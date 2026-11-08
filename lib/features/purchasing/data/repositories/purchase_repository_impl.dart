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
            'items': [for (final i in p.items) {'productId': i.product.id, 'qty': i.qty, 'unitCost': i.unitCost, 'unit': i.unit, 'size': i.size}],
            'paidAmount': p.paidAmount,
            'account': p.account,
            'vatAmount': p.vatAmount,
            'supplierBillNo': p.supplierBillNo,
            'supplierBillDate': p.supplierBillDate == null ? null : toMillis(p.supplierBillDate!),
            if (p.corrects != null) 'corrects': p.corrects,
            if (p.reversedAt != null) ...{'reversedAt': toMillis(p.reversedAt!), 'reversedByName': p.reversedByName, 'reversalReason': p.reversalReason},
          },
          fromJson: (j) {
            final supplier = suppliers.byId(j['supplierId']);
            if (supplier == null) return null;
            final items = <PurchaseItem>[];
            for (final i in (j['items'] as List? ?? const [])) {
              final product = products.byId(i['productId']);
              if (product == null) return null;
              items.add(PurchaseItem(product: product, qty: toDouble(i['qty']), unitCost: toDouble(i['unitCost']), unit: i['unit'], size: i['size'] == null ? 1 : toDouble(i['size'])));
            }
            return Purchase(
              id: j['id'],
              date: fromMillis(j['date']),
              supplier: supplier,
              items: items,
              paidAmount: toDouble(j['paidAmount']),
              account: j['account'] ?? 'cash',
              vatAmount: toDouble(j['vatAmount']),
              supplierBillNo: j['supplierBillNo'] ?? '',
              supplierBillDate: fromMillisOrNull(j['supplierBillDate']),
              corrects: j['corrects'],
              reversedAt: fromMillisOrNull(j['reversedAt']),
              reversedByName: j['reversedByName'] ?? '',
              reversalReason: j['reversalReason'] ?? '',
            );
          },
          merge: (p, j) => p
            ..paidAmount = toDouble(j['paidAmount'])
            ..reversedAt = fromMillisOrNull(j['reversedAt'])
            ..reversedByName = j['reversedByName'] ?? ''
            ..reversalReason = j['reversalReason'] ?? '',
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
            return PurchaseReturn(id: j['id'], date: fromMillis(j['date']), supplier: supplier, product: product, qty: toDouble(j['qty']), unitCost: toDouble(j['unitCost']), reason: j['reason'] ?? '');
          },
        );

  final SyncedCollection<Purchase> _purchases;
  final SyncedCollection<PurchaseReturn> _returns;

  List<SyncedCollection<Object?>> get collections => [_purchases, _returns];

  @override
  List<Purchase> get purchases => [
        for (final p in _purchases.items)
          if (!p.isReversed) p,
      ];

  @override
  List<Purchase> get allPurchases => _purchases.items;

  @override
  void markReversed(Purchase purchase, {required String byName, required String reason}) {
    purchase
      ..reversedAt = DateTime.now()
      ..reversedByName = byName
      ..reversalReason = reason;
    _purchases.save(purchase);
  }

  @override
  List<PurchaseReturn> get purchaseReturns => _returns.items;

  @override
  Purchase record(Supplier supplier, List<PurchaseItem> items, double paidAmount,
      {String account = 'cash', double vatAmount = 0, String supplierBillNo = '', DateTime? supplierBillDate, String? corrects}) {
    final purchase = Purchase(
      id: nextId('PU'),
      date: DateTime.now(),
      supplier: supplier,
      items: items,
      paidAmount: paidAmount,
      account: account,
      vatAmount: vatAmount,
      supplierBillNo: supplierBillNo,
      supplierBillDate: supplierBillDate,
      corrects: corrects,
    );
    _purchases.add(purchase);
    return purchase;
  }

  @override
  void recordReturn(PurchaseReturn purchaseReturn) => _returns.add(purchaseReturn);
}
