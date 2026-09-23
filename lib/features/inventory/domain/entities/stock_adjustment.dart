import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';

class StockAdjustment {
  StockAdjustment({
    required this.id,
    required this.date,
    required this.product,
    required this.type,
    required this.qty,
    this.note = '',
  });

  final String id;
  final DateTime date;
  final Product product;
  final AdjustmentType type;
  final int qty;
  final String note;
}
