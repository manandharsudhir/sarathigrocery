import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';

class RecordSupplierPayment {
  RecordSupplierPayment(this._suppliers, this._cash, this._audit, this._books);

  final SupplierRepository _suppliers;
  final CashRepository _cash;
  final AuditRepository _audit;
  final Books _books;

  void call(Supplier supplier, double amount, String note, {required String userName, String account = 'cash'}) {
    _suppliers.applyPayableChange(supplier, -amount);
    _cash.addLedgerEntry(
      type: CashEntryType.supplierPayment,
      amount: amount,
      note: note.isEmpty ? 'Payment to ${supplier.name}' : note,
      reference: supplier.id,
      account: account,
    );
    _books.supplierPaid(supplier.id, supplier.name, amount, account, by: userName);
    _audit.record(userName, 'Supplier payment recorded', 'Supplier', entityId: supplier.id, newValue: amount.toStringAsFixed(0));
  }
}
