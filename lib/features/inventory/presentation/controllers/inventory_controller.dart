import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/stock_adjustment.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/usecases/adjust_stock.dart';
import 'package:sarathigrocery/features/inventory/domain/usecases/update_product.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

class InventoryController extends ChangeNotifier {
  InventoryController(this._products, AuditRepository audit, NotificationRepository notifications, this._books)
      : _adjustStock = AdjustStock(_products, audit, notifications, _books),
        _updateProductUseCase = UpdateProduct(_products, audit, _books);

  final ProductRepository _products;
  final Books _books;
  final AdjustStock _adjustStock;
  final UpdateProduct _updateProductUseCase;

  List<Product> get products => _products.products;

  List<String> get categories => _products.categories;

  List<StockAdjustment> get adjustments => _products.adjustments;

  int get lowStockCount => _products.lowStockCount;

  int get nearExpiryCount => _products.nearExpiryCount;

  void addCategory(String name) {
    _products.addCategory(name);
    notifyListeners();
    AppSignal.instance.ping();
  }

  bool deleteCategory(String name) {
    final removed = _products.deleteCategory(name);
    if (removed) {
      notifyListeners();
      AppSignal.instance.ping();
    }
    return removed;
  }

  Product createProduct({
    required String name,
    required String category,
    required double unitPrice,
    double purchasePrice = 0,
    List<ProductPack> packs = const [],
    required double stockQty,
    required double reorderLevel,
    String sku = '',
    String brand = '',
    ProductUnit unit = ProductUnit.piece,
    String customUnitLabel = '',
    String description = '',
    DateTime? expiryDate,
    bool vatExempt = false,
    String primaryUnit = '',
    String saleUnit = '',
  }) {
    final product = _products.createProduct(
      name: name,
      category: category,
      unitPrice: unitPrice,
      purchasePrice: purchasePrice,
      packs: packs,
      stockQty: stockQty,
      reorderLevel: reorderLevel,
      sku: sku,
      brand: brand,
      unit: unit,
      customUnitLabel: customUnitLabel,
      description: description,
      expiryDate: expiryDate,
      vatExempt: vatExempt,
      primaryUnit: primaryUnit,
      saleUnit: saleUnit,
    );
    // Goods already on hand when added are part of opening capital.
    if (stockQty > 0) _books.openingStock(product);
    notifyListeners();
    AppSignal.instance.ping();
    return product;
  }

  void updateProduct(
    Product product, {
    required String userName,
    String? name,
    String? category,
    double? unitPrice,
    double? purchasePrice,
    List<ProductPack>? packs,
    double? reorderLevel,
    String? sku,
    String? brand,
    ProductUnit? unit,
    String? customUnitLabel,
    String? description,
    bool? isActive,
    DateTime? expiryDate,
    bool? vatExempt,
    String? primaryUnit,
    String? saleUnit,
  }) {
    _updateProductUseCase(
      product,
      userName: userName,
      name: name,
      category: category,
      unitPrice: unitPrice,
      purchasePrice: purchasePrice,
      packs: packs,
      reorderLevel: reorderLevel,
      sku: sku,
      brand: brand,
      unit: unit,
      customUnitLabel: customUnitLabel,
      description: description,
      isActive: isActive,
      expiryDate: expiryDate,
      vatExempt: vatExempt,
      primaryUnit: primaryUnit,
      saleUnit: saleUnit,
    );
    notifyListeners();
    AppSignal.instance.ping();
  }

  void adjustStock(Product product, AdjustmentType type, double qty, String note, {required String userName}) {
    _adjustStock(product, type, qty, note, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
