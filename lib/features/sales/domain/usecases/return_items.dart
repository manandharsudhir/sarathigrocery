import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

/// A customer brings some items of a counter sale back: recorded like goods
/// refused at the door, as negative lines against the bill ([Sale.returnOf]),
/// with a credit note in a VAT shop. Stock comes back; an udharo bill owes
/// less, a paid one is refunded from the account it was paid into.
class ReturnItems {
  ReturnItems(this._sales, this._products, this._customers, this._cash, this._audit, this._books);

  final SaleRepository _sales;
  final ProductRepository _products;
  final CustomerRepository _customers;
  final CashRepository _cash;
  final AuditRepository _audit;
  final Books _books;

  /// What is still on [sale] per line (sold minus already returned).
  List<double> remaining(Sale sale) {
    final left = [for (final i in sale.items) i.qty];
    for (final r in _sales.sales.where((r) => r.returnOf == sale.id && r.status == SaleStatus.completed)) {
      for (final i in r.items) {
        final at = sale.items.indexWhere((s) => s.product.id == i.product.id && s.unit == i.unit && s.unitPrice == i.unitPrice);
        if (at >= 0) left[at] += i.qty;
      }
    }
    return left;
  }

  /// Throws unless [returned] (sale line index → quantity in that line's
  /// unit) can come back from [sale].
  void check(Sale sale, Map<int, double> returned, String reason, {VatTerms? vat, BillNumber? creditNote}) {
    if (sale.status != SaleStatus.completed || sale.isDoorReturn) throw AccountingException('Only a completed sale can take items back.');
    if (sale.orderId != null) throw AccountingException('Goods from an order come back through the order (Some items refused).');
    if (reason.trim().isEmpty) throw AccountingException('Say why the items came back.');
    if (sale.invoiceNumber != null && creditNote == null) throw StateError('Returns on a tax invoice need a credit note number.');
    if (!returned.values.any((q) => q > 0)) throw AccountingException('Enter how many came back.');
    final left = remaining(sale);
    for (final MapEntry(key: i, value: q) in returned.entries) {
      if (q > left[i] + 1e-9) throw AccountingException('More ${sale.items[i].product.name} than is left on the bill.');
    }
    final untouched = !_sales.sales.any((r) => r.returnOf == sale.id && r.status == SaleStatus.completed);
    if (untouched && [for (var i = 0; i < left.length; i++) left[i] - (returned[i] ?? 0)].every((q) => q.abs() < 1e-9)) {
      throw AccountingException('That is everything on the bill: use Return (whole sale) instead.');
    }
  }

  Sale call(Sale sale, Map<int, double> returned, String reason, {required String userName, String? userId, VatTerms? vat, BillNumber? creditNote}) {
    check(sale, returned, reason, vat: vat, creditNote: creditNote);
    final lines = <SaleItem>[
      for (final MapEntry(key: i, value: q) in returned.entries)
        if (q > 0)
          SaleItem(
            product: sale.items[i].product,
            qty: -q,
            unitPrice: sale.items[i].unitPrice,
            unit: sale.items[i].unit,
            size: sale.items[i].size,
            unitCost: sale.items[i].unitCost,
          ),
    ];
    final exempt = lines.where((i) => i.product.vatExempt).fold(0.0, (sum, i) => sum + i.lineTotal);
    final taxable = lines.fold(0.0, (sum, i) => sum + i.lineTotal) - exempt;
    final back = _sales.record(
      items: lines,
      isCredit: sale.isCredit,
      customer: sale.customer,
      flaggedForApproval: false,
      createdByUserId: userId,
      createdByName: userName,
      account: sale.account,
      vatAmount: sale.vatAmount == 0 || vat == null ? 0.0 : -vatOn(-taxable, vat),
      vatIncluded: sale.vatIncluded,
      exemptAmount: sale.vatAmount == 0 ? 0 : exempt,
      invoiceNumber: creditNote?.number,
      invoiceSeries: creditNote?.series,
      invoiceSeq: creditNote?.seq,
      buyerPan: sale.buyerPan,
      returnOf: sale.id,
    );
    for (final i in lines) {
      _products.increaseStock(i.product, -i.baseQty);
    }
    if (sale.isCredit && sale.customer != null) {
      _customers.applyBalanceChange(sale.customer!, back.total);
    } else {
      _cash.addLedgerEntry(type: CashEntryType.refund, amount: -back.total, note: 'Items returned on sale ${sale.invoiceNumber ?? sale.id}', reference: back.id, account: sale.account);
    }
    _books.sale(back);
    _audit.record(userName, 'Items returned', 'Sale', entityId: back.id,
        oldValue: sale.invoiceNumber ?? sale.id, newValue: '${[for (final i in lines) '${i.product.name} ${-i.qty} ${i.unit}'].join(', ')} (${(-back.total).toStringAsFixed(0)}) – ${reason.trim()}');
    return back;
  }
}
