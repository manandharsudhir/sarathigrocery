import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
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
import 'package:sarathigrocery/features/purchasing/domain/usecases/reverse_purchase.dart';
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
    Books books, {
    List<String> Function()? moneyAccounts,
    bool Function()? vatShop,
    double Function()? margin,
  })  : _margin = margin ?? (() => 0),
        _notifications = notifications,
        _audit = audit,
        _vatShop = vatShop ?? (() => false),
        _moneyAccounts = moneyAccounts ?? (() => const ['cash', 'bank', 'wallet']), _createPurchase = CreatePurchase(_repository, products, suppliers, cash, audit, notifications, books),
        _recordReturn = RecordPurchaseReturn(_repository, products, suppliers, audit, books),
        _reverse = ReversePurchase(_repository, products, suppliers, cash, audit, notifications, books);

  final ReversePurchase _reverse;

  final PurchaseRepository _repository;
  final CreatePurchase _createPurchase;
  final List<String> Function() _moneyAccounts;
  final bool Function() _vatShop;
  final double Function() _margin;
  final NotificationRepository _notifications;
  final AuditRepository _audit;

  /// Default margin % for suggested minimum prices (Settings).
  double get marginPercent => _margin();

  /// After a purchase: tells the owner which of [products] still sell with
  /// no minimum price, or with one now below cost.
  void notifyPricesNeeded(Iterable<Product> products, {required String userName}) {
    final names = {
      for (final p in products)
        if (p.sellUnits.any((u) => u.price <= 0 || u.price < p.purchasePrice * u.size - 0.005)) p.name,
    };
    if (names.isEmpty) return;
    _notifications.notify('Set selling prices', 'After $userName\'s purchase: ${names.join(', ')} ${names.length == 1 ? 'has' : 'have'} no minimum price, or one below cost.', role: UserRole.owner);
  }

  /// VAT shops record the supplier's bill number and VAT (Purchase Book).
  bool get recordsVat => _vatShop();

  /// Accounts a purchase can be paid from.
  List<String> get moneyAccounts => _moneyAccounts();
  final RecordPurchaseReturn _recordReturn;

  /// Purchases still standing (reversed ones left out of every total).
  List<Purchase> get purchases => _repository.purchases;

  /// Every purchase, reversed ones included (for lists).
  List<Purchase> get allPurchases => _repository.allPurchases;

  /// The standing purchase that already carries supplier bill [billNo] from
  /// [supplier] ([except]: the one being corrected). A supplier never
  /// issues the same number twice, so this is a double entry.
  Purchase? duplicateBill(Supplier supplier, String billNo, {Purchase? except}) {
    final no = billNo.trim().toLowerCase();
    if (no.isEmpty) return null;
    return purchases.where((p) => p != except && p.supplier.id == supplier.id && p.supplierBillNo.trim().toLowerCase() == no).firstOrNull;
  }

  /// A purchase from [supplier] for the same [total] already today, or null.
  Purchase? similarToday(Supplier supplier, double total, {Purchase? except}) {
    final now = DateTime.now();
    return purchases
        .where((p) => p != except && p.supplier.id == supplier.id && (p.total - total).abs() < 0.005 && p.date.year == now.year && p.date.month == now.month && p.date.day == now.day)
        .firstOrNull;
  }

  /// The purchase that replaced [purchase], if it was corrected.
  Purchase? correctionOf(Purchase purchase) => allPurchases.where((p) => p.corrects == purchase.id).firstOrNull;

  /// Takes [purchase] (entered by mistake) back out, whole.
  void reversePurchase(Purchase purchase, String reason, {required String userName, required bool owner}) {
    _reverse(purchase, reason, userName: userName, owner: owner);
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// Replaces [old] with the purchase as it should have been, in one save:
  /// [old] reversed, the new one recorded and linked to it.
  Purchase correctPurchase(
    Purchase old,
    String reason, {
    required Supplier supplier,
    required List<PurchaseItem> items,
    double paidAmount = 0,
    required String userName,
    required bool owner,
    String account = 'cash',
    double vatAmount = 0,
    String supplierBillNo = '',
    DateTime? supplierBillDate,
  }) {
    _reverse(old, 'Corrected: ${reason.trim()}', userName: userName, owner: owner, replacement: items);
    final purchase = _createPurchase(supplier, items, paidAmount,
        userName: userName, account: account, vatAmount: vatAmount, supplierBillNo: supplierBillNo, supplierBillDate: supplierBillDate, corrects: old.id);
    _audit.record(userName, 'Purchase corrected', 'Purchase', entityId: purchase.id, oldValue: old.id, newValue: reason.trim());
    notifyListeners();
    AppSignal.instance.ping();
    return purchase;
  }

  List<PurchaseReturn> get purchaseReturns => _repository.purchaseReturns;

  Purchase createPurchase({
    required Supplier supplier,
    required List<PurchaseItem> items,
    double paidAmount = 0,
    required String userName,
    String account = 'cash',
    double vatAmount = 0,
    String supplierBillNo = '',
    DateTime? supplierBillDate,
  }) {
    final purchase = _createPurchase(supplier, items, paidAmount,
        userName: userName, account: account, vatAmount: vatAmount, supplierBillNo: supplierBillNo, supplierBillDate: supplierBillDate);
    notifyListeners();
    AppSignal.instance.ping();
    return purchase;
  }

  void recordPurchaseReturn(Supplier supplier, Product product, double qty, String reason, {required String userName, double? unitCost}) {
    _recordReturn(supplier, product, qty, reason, userName: userName, unitCost: unitCost);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
