import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
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
    this.packs = const [],
    this.unit = ProductUnit.piece,
    this.customUnitLabel = '',
    this.description = '',
    this.isActive = true,
    this.reservedQty = 0,
    this.expiryDate,
    this.vatExempt = false,
    this.primaryUnit = '',
    this.saleUnit = '',
  });

  final String id;
  String name;
  String category;
  String sku;
  String brand;
  /// Minimum selling price of one base [unit].
  double unitPrice;

  /// Cost of one base [unit] (latest purchase). Staff-only.
  double purchasePrice;

  /// Bigger ways it is sold/bought (sack, box, ...), each in base units.
  List<ProductPack> packs;

  /// The smallest unit: stock and cost are counted in it behind the scenes.
  ProductUnit unit;

  /// The unit the owner thinks in (shown first, used for cost and low
  /// stock on the form, the default for purchases). '' = [unitLabel].
  String primaryUnit;

  /// The unit a sale starts in. '' = [unitLabel].
  String saleUnit;
  String customUnitLabel;
  String description;
  bool isActive;
  double stockQty;
  double reservedQty;
  double reorderLevel;
  DateTime? expiryDate;

  /// Sold without VAT (your accountant confirms which goods qualify).
  bool vatExempt;

  double get availableStock => stockQty - reservedQty;

  bool get isLowStock => stockQty <= reorderLevel;

  bool get isNearExpiry =>
      expiryDate != null &&
      expiryDate!.difference(DateTime.now()).inDays <= 30 &&
      expiryDate!.isAfter(DateTime.now());

  String get unitLabel => unit == ProductUnit.custom ? customUnitLabel : unit.name;

  /// Everything it can be sold in: the base unit first, then [packs].
  List<ProductPack> get sellUnits => [ProductPack(label: unitLabel, size: 1, price: unitPrice), ...packs];

  /// The sell unit called [label]; the base unit if there's none (renamed).
  ProductPack sellUnit(String label) => sellUnits.firstWhere((u) => u.label == label, orElse: () => sellUnits.first);

  /// The lowest price one [unit] may be sold for: its minimum selling price,
  /// or — until one is set — its cost. Null when it has neither yet (never
  /// purchased, no price): the product can't be sold.
  double? floorFor(String unit) {
    final u = sellUnit(unit);
    if (u.price > 0) return u.price;
    if (purchasePrice > 0) return purchasePrice * u.size;
    return null;
  }

  /// Whether [price] for one [unit] is under its floor ([floorFor]).
  bool isBelowMinimum(String unit, double price) => price < (floorFor(unit) ?? 0) - 0.005;

  /// No minimum price and no cost yet for [unit].
  bool isUnpriced(String unit) => floorFor(unit) == null;

  ProductPack get primary => sellUnit(primaryUnit);

  /// "8.5 sack (425 kg)": in the primary unit, with the base unit alongside;
  /// with the base as primary, "1,250 kg (25 sack)" (whole biggest packs).
  String describeQty(double baseQty) {
    final base = '${formatQty(baseQty)} $unitLabel';
    final p = primary;
    if (p.size != 1) return '${formatQty(baseQty / p.size)} ${p.label} ($base)';
    if (packs.isEmpty) return base;
    final biggest = packs.reduce((a, b) => a.size >= b.size ? a : b);
    return '$base (${formatQty((baseQty / biggest.size).floorToDouble())} ${biggest.label})';
  }

  /// Case-insensitive search on name, category and SKU.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q) || category.toLowerCase().contains(q) || sku.toLowerCase().contains(q);
  }
}
