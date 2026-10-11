import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

/// The business side of verification: [receiver] counted the cash into the
/// till ([counted] may be less than collected — the gap is a shortfall
/// against the collector) or checked the wallet/bank/cheque reference.
/// The counted amount enters the ledger on the account it arrived in.
class SettlePayment {
  SettlePayment(this._payments, this._cash, this._audit, this._notifications, this._guards, this._books);

  final PaymentRepository _payments;
  final CashRepository _cash;
  final AuditRepository _audit;
  final NotificationRepository _notifications;
  final bool Function(Safeguard) _guards;
  final Books _books;

  /// [atCollection]: the collector settles their own collection at once —
  /// they hold `reconcileCash` (they are the till), or the shop has
  /// [Safeguard.handover] off (no handover step, anyone counts it in).
  void call(CustomerPayment payment, double counted, {required AppUser receiver, bool atCollection = false}) {
    final handover = _guards(Safeguard.handover);
    if (!receiver.can(Permission.reconcileCash) && (handover || !atCollection)) throw PaymentException('You are not allowed to count cash in.');
    if (payment.isSettled || payment.isReversed) throw PaymentException('This payment is already closed.');
    // Separation of duties (handover safeguard): nobody receives their own
    // collection — except the owner, who in a one-person shop does both.
    if (handover && !atCollection && payment.collectedById == receiver.id && receiver.role != UserRole.owner) {
      throw PaymentException('Someone other than the collector must count this cash in.');
    }
    if (counted < 0 || counted > payment.amount) throw PaymentException('Counted amount must be between 0 and ${formatNpr(payment.amount)}.');

    payment
      ..settledAt = DateTime.now()
      ..settledAmount = counted
      ..settledById = receiver.id
      ..settledByName = receiver.name;
    _payments.update(payment);
    _books.paymentSettled(payment, ledgerAccountFor(payment.method));

    if (counted > 0) {
      _cash.addLedgerEntry(
        type: CashEntryType.collection,
        amount: counted,
        note: 'Collection from ${payment.customer.name} via ${payment.collectedByName}${payment.reference.isEmpty ? '' : ' · ${payment.reference}'}',
        reference: payment.id,
        account: ledgerAccountFor(payment.method),
      );
    }
    _audit.record(receiver.name, payment.method == PaymentMethod.cash ? 'Cash counted in' : 'Payment verified', 'Payment',
        entityId: payment.id, oldValue: formatNpr(payment.amount), newValue: formatNpr(counted));

    if (payment.shortfall > 0) {
      _audit.record(receiver.name, 'Cash missing', 'Payment', entityId: payment.id, newValue: '${formatNpr(payment.shortfall)} missing from ${payment.collectedByName}');
      _notifications.notify('Cash missing', '${payment.collectedByName} handed over ${formatNpr(counted)} of ${formatNpr(payment.amount)} collected from ${payment.customer.name}.', role: UserRole.owner);
    }
  }
}
