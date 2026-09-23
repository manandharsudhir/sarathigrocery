import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';

class Sale {
  Sale({
    required this.id,
    required this.date,
    required this.items,
    required this.discountPercent,
    required this.isCredit,
    this.customer,
    this.flaggedForApproval = false,
    this.status = SaleStatus.completed,
    this.createdByUserId,
    this.createdByName = '',
  });

  final String id;
  final DateTime date;
  final List<SaleItem> items;
  final double discountPercent;
  final bool isCredit;
  final Customer? customer;
  bool flaggedForApproval;
  SaleStatus status;
  final String? createdByUserId;
  final String createdByName;

  double get subtotal => items.fold(0, (sum, i) => sum + i.lineTotal);
  double get discountAmount => subtotal * discountPercent / 100;
  double get total => subtotal - discountAmount;
  double get costOfGoods => items.fold(0.0, (sum, i) => sum + i.qty * i.product.purchasePrice);
}
