import 'dart:math';

import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';

final _codeRandom = Random.secure();

/// Places an order from the current cart: reserves stock (without touching
/// [Product.stockQty] yet — final deduction happens on delivery), issues a
/// secret delivery code for the customer, flags it if it would take the
/// customer past their credit limit, audits, and notifies owner + employee.
class PlaceOrder {
  PlaceOrder(this._orders, this._products, this._audit, this._notifications);

  final OrderRepository _orders;
  final ProductRepository _products;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  /// Balance + undelivered orders — what the customer would owe if every
  /// open order were delivered on credit.
  double creditExposure(Customer customer) =>
      customer.outstandingBalance +
      _orders.orders
          .where((o) => o.customer.id == customer.id && o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled)
          .fold(0.0, (sum, o) => sum + o.total);

  CustomerOrder? call(Customer customer, {required DeliveryType deliveryType, String address = '', String notes = '', required String userName, String? userId}) {
    if (_orders.cart.isEmpty) return null;

    final subtotal = _orders.cart.fold(0.0, (sum, i) => sum + i.lineTotal);
    final total = subtotal - subtotal * customer.defaultDiscountPercent / 100;
    final overLimit = creditExposure(customer) + total > customer.creditLimit;

    final order = _orders.createOrder(
      customer: customer,
      items: List.of(_orders.cart),
      discountPercent: customer.defaultDiscountPercent,
      deliveryType: deliveryType,
      address: address,
      notes: notes,
      placedByUserId: userId,
      overCreditLimit: overLimit,
    );
    _orders.saveDeliveryCode(order, _codeRandom.nextInt(1000000).toString().padLeft(6, '0'));

    for (final item in order.items) {
      _products.reserveStock(item.product, item.qty);
    }
    _orders.clearCart();

    _audit.record(userName, 'Order placed', 'Order', entityId: order.id, newValue: order.total.toStringAsFixed(0));
    final note = overLimit ? ' — over credit limit, needs approval' : '';
    _notifications.notify('New order', 'Order ${order.id} placed by ${customer.name}$note', role: UserRole.owner);
    _notifications.notify('New order', 'Order ${order.id} placed by ${customer.name}$note', role: UserRole.employee);

    return order;
  }
}
