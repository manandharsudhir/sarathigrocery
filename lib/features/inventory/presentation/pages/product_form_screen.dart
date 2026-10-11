import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/unit_setup.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/presentation/controllers/settings_controller.dart';

const _defaultCategory = 'General';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.controller, required this.auth, required this.settings, this.product});

  final InventoryController controller;
  final AuthController auth;
  final SettingsController settings;

  /// Null when creating a new product.
  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final _brand = TextEditingController(text: widget.product?.brand ?? '');
  late final _description = TextEditingController(text: widget.product?.description ?? '');

  late final _hasCategories = widget.settings.has(Feature.categories);

  /// With Categories off, new products go in [_defaultCategory].
  late String _category = widget.product?.category ??
      (!_hasCategories ? _defaultCategory : (widget.controller.categories.isEmpty ? '' : widget.controller.categories.first));
  late bool _isActive = widget.product?.isActive ?? true;
  late bool _vatExempt = widget.product?.vatExempt ?? false;

  bool get _isEditing => widget.product != null;

  // ---- Units, entered against the main unit ("1 sack = 50 kg").

  late final _UnitName _primary;
  late final _primaryPrice = TextEditingController();
  late final _cost = TextEditingController();
  late final _stockQty = TextEditingController(text: '0');
  late final _reorderLevel = TextEditingController(text: '5');
  final List<_UnitRow> _units = [];
  String _saleUnit = '';
  String? _unitError;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p == null) {
      _primary = _UnitName('kg');
      return;
    }
    final main = p.primary;
    _primary = _UnitName(_nameOf(p, main));
    _primaryPrice.text = _money(main.price);
    _cost.text = _money(p.purchasePrice * main.size);
    _reorderLevel.text = formatQty(p.reorderLevel / main.size);
    for (final u in p.sellUnits) {
      if (u.label == main.label) continue;
      final f = u.size / main.size;
      _units.add(_UnitRow(_nameOf(p, u), bigger: f >= 1, perPrimary: formatQty(f >= 1 ? f : 1 / f), price: _money(u.price)));
    }
    _saleUnit = _nameOf(p, p.sellUnit(p.saleUnit));
  }

  /// The name a unit was entered as (undoing "sack 25kg" suffixes).
  static String _nameOf(Product p, ProductPack u) => u.size == 1 ? u.label : (packNameOf(u.label, u.size, p.unitLabel) ?? u.label);

  static String _money(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String get _main => _primary.value.isEmpty ? 'unit' : _primary.value;

  List<String> get _unitNames => [_main, for (final u in _units) if (u.name.value.isNotEmpty) u.name.value];

  UnitPlan _plan() => planUnits(_primary.value, double.tryParse(_primaryPrice.text) ?? 0, [
        for (final u in _units) (name: u.name.value, perPrimary: double.tryParse(u.perPrimary.text) ?? 0, bigger: u.bigger, price: double.tryParse(u.price.text) ?? 0),
      ]);

  /// Units whose minimum price is below cost: a warning (clearance is allowed).
  List<String> get _belowCost {
    final cost = double.tryParse(_cost.text) ?? 0;
    if (cost <= 0) return const [];
    return [
      if ((double.tryParse(_primaryPrice.text) ?? 0) < cost) _main,
      for (final u in _units)
        if ((double.tryParse(u.perPrimary.text) ?? 0) > 0 && (double.tryParse(u.price.text) ?? 0) < cost * (u.bigger ? double.parse(u.perPrimary.text) : 1 / double.parse(u.perPrimary.text)))
          u.name.value,
    ];
  }

  /// Owner-only fix of a wrong average cost (booked as a stock revaluation).
  bool _costCorrected = false;

  Future<void> _correctCost() async {
    final input = TextEditingController(text: _cost.text);
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correct cost'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Normally the cost comes from purchases. Change it only to fix a mistake; the stock on hand is re-valued in the books.'),
          TextField(controller: input, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Cost per $_main')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, double.tryParse(input.text)), child: const Text('Save')),
        ],
      ),
    );
    if (value == null || value < 0) return;
    setState(() {
      _cost.text = _money(value);
      _costCorrected = true;
    });
  }

  void _addUnit() => setState(() => _units.add(_UnitRow('', bigger: false)));

  /// Picking dozen against piece (or the reverse) fills in 12.
  void _named(_UnitRow row, String name) {
    if (row.perPrimary.text.isNotEmpty) return;
    if ((name == 'dozen' && _main == 'piece') || (name == 'piece' && _main == 'dozen')) {
      row
        ..bigger = name == 'dozen'
        ..perPrimary.text = '12';
    }
  }

  Widget _unitSection(BuildContext context) {
    TextField number(TextEditingController c, String label) => TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Units', style: Theme.of(context).textTheme.titleSmall),
      const Text('The main unit is how you buy and count it (e.g. sack). Add the other units it is sold in.', style: TextStyle(color: Colors.grey)),
      _UnitNameField(name: _primary, label: 'Main unit', onChanged: () => setState(() {})),
      number(_primaryPrice, 'Min. price per $_main (optional)'),
      const Text('Leave prices blank if you don\'t know them yet: until set, nothing sells below cost, and a purchase suggests them.', style: TextStyle(color: Colors.grey)),
      // Cost comes from purchases (weighted average); it's only asked for
      // goods already on hand, and only corrected by the owner.
      if (_isEditing)
        Row(children: [
          Expanded(
            child: Text(
              (double.tryParse(_cost.text) ?? 0) > 0 ? 'Average cost from purchases: ${formatNpr(double.parse(_cost.text))} / $_main' : 'No cost yet: it is set by the first purchase.',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          if (widget.auth.currentUser?.role == UserRole.owner) TextButton(onPressed: _correctCost, child: const Text('Correct cost')),
        ]),
      for (final (i, row) in _units.indexed)
        Card(
          margin: const EdgeInsets.only(top: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
            child: Column(children: [
              Row(children: [
                Expanded(child: _UnitNameField(name: row.name, label: 'Unit', onChanged: () => setState(() => _named(row, row.name.value)))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _units.removeAt(i))),
              ]),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<bool>(
                    key: ValueKey(row.bigger),
                    initialValue: row.bigger,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Size'),
                    items: [
                      DropdownMenuItem(value: false, child: Text('smaller than $_main', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: true, child: Text('bigger than $_main', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => row.bigger = v ?? row.bigger),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: number(row.perPrimary, row.bigger ? '$_main in it' : 'per $_main')),
              ]),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  row.bigger
                      ? '1 ${row.name.value.isEmpty ? 'unit' : row.name.value} = ${row.perPrimary.text.isEmpty ? '?' : row.perPrimary.text} $_main'
                      : '1 $_main = ${row.perPrimary.text.isEmpty ? '?' : row.perPrimary.text} ${row.name.value.isEmpty ? 'unit' : row.name.value}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
              number(row.price, 'Min. price per ${row.name.value.isEmpty ? 'unit' : row.name.value}'),
            ]),
          ),
        ),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Add unit'), onPressed: _addUnit)),
      if (_unitNames.length > 1)
        DropdownButtonFormField<String>(
          initialValue: _unitNames.contains(_saleUnit) ? _saleUnit : null,
          decoration: const InputDecoration(labelText: 'Usually sold in', helperText: 'A new sale line starts in this unit'),
          items: [for (final n in _unitNames) DropdownMenuItem(value: n, child: Text(n))],
          onChanged: (v) => setState(() => _saleUnit = v ?? _saleUnit),
        ),
      if (_belowCost.isNotEmpty) Text('Minimum price is below cost for: ${_belowCost.join(', ')}.', style: const TextStyle(color: Colors.orange)),
      if (_unitError != null) Text(_unitError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (!_isEditing) number(_stockQty, 'Opening stock ($_main)'),
      if (!_isEditing && (double.tryParse(_stockQty.text) ?? 0) > 0) number(_cost, 'Cost of the stock you already have, per $_main'),
      number(_reorderLevel, 'Low stock level ($_main)'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Product' : 'Add Product')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Product name')),
          if (_hasCategories) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category.isEmpty ? null : _category,
              decoration: const InputDecoration(labelText: 'Category'),
              // Includes a category added while Categories was off ([_defaultCategory]).
              items: {...widget.controller.categories, if (_category.isNotEmpty) _category}.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
          ],
          const SizedBox(height: 12),
          TextField(controller: _sku, decoration: const InputDecoration(labelText: 'SKU / code')),
          const SizedBox(height: 12),
          TextField(controller: _brand, decoration: const InputDecoration(labelText: 'Brand (optional)')),
          const SizedBox(height: 12),
          _unitSection(context),
          const SizedBox(height: 12),
          TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
          if (widget.settings.current.vatRegistered)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('VAT exempt'),
              subtitle: const Text('Sold without VAT. Check with your accountant which goods qualify.'),
              value: _vatExempt,
              onChanged: (v) => setState(() => _vatExempt = v),
            ),
          if (_isEditing) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive products are hidden from customer browsing'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(_isEditing ? 'Save Changes' : 'Add Product')),
        ],
      ),
    );
  }

  void _save() {
    if (_name.text.trim().isEmpty || _category.isEmpty) return;
    final UnitPlan plan;
    try {
      plan = _plan();
    } on ArgumentError catch (e) {
      setState(() => _unitError = '${e.message}');
      return;
    }
    final existing = widget.product;
    if (existing != null && (existing.stockQty != 0 || existing.reservedQty != 0)) {
      // Stock is counted in the smallest unit: with stock on hand, that and
      // the existing conversions stay as they are (new units can be added).
      final sizes = {for (final u in existing.sellUnits) u.label: u.size};
      final moved = plan.base != existing.unitLabel || plan.packs.any((k) => sizes.containsKey(k.label) && sizes[k.label] != k.size);
      if (moved) {
        setState(() => _unitError = 'This product has stock, so its smallest unit (${existing.unitLabel}) and existing conversions can\'t change. You can add units or change prices.');
        return;
      }
    }
    final base = baseUnitFor(plan.base);
    final primaryLabel = plan.primary == plan.base ? '' : plan.primary;
    final saleLabel = (_saleUnit.isEmpty || _saleUnit == plan.base)
        ? ''
        : plan.packs.firstWhere((k) => k.label == _saleUnit || packNameOf(k.label, k.size, plan.base) == _saleUnit, orElse: () => plan.packs.first).label;
    final perBase = (double.tryParse(_cost.text) ?? 0) / plan.primarySize;
    final reorder = (double.tryParse(_reorderLevel.text) ?? 0) * plan.primarySize;

    if (existing != null) {
      widget.controller.updateProduct(
        existing,
        userName: widget.auth.currentUser?.name ?? '',
        name: _name.text.trim(),
        category: _category,
        sku: _sku.text.trim(),
        brand: _brand.text.trim(),
        unit: base.unit,
        customUnitLabel: base.custom,
        unitPrice: plan.basePrice,
        purchasePrice: _costCorrected ? perBase : null,
        packs: plan.packs,
        reorderLevel: reorder,
        description: _description.text.trim(),
        isActive: _isActive,
        vatExempt: _vatExempt,
        primaryUnit: primaryLabel,
        saleUnit: saleLabel,
      );
    } else {
      widget.controller.createProduct(
        name: _name.text.trim(),
        category: _category,
        sku: _sku.text.trim(),
        brand: _brand.text.trim(),
        unit: base.unit,
        customUnitLabel: base.custom,
        unitPrice: plan.basePrice,
        purchasePrice: (double.tryParse(_stockQty.text) ?? 0) > 0 ? perBase : 0,
        packs: plan.packs,
        stockQty: (double.tryParse(_stockQty.text) ?? 0) * plan.primarySize,
        reorderLevel: reorder,
        description: _description.text.trim(),
        vatExempt: _vatExempt,
        primaryUnit: primaryLabel,
        saleUnit: saleLabel,
      );
    }
    Navigator.pop(context);
  }
}

/// A unit name: one of [kUnitNames], or typed under "Other…".
class _UnitName {
  _UnitName(String initial) {
    if (initial.isEmpty || kUnitNames.contains(initial)) {
      choice = initial.isEmpty ? null : initial;
    } else {
      choice = otherName;
      other.text = initial;
    }
  }

  static const otherName = 'Other…';

  String? choice;
  final other = TextEditingController();

  String get value => choice == otherName ? other.text.trim() : (choice ?? '');
}

class _UnitRow {
  _UnitRow(String name, {required this.bigger, String perPrimary = '', String price = ''})
      : name = _UnitName(name),
        perPrimary = TextEditingController(text: perPrimary),
        price = TextEditingController(text: price);

  final _UnitName name;
  bool bigger;
  final TextEditingController perPrimary;
  final TextEditingController price;
}

class _UnitNameField extends StatelessWidget {
  const _UnitNameField({required this.name, required this.label, required this.onChanged});

  final _UnitName name;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      DropdownButtonFormField<String>(
        initialValue: name.choice,
        decoration: InputDecoration(labelText: label),
        items: [for (final n in [...kUnitNames, _UnitName.otherName]) DropdownMenuItem(value: n, child: Text(n))],
        onChanged: (v) {
          name.choice = v;
          onChanged();
        },
      ),
      if (name.choice == _UnitName.otherName)
        TextField(controller: name.other, decoration: const InputDecoration(labelText: 'Unit name', hintText: 'bori'), onChanged: (_) => onChanged()),
    ]);
  }
}
