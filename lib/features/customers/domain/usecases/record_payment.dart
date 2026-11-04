import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/customers/domain/usecases/settle_payment.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

/// Records money a customer handed over — at the counter, or at the door
/// against [order], or against a bill ([sale]: part paid with the sale, or
/// collected later from the sales list). Reduces the balance immediately (the customer has
/// paid), then the money is tracked until it reaches the till:
/// collectors with `reconcileCash` settle on the spot; anyone else's
/// collection waits for handover ([SettlePayment]) — unless the shop's
/// [Safeguard.handover] is off, when every collection settles on the spot.
/// Unsigned payments need a phone check only with [Safeguard.phoneConfirm].
class RecordPayment {
  RecordPayment(this._customers, this._payments, this._audit, this._notifications, this._settle, this._guards, this._books);

  final CustomerRepository _customers;
  final PaymentRepository _payments;
  final AuditRepository _audit;
  final NotificationRepository _notifications;
  final SettlePayment _settle;
  final bool Function(Safeguard) _guards;
  final Books _books;

  CustomerPayment call(
    Customer customer,
    double amount, {
    required PaymentMethod method,
    String reference = '',
    CustomerOrder? order,
    Sale? sale,
    String? signature,
    String signedName = '',
    required AppUser collector,
  }) {
    if (amount <= 0) throw PaymentException('Enter an amount greater than zero.');
    if (method != PaymentMethod.cash && reference.trim().isEmpty) {
      throw PaymentException('Enter the ${paymentMethodLabel(method)} reference so it can be verified.');
    }
    final atDoor = order != null && order.assignedToId == collector.id && collector.can(Permission.deliverOrders);
    if (!collector.can(Permission.recordPayments) && !atDoor) throw PaymentException('You are not allowed to record this payment.');
    if (order != null && order.customer.id != customer.id) throw PaymentException('That order belongs to another customer.');
    if (sale != null && (sale.customer?.id != customer.id || !sale.isCredit)) throw PaymentException('That bill isn\'t on this customer\'s account.');

    final billTotal = order?.total ?? sale?.total ?? 0.0;
    final alreadyPaid = _payments.payments
        .where((p) => !p.isReversed && ((order != null && p.orderId == order.id) || (sale != null && (p.saleId == sale.id || (sale.orderId != null && p.orderId == sale.orderId)))))
        .fold(0.0, (sum, p) => sum + p.amount);
    final orderDue = (billTotal - alreadyPaid).clamp(0.0, double.infinity);
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
      saleId: sale?.id,
      appliedToOrder: appliedToOrder,
      balanceAfter: customer.outstandingBalance,
      collectedById: collector.id,
      collectedByName: collector.name,
      signature: signature,
      signedName: signedName.trim(),
      autoConfirmed: signature == null && !_guards(Safeguard.phoneConfirm),
    );
    _payments.add(payment);
    _books.paymentRecorded(payment);

    _audit.record(collector.name, 'Payment recorded', 'Customer', entityId: customer.id,
        newValue: '${formatNpr(amount)} ${method.name}${order == null ? '' : ' for order ${order.id}'}${sale == null ? '' : ' for bill ${sale.invoiceNumber ?? sale.id}'}${payment.confirmedBySignature ? ' (signed)' : ''}');

    _notifications.notify('Payment collected', '${formatNpr(amount)} from ${customer.name} by ${collector.name}', role: UserRole.owner);

    if (collector.can(Permission.reconcileCash) || !_guards(Safeguard.handover)) _settle(payment, amount, receiver: collector, atCollection: true);
    return payment;
  }
}
