import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

/// The business side of verification: [receiver] counted the cash into the
/// till ([counted] may be less than collected — the gap is a shortfall
/// against the collector) or checked the wallet/bank/cheque reference.
/// The counted amount enters the ledger on the account it arrived in.
class SettlePayment {
  SettlePayment(this._payments, this._cash, this._audit, this._notifications);

  final PaymentRepository _payments;
  final CashRepository _cash;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  /// [atCollection]: a collector with `reconcileCash` (owner/accountant)
  /// is the till themselves, so their own collection settles immediately.
  void call(CustomerPayment payment, double counted, {required AppUser receiver, bool atCollection = false}) {
    if (!receiver.can(Permission.reconcileCash)) throw PaymentException('You are not allowed to receive handovers.');
    if (payment.isSettled || payment.isReversed) throw PaymentException('This payment is already closed.');
    // Separation of duties: nobody receives their own collection — except
    // the owner, who in a one-person shop does both.
    if (!atCollection && payment.collectedById == receiver.id && receiver.role != UserRole.owner) {
      throw PaymentException('Someone other than the collector must receive this.');
    }
    if (counted < 0 || counted > payment.amount) throw PaymentException('Counted amount must be between 0 and ${formatNpr(payment.amount)}.');

    payment
      ..settledAt = DateTime.now()
      ..settledAmount = counted
      ..settledById = receiver.id
      ..settledByName = receiver.name;
    _payments.update(payment);

    if (counted > 0) {
      _cash.addLedgerEntry(
        type: CashEntryType.collection,
        amount: counted,
        note: 'Collection from ${payment.customer.name} via ${payment.collectedByName}${payment.reference.isEmpty ? '' : ' · ${payment.reference}'}',
        reference: payment.id,
        account: ledgerAccountFor(payment.method),
      );
    }
    _audit.record(receiver.name, payment.method == PaymentMethod.cash ? 'Cash received into till' : 'Payment verified', 'Payment',
        entityId: payment.id, oldValue: formatNpr(payment.amount), newValue: formatNpr(counted));

    if (payment.shortfall > 0) {
      _audit.record(receiver.name, 'Cash shortfall', 'Payment', entityId: payment.id, newValue: '${formatNpr(payment.shortfall)} short from ${payment.collectedByName}');
      _notifications.notify('Cash shortfall', '${payment.collectedByName} handed over ${formatNpr(counted)} of ${formatNpr(payment.amount)} collected from ${payment.customer.name}.', role: UserRole.owner);
    }
  }
}
