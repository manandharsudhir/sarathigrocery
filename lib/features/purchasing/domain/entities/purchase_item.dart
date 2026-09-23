import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';

class PurchaseItem {
  PurchaseItem({required this.product, required this.qty, required this.unitCost});

  final Product product;
  int qty;
  double unitCost;

  double get lineTotal => qty * unitCost;
}
