import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

/// Logs a manual stock adjustment (damaged/expired/returned goods), audits
/// it, and notifies owner + employee if it just pushed the product into
/// low-stock territory.
class AdjustStock {
  AdjustStock(this._products, this._audit, this._notifications);

  final ProductRepository _products;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  void call(Product product, AdjustmentType type, int qty, String note, {required String userName}) {
    final wasLow = product.isLowStock;
    final before = product.stockQty;

    _products.recordAdjustment(product, type, qty, note);

    _audit.record(userName, 'Stock adjusted', 'Product', entityId: product.id, oldValue: '$before', newValue: '${product.stockQty}');

    if (!wasLow && product.isLowStock) {
      _notifications.notify('Low stock: ${product.name}', 'Only ${product.stockQty} ${product.unitLabel} left.', role: UserRole.owner);
      _notifications.notify('Low stock: ${product.name}', 'Only ${product.stockQty} ${product.unitLabel} left.', role: UserRole.employee);
    }
  }
}
