import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
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
    List<ProductPack> packs = const [],
    required double stockQty,
    required double reorderLevel,
    String sku = '',
    String brand = '',
    ProductUnit unit = ProductUnit.piece,
    String customUnitLabel = '',
    String description = '',
    DateTime? expiryDate,
    bool vatExempt,
    String primaryUnit,
    String saleUnit,
  });

  void updateProduct(
    Product product, {
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
  });

  /// Raw stock mutation with no audit/notification side effects — used by
  /// other features (sales, purchasing, ordering) that record their own
  /// audit trail for the containing operation.
  void increaseStock(Product product, double qty);

  void decreaseStock(Product product, double qty);

  /// Reserves stock for a placed-but-not-yet-delivered order (does not
  /// touch [Product.stockQty]).
  void reserveStock(Product product, double qty);

  /// Releases a reservation (order cancelled) without touching stock.
  void releaseReservation(Product product, double qty);

  void recordAdjustment(Product product, AdjustmentType type, double qty, String note);
}
