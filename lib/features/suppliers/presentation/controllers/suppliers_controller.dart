import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';
import 'package:sarathigrocery/features/suppliers/domain/usecases/record_supplier_payment.dart';

class SuppliersController extends ChangeNotifier {
  SuppliersController(this._repository, AuditRepository audit, CashRepository cash)
      : _recordPayment = RecordSupplierPayment(_repository, cash, audit);

  final SupplierRepository _repository;
  final RecordSupplierPayment _recordPayment;

  SupplierRepository get repository => _repository;

  List<Supplier> get suppliers => _repository.suppliers;

  double get totalPayable => _repository.totalPayable;

  Supplier createSupplier({required String name, required String businessName, required String phone, required String address, String productsSupplied = ''}) {
    final supplier = _repository.create(name: name, businessName: businessName, phone: phone, address: address, productsSupplied: productsSupplied);
    notifyListeners();
    AppSignal.instance.ping();
    return supplier;
  }

  void recordPayment(Supplier supplier, double amount, String note, {required String userName}) {
    _recordPayment(supplier, amount, note, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
