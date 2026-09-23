import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

/// Owner-only correction of a payment recorded in error (wrong customer,
/// wrong amount, disputed and found invalid). Never deletes: the payment
/// stays on both statements, marked reversed, and the balance goes back up.
/// If it was already counted into the till / bank, a refund entry takes
/// that amount back out (returned to the customer, or re-recorded
/// correctly as a new payment), so the ledger still matches reality.
class ReversePayment {
  ReversePayment(this._customers, this._payments, this._cash, this._users, this._audit, this._notifications);

  final CustomerRepository _customers;
  final PaymentRepository _payments;
  final CashRepository _cash;
  final UserRepository _users;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  void call(CustomerPayment payment, String reason, {required AppUser owner}) {
    if (owner.role != UserRole.owner) throw PaymentException('Only the owner can reverse a payment.');
    if (payment.isReversed) throw PaymentException('Already reversed.');
    if (reason.trim().isEmpty) throw PaymentException('Give a reason — the customer will see it.');

    payment
      ..reversedAt = DateTime.now()
      ..reversedByName = owner.name
      ..reversalReason = reason.trim();
    _payments.update(payment);
    _customers.applyBalanceChange(payment.customer, payment.amount);
    final settled = payment.settledAmount ?? 0;
    if (payment.isSettled && settled > 0) {
      _cash.addLedgerEntry(
        type: CashEntryType.refund,
        amount: settled,
        note: 'Reversal of payment from ${payment.customer.name}: ${reason.trim()}',
        reference: payment.id,
        account: ledgerAccountFor(payment.method),
      );
    }

    _audit.record(owner.name, 'Payment reversed', 'Payment', entityId: payment.id, oldValue: formatNpr(payment.amount), newValue: reason.trim());
    final customerUser = _users.userForCustomer(payment.customer.id);
    if (customerUser != null) {
      _notifications.notify('Payment reversed', '${formatNpr(payment.amount)} from ${formatDate(payment.date)} was reversed: ${reason.trim()}', userId: customerUser.id);
    }
  }
}
