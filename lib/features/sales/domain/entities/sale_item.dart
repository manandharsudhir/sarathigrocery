import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';

/// [qty] of [unit] (one of [Product.sellUnits], [size] base units each) at
/// [unitPrice] per [unit].
class SaleItem {
  SaleItem({required this.product, required this.qty, required this.unitPrice, String? unit, this.size = 1, this.unitCost})
      : unit = unit ?? product.unitLabel;

  final Product product;
  double qty;
  double unitPrice;
  final String unit;
  final double size;

  /// Cost of one [unit] when sold, so later cost changes don't rewrite past
  /// profit. Null when the seller couldn't see costs (delivery staff
  /// invoicing an order): the current cost is used instead.
  double? unitCost;

  double get baseQty => qty * size;

  double get lineTotal => qty * unitPrice;

  double get cost => qty * (unitCost ?? product.purchasePrice * size);
}
