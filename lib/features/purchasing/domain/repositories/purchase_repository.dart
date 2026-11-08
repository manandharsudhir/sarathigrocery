import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_return.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';

abstract class PurchaseRepository {
  /// Purchases still standing (reversed ones left out).
  List<Purchase> get purchases;

  /// Every purchase, reversed ones included (for lists that show them).
  List<Purchase> get allPurchases;

  void markReversed(Purchase purchase, {required String byName, required String reason});

  List<PurchaseReturn> get purchaseReturns;

  Purchase record(Supplier supplier, List<PurchaseItem> items, double paidAmount,
      {String account, double vatAmount, String supplierBillNo, DateTime? supplierBillDate, String? corrects});

  void recordReturn(PurchaseReturn purchaseReturn);
}
