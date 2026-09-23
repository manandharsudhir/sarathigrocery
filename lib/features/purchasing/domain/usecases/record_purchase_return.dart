import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_return.dart';
import 'package:sarathigrocery/features/purchasing/domain/repositories/purchase_repository.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';

class RecordPurchaseReturn {
  RecordPurchaseReturn(this._purchases, this._products, this._suppliers, this._audit);

  final PurchaseRepository _purchases;
  final ProductRepository _products;
  final SupplierRepository _suppliers;
  final AuditRepository _audit;

  void call(Supplier supplier, Product product, int qty, String reason, {required String userName}) {
    final unitCost = product.purchasePrice;
    _products.decreaseStock(product, qty);
    _suppliers.applyPayableChange(supplier, -(qty * unitCost));
    _purchases.recordReturn(PurchaseReturn(
      id: nextId('PR'),
      date: DateTime.now(),
      supplier: supplier,
      product: product,
      qty: qty,
      unitCost: unitCost,
      reason: reason,
    ));
    _audit.record(userName, 'Purchase returned', 'Purchase', entityId: product.id, newValue: '$qty ${product.unitLabel} to ${supplier.name}');
  }
}
