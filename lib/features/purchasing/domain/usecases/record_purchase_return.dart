import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_return.dart';
import 'package:sarathigrocery/features/purchasing/domain/repositories/purchase_repository.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';

class RecordPurchaseReturn {
  RecordPurchaseReturn(this._purchases, this._products, this._suppliers, this._audit, this._books);

  final PurchaseRepository _purchases;
  final ProductRepository _products;
  final SupplierRepository _suppliers;
  final AuditRepository _audit;
  final Books _books;

  void call(Supplier supplier, Product product, double qty, String reason, {required String userName}) {
    final unitCost = product.purchasePrice;
    _products.decreaseStock(product, qty);
    _suppliers.applyPayableChange(supplier, -(qty * unitCost));
    final record = PurchaseReturn(
      id: nextId('PR'),
      date: DateTime.now(),
      supplier: supplier,
      product: product,
      qty: qty,
      unitCost: unitCost,
      reason: reason,
    );
    _purchases.recordReturn(record);
    _books.purchaseReturn(record, by: userName);
    _audit.record(userName, 'Purchase returned', 'Purchase', entityId: product.id, newValue: '${product.describeQty(qty)} to ${supplier.name}');
  }
}
