import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';

void _mergeSupplier(Supplier s, Json j) {
  s
    ..name = j['name'] ?? ''
    ..businessName = j['businessName'] ?? ''
    ..phone = j['phone'] ?? ''
    ..address = j['address'] ?? ''
    ..productsSupplied = j['productsSupplied'] ?? ''
    ..amountPayable = toDouble(j['amountPayable']);
}

class SupplierRepositoryImpl implements SupplierRepository {
  final _suppliers = SyncedCollection<Supplier>(
    'suppliers',
    idOf: (s) => s.id,
    toJson: (s) => {
      'name': s.name,
      'businessName': s.businessName,
      'phone': s.phone,
      'address': s.address,
      'productsSupplied': s.productsSupplied,
      'amountPayable': s.amountPayable,
    },
    fromJson: (j) {
      final s = Supplier(id: j['id'], name: '', businessName: '', phone: '', address: '');
      _mergeSupplier(s, j);
      return s;
    },
    merge: _mergeSupplier,
    counters: {'amountPayable'},
  );

  List<SyncedCollection<Object?>> get collections => [_suppliers];

  @override
  List<Supplier> get suppliers => _suppliers.items;

  Supplier? byId(String? id) => _suppliers.byId(id);

  @override
  double get totalPayable => suppliers.fold(0.0, (sum, s) => sum + s.amountPayable);

  @override
  Supplier create({required String name, required String businessName, required String phone, required String address, String productsSupplied = '', double amountPayable = 0}) {
    final supplier = Supplier(id: nextId('SU'), name: name, businessName: businessName, phone: phone, address: address, productsSupplied: productsSupplied, amountPayable: amountPayable);
    _suppliers.add(supplier);
    return supplier;
  }

  @override
  void applyPayableChange(Supplier supplier, double delta) {
    supplier.amountPayable += delta;
    _suppliers.increment(supplier, {'amountPayable': delta});
  }
}
