import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';

class Product {
  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.unitPrice,
    required this.stockQty,
    required this.reorderLevel,
    this.sku = '',
    this.brand = '',
    this.purchasePrice = 0,
    this.retailPrice,
    this.unit = ProductUnit.piece,
    this.customUnitLabel = '',
    this.description = '',
    this.isActive = true,
    this.reservedQty = 0,
    this.expiryDate,
  });

  final String id;
  String name;
  String category;
  String sku;
  String brand;
  double unitPrice;
  double purchasePrice;
  double? retailPrice;
  ProductUnit unit;
  String customUnitLabel;
  String description;
  bool isActive;
  int stockQty;
  int reservedQty;
  int reorderLevel;
  DateTime? expiryDate;

  int get availableStock => stockQty - reservedQty;

  bool get isLowStock => stockQty <= reorderLevel;

  bool get isNearExpiry =>
      expiryDate != null &&
      expiryDate!.difference(DateTime.now()).inDays <= 30 &&
      expiryDate!.isAfter(DateTime.now());

  String get unitLabel => unit == ProductUnit.custom ? customUnitLabel : unit.name;
}
