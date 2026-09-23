import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_return.dart';
import 'package:sarathigrocery/features/purchasing/domain/repositories/purchase_repository.dart';
import 'package:sarathigrocery/features/purchasing/domain/usecases/create_purchase.dart';
import 'package:sarathigrocery/features/purchasing/domain/usecases/record_purchase_return.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';

class PurchasingController extends ChangeNotifier {
  PurchasingController(
    this._repository,
    ProductRepository products,
    SupplierRepository suppliers,
    CashRepository cash,
    AuditRepository audit,
    NotificationRepository notifications,
  )   : _createPurchase = CreatePurchase(_repository, products, suppliers, cash, audit, notifications),
        _recordReturn = RecordPurchaseReturn(_repository, products, suppliers, audit);

  final PurchaseRepository _repository;
  final CreatePurchase _createPurchase;
  final RecordPurchaseReturn _recordReturn;

  List<Purchase> get purchases => _repository.purchases;

  List<PurchaseReturn> get purchaseReturns => _repository.purchaseReturns;

  Purchase createPurchase({required Supplier supplier, required List<PurchaseItem> items, double paidAmount = 0, required String userName}) {
    final purchase = _createPurchase(supplier, items, paidAmount, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
    return purchase;
  }

  void recordPurchaseReturn(Supplier supplier, Product product, int qty, String reason, {required String userName}) {
    _recordReturn(supplier, product, qty, reason, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
