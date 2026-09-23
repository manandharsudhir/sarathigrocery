import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';

/// Wraps [ProductRepository.updateProduct] to audit price changes —
/// "price changes should be audited" is a business rule, not a data concern.
class UpdateProduct {
  UpdateProduct(this._products, this._audit);

  final ProductRepository _products;
  final AuditRepository _audit;

  void call(
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
    if (unitPrice != null && unitPrice != product.unitPrice) {
      _audit.record(userName, 'Price changed', 'Product', entityId: product.id, oldValue: product.unitPrice.toStringAsFixed(0), newValue: unitPrice.toStringAsFixed(0));
    }
    _products.updateProduct(
      product,
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
  }
}
