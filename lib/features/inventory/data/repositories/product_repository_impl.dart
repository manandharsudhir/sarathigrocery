import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/stock_adjustment.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';

Json _productToJson(Product p) => {
      'name': p.name,
      'category': p.category,
      'sku': p.sku,
      'brand': p.brand,
      'unitPrice': p.unitPrice,
      'purchasePrice': p.purchasePrice,
      'retailPrice': p.retailPrice,
      'unit': p.unit.name,
      'customUnitLabel': p.customUnitLabel,
      'description': p.description,
      'isActive': p.isActive,
      'stockQty': p.stockQty,
      'reservedQty': p.reservedQty,
      'reorderLevel': p.reorderLevel,
      'expiryDate': p.expiryDate == null ? null : toMillis(p.expiryDate!),
    };

Product _productFromJson(Json j) {
  final p = Product(id: j['id'], name: '', category: '', unitPrice: 0, stockQty: 0, reorderLevel: 0);
  _mergeProduct(p, j);
  return p;
}

void _mergeProduct(Product p, Json j) {
  p
    ..name = j['name'] ?? ''
    ..category = j['category'] ?? ''
    ..sku = j['sku'] ?? ''
    ..brand = j['brand'] ?? ''
    ..unitPrice = toDouble(j['unitPrice'])
    ..purchasePrice = toDouble(j['purchasePrice'])
    ..retailPrice = (j['retailPrice'] as num?)?.toDouble()
    ..unit = ProductUnit.values.byName(j['unit'] ?? ProductUnit.piece.name)
    ..customUnitLabel = j['customUnitLabel'] ?? ''
    ..description = j['description'] ?? ''
    ..isActive = j['isActive'] ?? true
    ..stockQty = toInt(j['stockQty'])
    ..reservedQty = toInt(j['reservedQty'])
    ..reorderLevel = toInt(j['reorderLevel'])
    ..expiryDate = fromMillisOrNull(j['expiryDate']);
}

class ProductRepositoryImpl implements ProductRepository {
  final _products = SyncedCollection<Product>(
    'products',
    idOf: (p) => p.id,
    toJson: _productToJson,
    fromJson: _productFromJson,
    merge: _mergeProduct,
    counters: {'stockQty', 'reservedQty'},
  );

  final _categories = SyncedCollection<String>(
    'categories',
    idOf: (name) => name,
    toJson: (name) => {'name': name},
    fromJson: (j) => j['id'] as String,
  );

  late final _adjustments = SyncedCollection<StockAdjustment>(
    'stockAdjustments',
    idOf: (a) => a.id,
    toJson: (a) => {'date': toMillis(a.date), 'productId': a.product.id, 'type': a.type.name, 'qty': a.qty, 'note': a.note},
    fromJson: (j) {
      final product = _products.byId(j['productId']);
      if (product == null) return null;
      return StockAdjustment(id: j['id'], date: fromMillis(j['date']), product: product, type: AdjustmentType.values.byName(j['type']), qty: toInt(j['qty']), note: j['note'] ?? '');
    },
  );

  /// [products] first: the other collections resolve references into it.
  List<SyncedCollection<Object?>> get collections => [_products, _categories, _adjustments];

  @override
  List<Product> get products => _products.items;

  @override
  List<String> get categories => _categories.items;

  @override
  List<StockAdjustment> get adjustments => _adjustments.items;

  Product? byId(String? id) => _products.byId(id);

  @override
  int get lowStockCount => products.where((p) => p.isLowStock).length;

  @override
  int get nearExpiryCount => products.where((p) => p.isNearExpiry).length;

  @override
  void addCategory(String name) {
    if (name.trim().isEmpty || categories.contains(name)) return;
    _categories.add(name);
  }

  @override
  bool deleteCategory(String name) {
    if (products.any((p) => p.category == name)) return false;
    _categories.remove(name);
    return true;
  }

  @override
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
    final product = Product(
      id: nextId('P'),
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
    _products.add(product);
    return product;
  }

  @override
  void updateProduct(
    Product product, {
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
    if (unitPrice != null) product.unitPrice = unitPrice;
    if (name != null) product.name = name;
    if (category != null) product.category = category;
    if (purchasePrice != null) product.purchasePrice = purchasePrice;
    if (retailPrice != null) product.retailPrice = retailPrice;
    if (reorderLevel != null) product.reorderLevel = reorderLevel;
    if (sku != null) product.sku = sku;
    if (brand != null) product.brand = brand;
    if (unit != null) product.unit = unit;
    if (customUnitLabel != null) product.customUnitLabel = customUnitLabel;
    if (description != null) product.description = description;
    if (isActive != null) product.isActive = isActive;
    if (expiryDate != null) product.expiryDate = expiryDate;
    _products.save(product);
  }

  void _changeStock(Product product, {int stock = 0, int reserved = 0}) {
    product
      ..stockQty += stock
      ..reservedQty += reserved;
    _products.increment(product, {if (stock != 0) 'stockQty': stock, if (reserved != 0) 'reservedQty': reserved});
  }

  @override
  void increaseStock(Product product, int qty) => _changeStock(product, stock: qty);

  @override
  void decreaseStock(Product product, int qty) => _changeStock(product, stock: -qty);

  @override
  void reserveStock(Product product, int qty) => _changeStock(product, reserved: qty);

  @override
  void releaseReservation(Product product, int qty) => _changeStock(product, reserved: -qty);

  @override
  void recordAdjustment(Product product, AdjustmentType type, int qty, String note) {
    _changeStock(product, stock: -qty);
    _adjustments.add(StockAdjustment(id: nextId('A'), date: DateTime.now(), product: product, type: type, qty: qty, note: note));
  }
}
