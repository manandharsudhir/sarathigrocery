import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/cash/domain/usecases/reverse_cash_entry.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';
import 'package:sarathigrocery/features/suppliers/domain/usecases/record_supplier_payment.dart';

class SuppliersController extends ChangeNotifier {
  SuppliersController(this._repository, AuditRepository audit, this._cash, Books books)
      : _recordPayment = RecordSupplierPayment(_repository, _cash, audit, books),
        _reverse = ReverseCashEntry(_cash, books, audit);

  final SupplierRepository _repository;
  final CashRepository _cash;
  final RecordSupplierPayment _recordPayment;
  final ReverseCashEntry _reverse;

  SupplierRepository get repository => _repository;

  List<Supplier> get suppliers => _repository.suppliers;

  double get totalPayable => _repository.totalPayable;

  Supplier createSupplier({required String name, required String businessName, required String phone, required String address, String productsSupplied = '', String pan = ''}) {
    final supplier = _repository.create(name: name, businessName: businessName, phone: phone, address: address, productsSupplied: productsSupplied, pan: pan.trim());
    notifyListeners();
    AppSignal.instance.ping();
    return supplier;
  }

  void recordPayment(Supplier supplier, double amount, String note, {required String userName, String account = 'cash'}) {
    _recordPayment(supplier, amount, note, userName: userName, account: account);
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// Payments made to [supplier] directly (not with a purchase), newest first.
  List<CashLedgerEntry> paymentsTo(Supplier supplier) =>
      _cash.ledger.where((e) => e.type == CashEntryType.supplierPayment && e.reference == supplier.id && !e.isReversal).toList().reversed.toList();

  CashLedgerEntry? reversalOf(CashLedgerEntry payment) => _cash.reversalOf(payment);

  /// A payment of the same amount to [supplier] already today, or null.
  CashLedgerEntry? similarPaymentToday(Supplier supplier, double amount) =>
      paymentsTo(supplier).where((e) => isToday(e.date) && _cash.reversalOf(e) == null && (e.amount - amount).abs() < 0.005).firstOrNull;

  /// Why [payment] can't be reversed by this person, or null.
  String? reverseProblem(CashLedgerEntry payment, {required bool owner}) {
    try {
      _reverse.check(payment, 'x', owner: owner);
      return null;
    } on AccountingException catch (e) {
      return e.message;
    }
  }

  /// Undoes a supplier payment entered by mistake: the money goes back to
  /// its account and the supplier is owed it again.
  void reversePayment(Supplier supplier, CashLedgerEntry payment, String reason, {required String userName, required bool owner}) {
    if (payment.type != CashEntryType.supplierPayment || payment.reference != supplier.id) throw AccountingException('Undo this from its purchase.');
    _reverse(payment, reason, userName: userName, owner: owner);
    _repository.applyPayableChange(supplier, payment.amount);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
