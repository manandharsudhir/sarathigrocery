import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';

/// Wraps [ProductRepository.updateProduct] to audit price changes —
/// "price changes should be audited" is a business rule, not a data concern.
class UpdateProduct {
  UpdateProduct(this._products, this._audit, this._books);

  final ProductRepository _products;
  final AuditRepository _audit;
  final Books _books;

  void call(
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
    if (unitPrice != null && unitPrice != product.unitPrice) {
      _audit.record(userName, 'Price changed', 'Product', entityId: product.id, oldValue: product.unitPrice.toStringAsFixed(0), newValue: unitPrice.toStringAsFixed(0));
    }
    if (packs != null && _describe(packs) != _describe(product.packs)) {
      _audit.record(userName, 'Pack prices changed', 'Product', entityId: product.id, oldValue: _describe(product.packs), newValue: _describe(packs));
    }
    if (purchasePrice != null && (purchasePrice - product.purchasePrice).abs() >= 0.005) {
      _books.stockRevalued(product, product.purchasePrice, purchasePrice, by: userName);
    }
    _products.updateProduct(
      product,
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
  }

  static String _describe(List<ProductPack> packs) => [for (final p in packs) '${p.label} ${p.size}: ${p.price.toStringAsFixed(0)}'].join(', ');
}
