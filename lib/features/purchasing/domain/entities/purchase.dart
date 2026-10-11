import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';

class Purchase {
  Purchase({
    required this.id,
    required this.date,
    required this.supplier,
    required this.items,
    this.paidAmount = 0,
    this.account = 'cash',
    this.vatAmount = 0,
    this.supplierBillNo = '',
    this.supplierBillDate,
  });

  final String id;
  final DateTime date;
  final Supplier supplier;
  final List<PurchaseItem> items;
  double paidAmount;

  /// Money account [paidAmount] came out of.
  final String account;

  /// VAT on the supplier's bill (claimable against VAT collected).
  final double vatAmount;
  final String supplierBillNo;
  final DateTime? supplierBillDate;

  double get goodsTotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get total => goodsTotal + vatAmount;
  double get remainingAmount => total - paidAmount;
}
