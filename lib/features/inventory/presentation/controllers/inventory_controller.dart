import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/stock_adjustment.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/usecases/adjust_stock.dart';
import 'package:sarathigrocery/features/inventory/domain/usecases/update_product.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

class InventoryController extends ChangeNotifier {
  InventoryController(this._products, AuditRepository audit, NotificationRepository notifications)
      : _adjustStock = AdjustStock(_products, audit, notifications),
        _updateProductUseCase = UpdateProduct(_products, audit);

  final ProductRepository _products;
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
    double? retailPrice,
    required int stockQty,
    required int reorderLevel,
    String sku = '',
    String brand = '',
    ProductUnit unit = ProductUnit.piece,
    String customUnitLabel = '',
    String description = '',
    DateTime? expiryDate,
  }) {
    final product = _products.createProduct(
      name: name,
      category: category,
      unitPrice: unitPrice,
      purchasePrice: purchasePrice,
      retailPrice: retailPrice,
      stockQty: stockQty,
      reorderLevel: reorderLevel,
      sku: sku,
      brand: brand,
      unit: unit,
      customUnitLabel: customUnitLabel,
      description: description,
      expiryDate: expiryDate,
    );
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
    double? retailPrice,
    int? reorderLevel,
    String? sku,
    String? brand,
    ProductUnit? unit,
    String? customUnitLabel,
    String? description,
    bool? isActive,
    DateTime? expiryDate,
  }) {
    _updateProductUseCase(
      product,
      userName: userName,
      name: name,
      category: category,
      unitPrice: unitPrice,
      purchasePrice: purchasePrice,
      retailPrice: retailPrice,
      reorderLevel: reorderLevel,
      sku: sku,
      brand: brand,
      unit: unit,
      customUnitLabel: customUnitLabel,
      description: description,
      isActive: isActive,
      expiryDate: expiryDate,
    );
    notifyListeners();
    AppSignal.instance.ping();
  }

  void adjustStock(Product product, AdjustmentType type, int qty, String note, {required String userName}) {
    _adjustStock(product, type, qty, note, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
