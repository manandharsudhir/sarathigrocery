import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/settle_payment.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';

/// Records money a customer handed over — at the counter, or at the door
/// against [order]. Reduces the balance immediately (the customer has
/// paid), then the money is tracked until it reaches the till:
/// collectors with `reconcileCash` settle on the spot; anyone else's
/// collection waits for handover ([SettlePayment]).
class RecordPayment {
  RecordPayment(this._customers, this._payments, this._users, this._audit, this._notifications, this._settle);

  final CustomerRepository _customers;
  final PaymentRepository _payments;
  final UserRepository _users;
  final AuditRepository _audit;
  final NotificationRepository _notifications;
  final SettlePayment _settle;

  CustomerPayment call(
    Customer customer,
    double amount, {
    required PaymentMethod method,
    String reference = '',
    CustomerOrder? order,
    String? deliveryCode,
    required AppUser collector,
  }) {
    if (amount <= 0) throw PaymentException('Enter an amount greater than zero.');
    if (method != PaymentMethod.cash && reference.trim().isEmpty) {
      throw PaymentException('Enter the ${paymentMethodLabel(method)} reference so it can be verified.');
    }
    final atDoor = order != null && order.assignedToId == collector.id && collector.can(Permission.deliverOrders);
    if (!collector.can(Permission.recordPayments) && !atDoor) throw PaymentException('You are not allowed to record this payment.');
    if (order != null && order.customer.id != customer.id) throw PaymentException('That order belongs to another customer.');
    final code = deliveryCode?.trim();
    if (code != null && code.isNotEmpty && order == null) throw PaymentException('A delivery code only applies to an order.');

    final alreadyPaid = order == null
        ? 0.0
        : _payments.payments.where((p) => p.orderId == order.id && !p.isReversed).fold(0.0, (sum, p) => sum + p.amount);
    final orderDue = order == null ? 0.0 : (order.total - alreadyPaid).clamp(0.0, double.infinity);
    final appliedToOrder = amount < orderDue ? amount : orderDue;

    _customers.applyBalanceChange(customer, -amount, paymentDate: DateTime.now());

    final payment = CustomerPayment(
      id: nextId('PM'),
      date: DateTime.now(),
      customer: customer,
      amount: amount,
      method: method,
      reference: reference.trim(),
      orderId: order?.id,
      appliedToOrder: appliedToOrder,
      balanceAfter: customer.outstandingBalance,
      collectedById: collector.id,
      collectedByName: collector.name,
      deliveryCode: code == null || code.isEmpty ? null : code,
    );
    _payments.add(payment);

    _audit.record(collector.name, 'Payment recorded', 'Customer', entityId: customer.id,
        newValue: '${formatNpr(amount)} ${method.name}${order == null ? '' : ' for order ${order.id}'}${payment.confirmedByCode ? ' (code verified)' : ''}');

    final customerUserId = order?.placedByUserId ?? _users.userForCustomer(customer.id)?.id;
    if (customerUserId != null) {
      _notifications.notify(
        'Receipt: ${formatNpr(amount)} received',
        '${order == null ? '' : '${formatNpr(appliedToOrder)} for order ${order.id}, '}'
            '${formatNpr(payment.appliedToPreviousBalance)} toward earlier balance. Balance now ${formatNpr(payment.balanceAfter)}.'
            '${payment.confirmedByCode ? '' : ' Please confirm or report a problem in My Account.'}',
        userId: customerUserId,
      );
    }
    _notifications.notify('Payment collected', '${formatNpr(amount)} from ${customer.name} by ${collector.name}', role: UserRole.owner);

    if (collector.can(Permission.reconcileCash)) _settle(payment, amount, receiver: collector, atCollection: true);
    return payment;
  }
}
