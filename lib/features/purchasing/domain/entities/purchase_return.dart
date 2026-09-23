import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';

class PurchaseReturn {
  PurchaseReturn({
    required this.id,
    required this.date,
    required this.supplier,
    required this.product,
    required this.qty,
    required this.unitCost,
    this.reason = '',
  });

  final String id;
  final DateTime date;
  final Supplier supplier;
  final Product product;
  final int qty;
  final double unitCost;
  final String reason;

  double get total => qty * unitCost;
}
