import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/domain/repositories/order_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/domain/usecases/record_sale.dart';

/// Staff take an order for a customer (phone/WhatsApp/in person): reserves
/// stock (without touching [Product.stockQty] yet — final deduction happens
/// on delivery), audits, and notifies owner + employee. An order is not debt,
/// so the credit limit is checked only on delivery ([AdvanceOrderStatus]).
class PlaceOrder {
  PlaceOrder(this._orders, this._products, this._audit, this._notifications);

  final OrderRepository _orders;
  final ProductRepository _products;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  /// Prices are fixed now. Throws [BelowMinimumPriceException] for a line
  /// under its minimum price unless [allowBelowMinimum].
  CustomerOrder? call(Customer customer, List<OrderItem> items,
      {required DeliveryType deliveryType, String address = '', String notes = '', required String staffName, bool allowBelowMinimum = false, VatTerms? vat}) {
    if (items.isEmpty) return null;
    final unpriced = {for (final i in items) if (i.product.isUnpriced(i.unit)) i.product.name};
    if (unpriced.isNotEmpty) throw UnpricedProductException(unpriced.toList());
    final below = [for (final i in items) if (i.product.isBelowMinimum(i.unit, i.price)) i];
    if (below.isNotEmpty && !allowBelowMinimum) throw BelowMinimumPriceException([for (final i in below) '${i.product.name} (${i.unit})']);

    final lines = items.fold(0.0, (sum, i) => sum + i.lineTotal);
    final exempt = items.where((i) => i.product.vatExempt).fold(0.0, (sum, i) => sum + i.lineTotal);
    final vatAmount = vatOn(lines - exempt, vat);

    final order = _orders.createOrder(
      customer: customer,
      items: items,
      deliveryType: deliveryType,
      address: address,
      notes: notes,
      placedByStaffName: staffName,
      vatAmount: vatAmount,
      vatIncluded: vat?.included ?? true,
      exemptAmount: vat == null ? 0 : exempt,
    );

    for (final item in order.items) {
      _products.reserveStock(item.product, item.baseQty);
    }

    _audit.record(staffName, 'Order placed', 'Order', entityId: order.id, newValue: order.total.toStringAsFixed(0));
    auditBelowMinimum(_audit, _notifications, staffName, 'Order', order.id, [for (final i in below) (product: i.product.name, unit: i.unit, price: i.price, minimum: i.product.floorFor(i.unit) ?? 0)]);
    final message = 'Order ${order.id} placed by $staffName for ${customer.name}';
    _notifications.notify('New order', message, role: UserRole.owner);
    _notifications.notify('New order', message, role: UserRole.employee);

    return order;
  }
}
