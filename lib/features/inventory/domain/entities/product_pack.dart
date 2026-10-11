import 'package:sarathigrocery/core/utils/formatters.dart';

/// One way a product is sold or bought: [size] base units (e.g. a 50 kg
/// sack of a product counted in kg), never sold below [price] (the minimum
/// selling price, set by whoever manages products; sellers may charge more).
class ProductPack {
  const ProductPack({required this.label, required this.size, required this.price});

  final String label;
  final double size;
  final double price;
}

/// A sale or order priced a line below its sell unit's minimum, by someone
/// without `Permission.sellBelowMinimum`. [lines] name them ("Sugar (sack)").
class BelowMinimumPriceException implements Exception {
  BelowMinimumPriceException(this.lines);

  final List<String> lines;

  String get message => 'Below the minimum selling price: ${lines.join(', ')}.';

  @override
  String toString() => message;
}

/// A sale/order line for a product with neither a minimum price nor a cost
/// yet (never purchased): it can't be sold until one exists.
class UnpricedProductException implements Exception {
  UnpricedProductException(this.products);

  final List<String> products;

  String get message => 'No price or cost yet for ${products.join(', ')}: set a minimum price or record a purchase first.';

  @override
  String toString() => message;
}

/// The minimum price a purchase suggests: [cost] plus [marginPercent],
/// rounded up to a whole rupee.
double suggestedPrice(double cost, double marginPercent) => (cost * (1 + marginPercent / 100)).ceilToDouble();

/// Unit names offered on the product form ("Other…" allows any).
const kUnitNames = ['kg', 'g', 'litre', 'ml', 'piece', 'packet', 'box', 'carton', 'sack', 'bottle', 'dozen', 'crate', 'bundle', 'tin'];

/// Packs are found by label, so a label used twice ("sack" for 25 and 50 kg)
/// gets its size added: "sack 25kg", "sack 50kg". Throws [ArgumentError]
/// for a real duplicate (same label and size).
List<ProductPack> withUniqueLabels(List<ProductPack> packs, String unitLabel) {
  final counts = <String, int>{};
  for (final p in packs) {
    counts[p.label] = (counts[p.label] ?? 0) + 1;
  }
  final named = [
    for (final p in packs)
      counts[p.label]! > 1 ? ProductPack(label: '${p.label} ${formatQty(p.size)}$unitLabel', size: p.size, price: p.price) : p,
  ];
  final seen = <String>{};
  for (final p in named) {
    if (!seen.add(p.label)) throw ArgumentError('Duplicate pack: ${p.label}');
  }
  return named;
}

/// The list name a stored [label] was picked as (undoing [withUniqueLabels]),
/// or null if it was typed under "Other…".
String? packNameOf(String label, double size, String unitLabel) {
  for (final name in kUnitNames) {
    if (label == name || label == '$name ${formatQty(size)}$unitLabel') return name;
  }
  return null;
}
