import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

/// Advances (or cancels) an order. Cancelling releases reserved stock.
/// Delivering finalizes the reservation into a stock deduction AND bills
/// the customer: an invoice (credit sale linked to the order) is recorded
/// and the order total goes onto their balance. Whatever they pay at the
/// door is then recorded as a payment against that balance.
class AdvanceOrderStatus {
  AdvanceOrderStatus(this._orders, this._products, this._sales, this._customers, this._audit, this._notifications, this._users);

  final OrderRepository _orders;
  final ProductRepository _products;
  final SaleRepository _sales;
  final CustomerRepository _customers;
  final AuditRepository _audit;
  final NotificationRepository _notifications;
  final UserRepository _users;

  void call(CustomerOrder order, OrderStatus newStatus, {required String userName, String? userId}) {
    final oldStatus = order.status;
    if (oldStatus == newStatus || oldStatus == OrderStatus.delivered || oldStatus == OrderStatus.cancelled) return;

    if (newStatus == OrderStatus.cancelled) {
      for (final item in order.items) {
        _products.releaseReservation(item.product, item.qty);
      }
    }
    if (newStatus == OrderStatus.delivered) {
      for (final item in order.items) {
        _products.releaseReservation(item.product, item.qty);
        _products.decreaseStock(item.product, item.qty);
      }
      invoice(order, userName: userName, userId: userId);
    }

    _orders.setStatus(order, newStatus);

    _audit.record(userName, 'Order status changed', 'Order', entityId: order.id, oldValue: oldStatus.name, newValue: newStatus.name);

    final customerUserId = order.placedByUserId ?? _users.userForCustomer(order.customer.id)?.id;
    if (customerUserId != null) {
      _notifications.notify('Order ${order.id}: ${orderStatusLabel(newStatus)}', 'Your order is now ${orderStatusLabel(newStatus).toLowerCase()}.', userId: customerUserId);
    }
  }

  /// Delivered orders with no invoice — delivered before delivery started
  /// billing customers. Their stock was already deducted back then.
  List<CustomerOrder> uninvoiced() {
    final invoiced = {for (final s in _sales.sales) s.orderId};
    return _orders.orders.where((o) => o.status == OrderStatus.delivered && !invoiced.contains(o.id)).toList();
  }

  /// Bills a delivered order onto the customer's balance: a credit sale
  /// linked to the order.
  void invoice(CustomerOrder order, {required String userName, String? userId}) {
    final sale = _sales.record(
      items: [for (final i in order.items) SaleItem(product: i.product, qty: i.qty, unitPrice: i.price)],
      discountPercent: order.discountPercent,
      isCredit: true,
      customer: order.customer,
      flaggedForApproval: order.overCreditLimit,
      createdByUserId: userId,
      createdByName: userName,
      orderId: order.id,
    );
    _customers.applyBalanceChange(order.customer, sale.total);
    _audit.record(userName, 'Order invoiced', 'Sale', entityId: sale.id, newValue: '${sale.total.toStringAsFixed(0)} for order ${order.id}');
  }
}
