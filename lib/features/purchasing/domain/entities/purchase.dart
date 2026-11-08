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
    this.corrects,
    this.reversedAt,
    this.reversedByName = '',
    this.reversalReason = '',
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

  /// The purchase this one replaces (entered again after a mistake).
  final String? corrects;

  /// Set when this purchase was entered by mistake and taken back out.
  DateTime? reversedAt;
  String reversedByName;
  String reversalReason;
  bool get isReversed => reversedAt != null;

  double get goodsTotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);
  double get total => goodsTotal + vatAmount;
  double get remainingAmount => total - paidAmount;
}
