import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/purchasing/domain/repositories/purchase_repository.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';

/// Receives stock from a supplier: increases stock (and updates each
/// product's cost to the latest purchase price), increases the supplier's
/// payable by the unpaid amount, logs any amount paid now, audits, and
/// notifies the owner.
class CreatePurchase {
  CreatePurchase(this._purchases, this._products, this._suppliers, this._cash, this._audit, this._notifications);

  final PurchaseRepository _purchases;
  final ProductRepository _products;
  final SupplierRepository _suppliers;
  final CashRepository _cash;
  final AuditRepository _audit;
  final NotificationRepository _notifications;

  Purchase call(Supplier supplier, List<PurchaseItem> items, double paidAmount, {required String userName}) {
    final purchase = _purchases.record(supplier, items, paidAmount);

    for (final item in items) {
      _products.increaseStock(item.product, item.qty);
      _products.updateProduct(item.product, purchasePrice: item.unitCost);
    }

    _suppliers.applyPayableChange(supplier, purchase.remainingAmount);

    if (paidAmount > 0) {
      _cash.addLedgerEntry(
        type: CashEntryType.supplierPayment,
        amount: paidAmount,
        note: 'Purchase ${purchase.id} payment - ${supplier.name}',
        reference: purchase.id,
      );
    }

    _audit.record(userName, 'Purchase received', 'Purchase', entityId: purchase.id, newValue: purchase.total.toStringAsFixed(0));
    _notifications.notify('Stock received', 'Purchase ${purchase.id} received from ${supplier.name}', role: UserRole.owner);

    return purchase;
  }
}
