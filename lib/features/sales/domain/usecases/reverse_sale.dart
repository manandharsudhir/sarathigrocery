import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/sales/domain/entities/credit_note.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

/// Shared reversal for cancelling a sale or recording a full return: puts
/// stock back, reverses the customer balance or refunds cash, and audits it.
/// Returns false if the sale was already cancelled/returned.
class ReverseSale {
  ReverseSale(this._sales, this._products, this._customers, this._cash, this._audit, this._books);

  final SaleRepository _sales;
  final ProductRepository _products;
  final CustomerRepository _customers;
  final CashRepository _cash;
  final AuditRepository _audit;
  final Books _books;

  /// A tax-invoiced sale is reversed by a numbered credit note ([creditNote]).
  bool call(Sale sale, SaleStatus newStatus, String reason, {required String userName, BillNumber? creditNote}) {
    if (sale.status != SaleStatus.completed) return false;
    if (sale.invoiceNumber != null && creditNote == null) throw StateError('A tax invoice is reversed with a credit note.');
    if (creditNote != null) {
      _sales.addCreditNote(CreditNote(
        id: nextId('CN'),
        date: DateTime.now(),
        sale: sale,
        number: creditNote.number,
        series: creditNote.series,
        seq: creditNote.seq,
        reason: reason,
        byName: userName,
      ));
    }

    for (final item in sale.items) {
      _products.increaseStock(item.product, item.baseQty);
    }

    if (sale.isCredit && sale.customer != null) {
      _customers.applyBalanceChange(sale.customer!, -sale.total);
    } else {
      _cash.addLedgerEntry(
        type: CashEntryType.refund,
        amount: sale.total,
        note: '${newStatus == SaleStatus.returned ? 'Return' : 'Cancellation'} refund for sale ${sale.id}',
        reference: sale.id,
        account: sale.account,
      );
    }
    _books.saleReversed(sale, newStatus == SaleStatus.returned ? 'Returned' : 'Cancelled', by: userName);

    _sales.setStatus(sale, newStatus);

    _audit.record(
      userName,
      newStatus == SaleStatus.returned ? 'Sale returned' : 'Sale cancelled',
      'Sale',
      entityId: sale.id,
      oldValue: 'completed',
      newValue: '${newStatus.name}${reason.isEmpty ? '' : ' - $reason'}',
    );
    return true;
  }
}
