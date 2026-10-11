import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';

/// [qty] of [unit] (one of [Product.sellUnits], [size] base units each) at
/// [price] per [unit], fixed when the order is placed.
class OrderItem {
  OrderItem({required this.product, required this.qty, required this.price, String? unit, this.size = 1}) : unit = unit ?? product.unitLabel;

  final Product product;
  double qty;
  double price;
  final String unit;
  final double size;

  double get baseQty => qty * size;

  double get lineTotal => qty * price;
}
