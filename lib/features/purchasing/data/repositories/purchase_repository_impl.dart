import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/inventory/data/repositories/product_repository_impl.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_return.dart';
import 'package:sarathigrocery/features/purchasing/domain/repositories/purchase_repository.dart';
import 'package:sarathigrocery/features/suppliers/data/repositories/supplier_repository_impl.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';

class PurchaseRepositoryImpl implements PurchaseRepository {
  PurchaseRepositoryImpl(ProductRepositoryImpl products, SupplierRepositoryImpl suppliers)
      : _purchases = SyncedCollection<Purchase>(
          'purchases',
          idOf: (p) => p.id,
          toJson: (p) => {
            'date': toMillis(p.date),
            'supplierId': p.supplier.id,
            'items': [for (final i in p.items) {'productId': i.product.id, 'qty': i.qty, 'unitCost': i.unitCost}],
            'paidAmount': p.paidAmount,
          },
          fromJson: (j) {
            final supplier = suppliers.byId(j['supplierId']);
            if (supplier == null) return null;
            final items = <PurchaseItem>[];
            for (final i in (j['items'] as List? ?? const [])) {
              final product = products.byId(i['productId']);
              if (product == null) return null;
              items.add(PurchaseItem(product: product, qty: toInt(i['qty']), unitCost: toDouble(i['unitCost'])));
            }
            return Purchase(id: j['id'], date: fromMillis(j['date']), supplier: supplier, items: items, paidAmount: toDouble(j['paidAmount']));
          },
          merge: (p, j) => p.paidAmount = toDouble(j['paidAmount']),
        ),
        _returns = SyncedCollection<PurchaseReturn>(
          'purchaseReturns',
          idOf: (r) => r.id,
          toJson: (r) => {
            'date': toMillis(r.date),
            'supplierId': r.supplier.id,
            'productId': r.product.id,
            'qty': r.qty,
            'unitCost': r.unitCost,
            'reason': r.reason,
          },
          fromJson: (j) {
            final supplier = suppliers.byId(j['supplierId']);
            final product = products.byId(j['productId']);
            if (supplier == null || product == null) return null;
            return PurchaseReturn(id: j['id'], date: fromMillis(j['date']), supplier: supplier, product: product, qty: toInt(j['qty']), unitCost: toDouble(j['unitCost']), reason: j['reason'] ?? '');
          },
        );

  final SyncedCollection<Purchase> _purchases;
  final SyncedCollection<PurchaseReturn> _returns;

  List<SyncedCollection<Object?>> get collections => [_purchases, _returns];

  @override
  List<Purchase> get purchases => _purchases.items;

  @override
  List<PurchaseReturn> get purchaseReturns => _returns.items;

  @override
  Purchase record(Supplier supplier, List<PurchaseItem> items, double paidAmount) {
    final purchase = Purchase(id: nextId('PU'), date: DateTime.now(), supplier: supplier, items: items, paidAmount: paidAmount);
    _purchases.add(purchase);
    return purchase;
  }

  @override
  void recordReturn(PurchaseReturn purchaseReturn) => _returns.add(purchaseReturn);
}
