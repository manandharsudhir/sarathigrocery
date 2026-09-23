import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/stock_adjustment.dart';

abstract class ProductRepository {
  List<Product> get products;

  List<String> get categories;

  List<StockAdjustment> get adjustments;

  int get lowStockCount;

  int get nearExpiryCount;

  void addCategory(String name);

  /// Returns false (without deleting) if a product still uses this category.
  bool deleteCategory(String name);

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
  });

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
  });

  /// Raw stock mutation with no audit/notification side effects — used by
  /// other features (sales, purchasing, ordering) that record their own
  /// audit trail for the containing operation.
  void increaseStock(Product product, int qty);

  void decreaseStock(Product product, int qty);

  /// Reserves stock for a placed-but-not-yet-delivered order (does not
  /// touch [Product.stockQty]).
  void reserveStock(Product product, int qty);

  /// Releases a reservation (order cancelled) without touching stock.
  void releaseReservation(Product product, int qty);

  void recordAdjustment(Product product, AdjustmentType type, int qty, String note);
}
