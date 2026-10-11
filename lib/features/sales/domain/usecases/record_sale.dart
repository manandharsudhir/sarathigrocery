import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

class RecordSale {
  RecordSale(this._sales, this._products, this._customers, this._cash, this._audit, this._notifications, this._books);

  final SaleRepository _sales;
  final ProductRepository _products;
  final CustomerRepository _customers;
  final CashRepository _cash;
  final AuditRepository _audit;
  final NotificationRepository _notifications;
  final Books _books;

  /// Returns the recorded sale; [Sale.flaggedForApproval] marks an udharo
  /// sale past the customer's credit limit (allowed; the owner is told). Throws
  /// [BelowMinimumPriceException] for a line under its minimum price unless
  /// [allowBelowMinimum] (`Permission.sellBelowMinimum`).
  Sale call({
    required List<SaleItem> items,
    required bool isCredit,
    Customer? customer,
    required String userName,
    String? userId,
    bool allowBelowMinimum = false,
    String account = 'cash',
    VatTerms? vat,
    BillNumber? bill,
  }) {
    if (vat != null && bill == null) throw StateError('A VAT shop\'s sale needs a tax invoice number.');
    // ponytail: checked in the app only — rules can't loop over lines; a
    // Cloud Function (Blaze plan) would make it server-side.
    final unpriced = {for (final i in items) if (i.product.isUnpriced(i.unit)) i.product.name};
    if (unpriced.isNotEmpty) throw UnpricedProductException(unpriced.toList());
    final below = [for (final i in items) if (i.product.isBelowMinimum(i.unit, i.unitPrice)) i];
    if (below.isNotEmpty && !allowBelowMinimum) throw BelowMinimumPriceException([for (final i in below) '${i.product.name} (${i.unit})']);

    for (final item in items) {
      if (item.product.purchasePrice > 0) item.unitCost ??= item.product.purchasePrice * item.size;
    }
    final exempt = items.where((i) => i.product.vatExempt).fold(0.0, (sum, i) => sum + i.lineTotal);
    final lines = items.fold(0.0, (sum, i) => sum + i.lineTotal);
    final vatAmount = vatOn(lines - exempt, vat);
    final total = lines + (vat != null && !vat.included ? vatAmount : 0);
    final needsApproval = isCredit && customer != null && customer.outstandingBalance + total > customer.creditLimit;

    final sale = _sales.record(
      items: items,
      isCredit: isCredit,
      customer: customer,
      flaggedForApproval: needsApproval,
      createdByUserId: userId,
      createdByName: userName,
      account: isCredit && customer != null ? 'cash' : account,
      vatAmount: vatAmount,
      vatIncluded: vat?.included ?? true,
      exemptAmount: vat == null ? 0 : exempt,
      invoiceNumber: bill?.number,
      invoiceSeries: bill?.series,
      invoiceSeq: bill?.seq,
      buyerPan: customer?.pan ?? '',
    );
    _books.sale(sale);

    for (final item in items) {
      final wasLow = item.product.isLowStock;
      _products.decreaseStock(item.product, item.baseQty);
      if (!wasLow && item.product.isLowStock) {
        final left = 'Only ${item.product.describeQty(item.product.stockQty)} left.';
        _notifications.notify('Low stock: ${item.product.name}', left, role: UserRole.owner);
        _notifications.notify('Low stock: ${item.product.name}', left, role: UserRole.employee);
      }
    }

    if (isCredit && customer != null) {
      _customers.applyBalanceChange(customer, sale.total);
    } else {
      _cash.addLedgerEntry(
        type: CashEntryType.sale,
        amount: sale.total,
        note: 'Sale ${sale.id}${customer != null ? ' - ${customer.name}' : ''}',
        reference: sale.id,
        account: sale.account,
      );
    }

    _audit.record(userName, 'Sale recorded', 'Sale', entityId: sale.id, newValue: sale.total.toStringAsFixed(0));
    if (needsApproval) {
      _notifications.notify('Over credit limit', '${customer.name}: udharo sale by $userName takes them ${(customer.outstandingBalance - customer.creditLimit).toStringAsFixed(0)} over their limit.', role: UserRole.owner);
    }
    auditBelowMinimum(_audit, _notifications, userName, 'Sale', sale.id, [for (final i in below) (product: i.product.name, unit: i.unit, price: i.unitPrice, minimum: i.product.floorFor(i.unit) ?? 0)]);

    return sale;
  }
}

/// Records each below-minimum line (allowed for this seller) and tells the owner.
void auditBelowMinimum(
  AuditRepository audit,
  NotificationRepository notifications,
  String userName,
  String entity,
  String entityId,
  List<({String product, String unit, double price, double minimum})> lines,
) {
  for (final l in lines) {
    audit.record(userName, 'Sold below minimum price', entity, entityId: entityId, oldValue: '${l.product} ${l.unit} min ${l.minimum.toStringAsFixed(0)}', newValue: l.price.toStringAsFixed(0));
  }
  if (lines.isNotEmpty) {
    notifications.notify('Sold below minimum price', '$entity $entityId by $userName: ${[for (final l in lines) '${l.product} (${l.unit})'].join(', ')}', role: UserRole.owner);
  }
}
