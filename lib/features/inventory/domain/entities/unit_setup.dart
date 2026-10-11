import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';

/// One extra unit as the owner enters it, related to the primary unit:
/// `1 primary = perPrimary name` when smaller, `1 name = perPrimary primary`
/// when [bigger]. [price] is its minimum selling price.
typedef UnitEntry = ({String name, double perPrimary, bool bigger, double price});

/// How a product's units are stored: stock counts in the smallest unit
/// ([base]); every other unit is a [ProductPack] of that many base units;
/// [primarySize] is the primary unit's size in base units.
typedef UnitPlan = ({String base, double basePrice, List<ProductPack> packs, double primarySize, String primary});

/// Turns the owner's "1 sack = 50 kg" entries into a [UnitPlan]. The same
/// name twice (sacks of 25 and 50 kg) is told apart by size ("sack 25kg").
/// Throws [ArgumentError] for a missing name, a conversion ≤ 0, a unit
/// named like the primary, or a true duplicate.
UnitPlan planUnits(String primary, double primaryPrice, List<UnitEntry> others) {
  primary = primary.trim();
  final all = [
    (name: primary, inPrimary: 1.0, price: primaryPrice),
    for (final u in others) (name: u.name.trim(), inPrimary: u.bigger ? u.perPrimary : 1 / u.perPrimary, price: u.price),
  ];
  if (all.any((u) => u.name.isEmpty)) throw ArgumentError('Give every unit a name.');
  if (others.any((u) => u.perPrimary <= 0)) throw ArgumentError('Every conversion must be more than 0.');
  if (others.any((u) => u.name.trim() == primary)) throw ArgumentError('$primary is already the main unit.');

  var baseAt = 0;
  for (var i = 1; i < all.length; i++) {
    if (all[i].inPrimary < all[baseAt].inPrimary) baseAt = i;
  }
  final unit = all[baseAt].inPrimary;
  double size(int i) => _clean(all[i].inPrimary / unit);
  final packs = withUniqueLabels([
    for (var i = 0; i < all.length; i++)
      if (i != baseAt) ProductPack(label: all[i].name, size: size(i), price: all[i].price),
  ], all[baseAt].name);
  return (base: all[baseAt].name, basePrice: all[baseAt].price, packs: packs, primarySize: size(0), primary: primary);
}

/// Removes float noise (1/0.02 = 49.99999…) from a conversion.
double _clean(double v) => (v * 1e6).roundToDouble() / 1e6;

/// The stored base unit for a unit name.
({ProductUnit unit, String custom}) baseUnitFor(String name) {
  for (final u in ProductUnit.values) {
    if (u != ProductUnit.custom && u.name == name) return (unit: u, custom: '');
  }
  return (unit: ProductUnit.custom, custom: name);
}
