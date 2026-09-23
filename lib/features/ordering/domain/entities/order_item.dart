import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';

class OrderItem {
  OrderItem({required this.product, required this.qty, required this.price});

  final Product product;
  int qty;
  double price;

  double get lineTotal => qty * price;
}
