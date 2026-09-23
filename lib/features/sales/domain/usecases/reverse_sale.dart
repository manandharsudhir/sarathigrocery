import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';

/// Shared reversal for cancelling a sale or recording a full return: puts
/// stock back, reverses the customer balance or refunds cash, and audits it.
/// Returns false if the sale was already cancelled/returned.
class ReverseSale {
  ReverseSale(this._sales, this._products, this._customers, this._cash, this._audit);

  final SaleRepository _sales;
  final ProductRepository _products;
  final CustomerRepository _customers;
  final CashRepository _cash;
  final AuditRepository _audit;

  bool call(Sale sale, SaleStatus newStatus, String reason, {required String userName}) {
    if (sale.status != SaleStatus.completed) return false;

    for (final item in sale.items) {
      _products.increaseStock(item.product, item.qty);
    }

    if (sale.isCredit && sale.customer != null) {
      _customers.applyBalanceChange(sale.customer!, -sale.total);
    } else {
      _cash.addLedgerEntry(
        type: CashEntryType.expense,
        amount: sale.total,
        note: '${newStatus == SaleStatus.returned ? 'Return' : 'Cancellation'} refund for sale ${sale.id}',
        reference: sale.id,
      );
    }

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
