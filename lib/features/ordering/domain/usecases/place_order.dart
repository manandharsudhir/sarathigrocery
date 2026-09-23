import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';

/// Places an order from the current cart: reserves stock (without touching
/// [Product.stockQty] yet — final deduction happens on delivery), audits,
/// and notifies owner + employee of the new order.
class PlaceOrder {
  PlaceOrder(this._orders, this._products, this._audit, this._notifications);

  final OrderRepository _orders;
  final ProductRepository _products;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  CustomerOrder? call(Customer customer, {required DeliveryType deliveryType, String address = '', String notes = '', required String userName}) {
    if (_orders.cart.isEmpty) return null;

    final order = _orders.createOrder(
      customer: customer,
      items: List.of(_orders.cart),
      discountPercent: customer.defaultDiscountPercent,
      deliveryType: deliveryType,
      address: address,
      notes: notes,
    );

    for (final item in order.items) {
      _products.reserveStock(item.product, item.qty);
    }
    _orders.clearCart();

    _audit.record(userName, 'Order placed', 'Order', entityId: order.id, newValue: order.total.toStringAsFixed(0));
    _notifications.notify('New order', 'Order ${order.id} placed by ${customer.name}', role: UserRole.owner);
    _notifications.notify('New order', 'Order ${order.id} placed by ${customer.name}', role: UserRole.employee);

    return order;
  }
}
