import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

/// The customer's side of verification, from their own app: confirm that
/// a recorded payment is right, or dispute it (which alerts the owner).
class RespondToPayment {
  RespondToPayment(this._payments, this._audit, this._notifications);

  final PaymentRepository _payments;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  void _checkOwner(CustomerPayment payment, AppUser customerUser) {
    if (customerUser.role != UserRole.customer || customerUser.linkedCustomerId != payment.customer.id) {
      throw PaymentException('Only ${payment.customer.name} can respond to this payment.');
    }
    if (payment.isReversed) throw PaymentException('This payment was reversed.');
  }

  void confirm(CustomerPayment payment, {required AppUser customerUser}) {
    _checkOwner(payment, customerUser);
    if (payment.isCustomerConfirmed || payment.isDisputed) throw PaymentException('You already responded to this payment.');
    payment.customerConfirmedAt = DateTime.now();
    _payments.update(payment);
    _audit.record(customerUser.name, 'Payment confirmed by customer', 'Payment', entityId: payment.id, newValue: formatNpr(payment.amount));
  }

  void dispute(CustomerPayment payment, String note, {required AppUser customerUser}) {
    _checkOwner(payment, customerUser);
    if (payment.isDisputed) throw PaymentException('You already reported a problem with this payment.');
    if (note.trim().isEmpty) throw PaymentException('Describe the problem, e.g. "I paid 7,000, not 5,000".');
    payment
      ..disputedAt = DateTime.now()
      ..disputeNote = note.trim();
    _payments.update(payment);
    _audit.record(customerUser.name, 'Payment disputed by customer', 'Payment', entityId: payment.id, newValue: note.trim());
    _notifications.notify('Payment disputed', '${payment.customer.name}: "${note.trim()}" (${formatNpr(payment.amount)} recorded by ${payment.collectedByName})', role: UserRole.owner);
  }
}
