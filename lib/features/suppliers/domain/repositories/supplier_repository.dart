import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';

abstract class SupplierRepository {
  List<Supplier> get suppliers;

  double get totalPayable;

  Supplier create({required String name, required String businessName, required String phone, required String address, String productsSupplied = '', double amountPayable = 0});

  /// Raw payable mutation, no ledger/audit side effects.
  void applyPayableChange(Supplier supplier, double delta);
}
