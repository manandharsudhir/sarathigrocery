import 'package:sarathigrocery/core/utils/formatters.dart';
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
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';

/// Takes a purchase entered by mistake back out, whole: stock down (its
/// cost unwound from the weighted average), the supplier owed less, any
/// amount paid with it back in its account, the books reversed. Dated
/// today; the purchase stays, marked reversed.
class ReversePurchase {
  ReversePurchase(this._purchases, this._products, this._suppliers, this._cash, this._audit, this._notifications, this._books);

  final PurchaseRepository _purchases;
  final ProductRepository _products;
  final SupplierRepository _suppliers;
  final CashRepository _cash;
  final AuditRepository _audit;
  final NotificationRepository _notifications;
  final Books _books;

  /// Throws unless [purchase] can be reversed by this person ([owner]: any
  /// time; cash staff: today's only). [replacement]: the corrected lines
  /// saved with it — stock is checked after both, so a quantity typed too
  /// low can always be fixed even if the goods are sold.
  void check(Purchase purchase, String reason, {required bool owner, List<PurchaseItem> replacement = const []}) {
    if (purchase.isReversed) throw AccountingException('This purchase is already reversed.');
    if (reason.trim().isEmpty) throw AccountingException('Say why it is being reversed.');
    if (!owner && !isToday(purchase.date)) throw AccountingException('Only the owner can reverse a purchase from before today.');
    final change = <String, double>{};
    final products = {for (final i in [...purchase.items, ...replacement]) i.product.id: i.product};
    for (final i in purchase.items) {
      change[i.product.id] = (change[i.product.id] ?? 0) - i.baseQty;
    }
    for (final i in replacement) {
      change[i.product.id] = (change[i.product.id] ?? 0) + i.baseQty;
    }
    final short = [
      for (final MapEntry(key: id, value: delta) in change.entries)
        if (products[id]!.stockQty + delta < -1e-9) products[id]!.name,
    ];
    if (short.isNotEmpty) {
      throw AccountingException('Not enough stock of ${short.join(', ')} to take this purchase back out: stock is already off. Count it and adjust stock first.');
    }
  }

  void call(Purchase purchase, String reason, {required String userName, required bool owner, List<PurchaseItem> replacement = const []}) {
    check(purchase, reason, owner: owner, replacement: replacement);
    reason = reason.trim();
    _books.purchaseReversed(purchase, reason, by: userName);
    for (final item in purchase.items) {
      final p = item.product;
      final value = p.stockQty * p.purchasePrice;
      final left = p.stockQty - item.baseQty;
      // Weighted average in reverse. If the bill's cost can't come out of
      // what's left (already sold through at the blended cost), the gap is
      // written off so the books' stock value still equals qty × cost.
      final newValue = left > 0 ? (value - item.lineTotal).clamp(0.0, double.infinity) : left * p.purchasePrice;
      if (left > 0) _products.updateProduct(p, purchasePrice: newValue / left);
      _products.decreaseStock(p, item.baseQty);
      final gap = newValue - (value - item.lineTotal);
      if (gap.abs() > 0.005) _books.stockValueChanged(p, gap, 'Purchase ${purchase.id} reversed', by: userName);
    }
    _suppliers.applyPayableChange(purchase.supplier, -purchase.remainingAmount);
    for (final line in _cash.ledger.where((e) => e.type == CashEntryType.supplierPayment && e.reference == purchase.id && !e.isReversal).toList()) {
      _cash.addLedgerEntry(
        id: 'rev-${line.id}',
        type: line.type,
        amount: -line.amount,
        note: 'Reversed: ${line.note} – $reason',
        reference: purchase.id,
        account: line.account,
        journalId: 'rev-purchase-${purchase.id}',
        reverses: line.id,
      );
    }
    _purchases.markReversed(purchase, byName: userName, reason: reason);
    _audit.record(userName, 'Purchase reversed', 'Purchase', entityId: purchase.id, oldValue: formatNpr(purchase.total), newValue: reason);
    _notifications.notify('Purchase reversed', 'Purchase ${purchase.id} from ${purchase.supplier.name} (${formatNpr(purchase.total)}) reversed by $userName: $reason', role: UserRole.owner);
  }
}
