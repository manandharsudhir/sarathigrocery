import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';

/// Advances (or cancels) an order. Cancelling releases any reserved stock;
/// marking delivered finalizes the reservation into an actual stock
/// deduction. Notifies the linked customer login, if any.
class AdvanceOrderStatus {
  AdvanceOrderStatus(this._orders, this._products, this._audit, this._notifications, this._users);

  final OrderRepository _orders;
  final ProductRepository _products;
  final AuditRepository _audit;
  final NotificationRepository _notifications;
  final UserRepository _users;

  void call(CustomerOrder order, OrderStatus newStatus, {required String userName}) {
    final oldStatus = order.status;
    if (oldStatus == newStatus) return;

    if (newStatus == OrderStatus.cancelled && oldStatus != OrderStatus.delivered) {
      for (final item in order.items) {
        _products.releaseReservation(item.product, item.qty);
      }
    }
    if (newStatus == OrderStatus.delivered) {
      for (final item in order.items) {
        _products.releaseReservation(item.product, item.qty);
        _products.decreaseStock(item.product, item.qty);
      }
    }

    _orders.setStatus(order, newStatus);

    _audit.record(userName, 'Order status changed', 'Order', entityId: order.id, oldValue: oldStatus.name, newValue: newStatus.name);

    final customerUser = _users.userForCustomer(order.customer.id);
    _notifications.notify('Order ${order.id} ${newStatus.name}', 'Your order is now ${newStatus.name}.', userId: customerUser?.id);
  }
}
