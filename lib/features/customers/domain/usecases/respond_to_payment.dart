import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

/// The customer's side of verification: from their own app (confirm /
/// dispute), or — for customers without the app — by a phone call from
/// staff who didn't collect the money.
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
    _dispute(payment, note, byName: customerUser.name, audit: 'Payment disputed by customer');
  }

  void _dispute(CustomerPayment payment, String note, {required String byName, required String audit}) {
    payment
      ..disputedAt = DateTime.now()
      ..disputeNote = note.trim()
      ..disputedByName = byName;
    _payments.update(payment);
    _audit.record(byName, audit, 'Payment', entityId: payment.id, newValue: note.trim());
    _notifications.notify('Payment disputed', '${payment.customer.name}: "${note.trim()}" (${formatNpr(payment.amount)} recorded by ${payment.collectedByName})', role: UserRole.owner);
  }

  /// Staff who can receive money (owner/accountant), and didn't collect
  /// this payment, phoned the customer to check it.
  void _checkCaller(CustomerPayment payment, AppUser staff) {
    if (!staff.can(Permission.reconcileCash)) throw PaymentException('Only the owner or accountant can confirm by phone.');
    if (staff.id == payment.collectedById) throw PaymentException('Someone other than the collector must call the customer.');
    if (payment.isReversed) throw PaymentException('This payment was reversed.');
  }

  void confirmByPhone(CustomerPayment payment, {required AppUser staff}) {
    _checkCaller(payment, staff);
    if (payment.isCustomerConfirmed || payment.isDisputed) throw PaymentException('This payment is already confirmed or disputed.');
    payment
      ..phoneConfirmedAt = DateTime.now()
      ..phoneConfirmedByName = staff.name;
    _payments.update(payment);
    _audit.record(staff.name, 'Payment confirmed by phone call', 'Payment', entityId: payment.id, newValue: '${formatNpr(payment.amount)} · ${payment.customer.name}');
  }

  /// The customer told staff on the phone that the recorded payment is wrong.
  void disputeOnBehalf(CustomerPayment payment, String note, {required AppUser staff}) {
    _checkCaller(payment, staff);
    if (payment.isDisputed) throw PaymentException('Already disputed.');
    if (note.trim().isEmpty) throw PaymentException('Write down what the customer said.');
    _dispute(payment, note, byName: '${staff.name} (phone call)', audit: 'Payment disputed by customer on a call');
  }
}
