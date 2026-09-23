import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';

class Purchase {
  Purchase({
    required this.id,
    required this.date,
    required this.supplier,
    required this.items,
    this.paidAmount = 0,
  });

  final String id;
  final DateTime date;
  final Supplier supplier;
  final List<PurchaseItem> items;
  double paidAmount;

  double get total => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get remainingAmount => total - paidAmount;
}
