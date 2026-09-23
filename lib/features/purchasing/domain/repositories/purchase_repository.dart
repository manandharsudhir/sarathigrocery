import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_return.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';

abstract class PurchaseRepository {
  List<Purchase> get purchases;

  List<PurchaseReturn> get purchaseReturns;

  Purchase record(Supplier supplier, List<PurchaseItem> items, double paidAmount);

  void recordReturn(PurchaseReturn purchaseReturn);
}
