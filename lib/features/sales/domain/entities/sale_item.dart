import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';

class SaleItem {
  SaleItem({
    required this.product,
    required this.qty,
    required this.unitPrice,
  });

  final Product product;
  int qty;
  double unitPrice;

  double get lineTotal => qty * unitPrice;
}
