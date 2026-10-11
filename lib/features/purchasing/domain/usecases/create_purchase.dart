import 'package:sarathigrocery/features/accounting/domain/books.dart';
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

/// Receives stock from a supplier: increases stock (and moves each
/// product's cost to the weighted average of old stock and this purchase), increases the supplier's
/// payable by the unpaid amount, logs any amount paid now, audits, and
/// notifies the owner.
class CreatePurchase {
  CreatePurchase(this._purchases, this._products, this._suppliers, this._cash, this._audit, this._notifications, this._books);

  final PurchaseRepository _purchases;
  final ProductRepository _products;
  final SupplierRepository _suppliers;
  final CashRepository _cash;
  final AuditRepository _audit;
  final NotificationRepository _notifications;
  final Books _books;

  Purchase call(Supplier supplier, List<PurchaseItem> items, double paidAmount,
      {required String userName, String account = 'cash', double vatAmount = 0, String supplierBillNo = '', DateTime? supplierBillDate}) {
    final purchase = _purchases.record(supplier, items, paidAmount,
        account: account, vatAmount: vatAmount, supplierBillNo: supplierBillNo, supplierBillDate: supplierBillDate);

    for (final item in items) {
      final p = item.product;
      final before = p.stockQty;
      // Weighted average cost; stock at or below zero restarts at this price.
      final cost = before > 0 ? (before * p.purchasePrice + item.lineTotal) / (before + item.baseQty) : item.unitCost / item.size;
      _products.increaseStock(p, item.baseQty);
      _products.updateProduct(p, purchasePrice: cost);
    }
    _books.purchase(purchase, by: userName);

    _suppliers.applyPayableChange(supplier, purchase.remainingAmount);

    if (paidAmount > 0) {
      _cash.addLedgerEntry(
        type: CashEntryType.supplierPayment,
        amount: paidAmount,
        note: 'Purchase ${purchase.id} payment - ${supplier.name}',
        reference: purchase.id,
        account: account,
      );
    }

    _audit.record(userName, 'Purchase received', 'Purchase', entityId: purchase.id, newValue: purchase.total.toStringAsFixed(0));
    _notifications.notify('Stock received', 'Purchase ${purchase.id} received from ${supplier.name}', role: UserRole.owner);

    return purchase;
  }
}
