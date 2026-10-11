import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
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
  AdjustStock(this._products, this._audit, this._notifications, this._books);

  final ProductRepository _products;
  final AuditRepository _audit;
  final NotificationRepository _notifications;
  final Books _books;

  void call(Product product, AdjustmentType type, double qty, String note, {required String userName}) {
    final wasLow = product.isLowStock;
    final before = product.stockQty;

    _products.recordAdjustment(product, type, qty, note);
    _books.stockAdjusted(product, type == AdjustmentType.returned ? qty : -qty, '${type.name[0].toUpperCase()}${type.name.substring(1)}${note.isEmpty ? '' : ' ($note)'}', by: userName);

    _audit.record(userName, 'Stock adjusted', 'Product', entityId: product.id, oldValue: formatQty(before), newValue: formatQty(product.stockQty));

    if (!wasLow && product.isLowStock) {
      _notifications.notify('Low stock: ${product.name}', 'Only ${product.describeQty(product.stockQty)} left.', role: UserRole.owner);
      _notifications.notify('Low stock: ${product.name}', 'Only ${product.describeQty(product.stockQty)} left.', role: UserRole.employee);
    }
  }
}
