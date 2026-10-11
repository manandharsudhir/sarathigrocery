import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';

/// One line being entered: [qty] of [unit] (a [Product.sellUnits] entry)
/// at [price] per unit. Shared by sales, orders and purchases.
class CartLine {
  CartLine(this.product, this.unit, double price)
      : qty = TextEditingController(text: '1'),
        price = TextEditingController(text: _money(price));

  final Product product;
  ProductPack unit;
  final TextEditingController qty;
  final TextEditingController price;

  /// Purchases only: the new minimum selling price for [unit] (blank = keep).
  final sellPrice = TextEditingController();

  /// The owner typed [sellPrice] themselves (stop suggesting).
  bool sellPriceTyped = false;

  double get qtyValue => double.tryParse(qty.text) ?? 0;
  double get priceValue => double.tryParse(price.text) ?? 0;
  double get baseQty => qtyValue * unit.size;
  double get total => qtyValue * priceValue;
  bool get belowMinimum => product.isBelowMinimum(unit.label, priceValue);
}

String _money(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// What stops [lines] from being saved, or null. Sales/orders pass
/// [checkMinimum] (prices) and [checkStock] (available stock).
String? cartProblem(List<CartLine> lines, {bool checkMinimum = false, bool allowBelowMinimum = false, bool checkStock = false}) {
  if (lines.isEmpty) return 'Add at least one item.';
  if (lines.any((l) => l.qtyValue <= 0)) return 'Every quantity must be more than 0.';
  if (lines.any((l) => l.priceValue < 0)) return 'Prices can\'t be negative.';
  if (checkMinimum) {
    final unpriced = {for (final l in lines) if (l.product.isUnpriced(l.unit.label)) l.product.name};
    if (unpriced.isNotEmpty) return UnpricedProductException(unpriced.toList()).message;
  }
  if (checkMinimum && !allowBelowMinimum) {
    final below = [for (final l in lines) if (l.belowMinimum) '${l.product.name} (${l.unit.label})'];
    if (below.isNotEmpty) return 'Below the minimum price: ${below.join(', ')}.';
  }
  if (checkStock) {
    final wanted = <Product, double>{};
    for (final l in lines) {
      wanted[l.product] = (wanted[l.product] ?? 0) + l.baseQty;
    }
    for (final e in wanted.entries) {
      if (e.value > e.key.availableStock + 1e-9) return 'Only ${e.key.describeQty(e.key.availableStock)} of ${e.key.name} available.';
    }
  }
  return null;
}

/// Product search + "add" list, then the editable [lines]. [priceFor]
/// fills a new line's price for a unit (minimum selling price, or cost for
/// purchases); [priceLabel] names it.
class CartEditor extends StatefulWidget {
  const CartEditor({
    super.key,
    required this.products,
    required this.lines,
    required this.onChanged,
    required this.priceFor,
    this.priceLabel = 'Price',
    this.showMinimum = true,
    this.allowBelowMinimum = false,
    this.editSellPrice = false,
    this.startUnit,
    this.marginPercent = 0,
  });

  final List<Product> products;
  final List<CartLine> lines;
  final VoidCallback onChanged;
  final double Function(Product product, ProductPack unit) priceFor;
  final String priceLabel;

  /// Sales/orders: show each unit's minimum and flag lines under it.
  final bool showMinimum;
  final bool allowBelowMinimum;

  /// Purchases, for whoever manages products: set new selling prices.
  final bool editSellPrice;

  /// The unit a new line starts in (default: the product's selling unit).
  final ProductPack Function(Product product)? startUnit;

  /// Purchases: suggests a new minimum price at cost + this % when the unit
  /// has none or it would be below the new cost.
  final double marginPercent;

  @override
  State<CartEditor> createState() => _CartEditorState();
}

class _CartEditorState extends State<CartEditor> {
  String _query = '';

  void _changed() {
    if (widget.editSellPrice && widget.marginPercent > 0) {
      for (final l in widget.lines) {
        if (l.sellPriceTyped || l.priceValue <= 0) continue;
        final current = l.product.sellUnit(l.unit.label).price;
        l.sellPrice.text = current <= 0 || l.priceValue > current ? formatQty(suggestedPrice(l.priceValue, widget.marginPercent)) : '';
      }
    }
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _query.isEmpty ? const <Product>[] : widget.products.where((p) => p.matches(_query)).take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, line) in widget.lines.indexed) _lineCard(i, line),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search products to add', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        for (final p in matches)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p.name),
            subtitle: Text('${p.describeQty(p.availableStock)} available'
                '${widget.showMinimum ? ' · ${[for (final u in p.sellUnits) '${u.label} ${u.price > 0 ? formatNpr(u.price) : (p.floorFor(u.label) == null ? 'no price yet' : 'at cost')}'].join(', ')}' : ''}'),
            trailing: const Icon(Icons.add_circle_outline),
            onTap: () {
              final unit = widget.startUnit?.call(p) ?? p.sellUnit(p.saleUnit);
              widget.lines.add(CartLine(p, unit, widget.priceFor(p, unit)));
              _changed();
            },
          ),
      ],
    );
  }

  Widget _lineCard(int index, CartLine line) {
    final minimum = widget.showMinimum ? (line.product.floorFor(line.unit.label) ?? 0) : line.product.sellUnit(line.unit.label).price;
    final below = widget.showMinimum && line.belowMinimum;
    // Purchases: the new cost is above what this unit may be sold for.
    final costAbove = !widget.showMinimum && line.priceValue > minimum && (double.tryParse(line.sellPrice.text) ?? 0) < line.priceValue;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(line.product.name, style: Theme.of(context).textTheme.titleSmall)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  widget.lines.removeAt(index);
                  _changed();
                },
              ),
            ]),
            Row(children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: line.unit.label,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Unit', isDense: true),
                  items: [
                    for (final u in line.product.sellUnits)
                      DropdownMenuItem(value: u.label, child: Text(u.size == 1 ? u.label : '${u.label} (${formatQty(u.size)} ${line.product.unitLabel})')),
                  ],
                  onChanged: (label) {
                    if (label == null) return;
                    line.unit = line.product.sellUnit(label);
                    line.price.text = _money(widget.priceFor(line.product, line.unit));
                    line.sellPrice.clear();
                    _changed();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: line.qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                  onChanged: (_) => _changed(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: line.price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: '${widget.priceLabel} / ${line.unit.label}', isDense: true),
                  onChanged: (_) => _changed(),
                ),
              ),
              const SizedBox(width: 8),
            ]),
            if (widget.editSellPrice)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextField(
                  controller: line.sellPrice,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => line.sellPriceTyped = true,
                  decoration: InputDecoration(
                    labelText: 'New min. selling price / ${line.unit.label}',
                    hintText: 'now ${formatNpr(minimum)}',
                    isDense: true,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [
                  formatNpr(line.total),
                  if (below) 'below minimum ${formatNpr(minimum)}${widget.allowBelowMinimum ? ' (allowed, recorded)' : ''}',
                  if (costAbove) 'costs more than its minimum selling price ${formatNpr(minimum)}${widget.editSellPrice ? ': set a new one above' : ''}',
                ].join(' · '),
                style: TextStyle(color: below ? (widget.allowBelowMinimum ? Colors.orange : Theme.of(context).colorScheme.error) : (costAbove ? Colors.orange : null)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
