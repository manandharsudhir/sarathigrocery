import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';

/// [qty] of [unit] (e.g. sacks, [size] base units each) bought at
/// [unitCost] per [unit].
class PurchaseItem {
  PurchaseItem({required this.product, required this.qty, required this.unitCost, String? unit, this.size = 1}) : unit = unit ?? product.unitLabel;

  final Product product;
  double qty;
  double unitCost;
  final String unit;
  final double size;

  double get baseQty => qty * size;

  double get lineTotal => qty * unitCost;
}
