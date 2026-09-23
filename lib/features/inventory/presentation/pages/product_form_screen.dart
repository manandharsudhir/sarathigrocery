import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_unit.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.controller, required this.auth, this.product});

  final InventoryController controller;
  final AuthController auth;

  /// Null when creating a new product.
  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final _brand = TextEditingController(text: widget.product?.brand ?? '');
  late final _unitPrice = TextEditingController(text: widget.product == null ? '' : widget.product!.unitPrice.toStringAsFixed(0));
  late final _purchasePrice = TextEditingController(text: widget.product == null ? '' : widget.product!.purchasePrice.toStringAsFixed(0));
  late final _retailPrice = TextEditingController(text: widget.product?.retailPrice?.toStringAsFixed(0) ?? '');
  late final _reorderLevel = TextEditingController(text: widget.product == null ? '5' : widget.product!.reorderLevel.toString());
  late final _stockQty = TextEditingController(text: widget.product == null ? '0' : widget.product!.stockQty.toString());
  late final _description = TextEditingController(text: widget.product?.description ?? '');
  late final _customUnitLabel = TextEditingController(text: widget.product?.customUnitLabel ?? '');

  late String _category = widget.product?.category ?? (widget.controller.categories.isEmpty ? '' : widget.controller.categories.first);
  late ProductUnit _unit = widget.product?.unit ?? ProductUnit.piece;
  late bool _isActive = widget.product?.isActive ?? true;

  bool get _isEditing => widget.product != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Product' : 'Add Product')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Product name')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category.isEmpty ? null : _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: widget.controller.categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 12),
          TextField(controller: _sku, decoration: const InputDecoration(labelText: 'SKU / code')),
          const SizedBox(height: 12),
          TextField(controller: _brand, decoration: const InputDecoration(labelText: 'Brand (optional)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<ProductUnit>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Unit'),
            items: ProductUnit.values.map((u) => DropdownMenuItem(value: u, child: Text(u.name))).toList(),
            onChanged: (v) => setState(() => _unit = v ?? _unit),
          ),
          if (_unit == ProductUnit.custom) ...[
            const SizedBox(height: 12),
            TextField(controller: _customUnitLabel, decoration: const InputDecoration(labelText: 'Custom unit label')),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: TextField(controller: _purchasePrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase price'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _unitPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Wholesale price'))),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _retailPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Retail price (optional)')),
          const SizedBox(height: 12),
          if (!_isEditing) ...[
            TextField(controller: _stockQty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Opening stock quantity')),
            const SizedBox(height: 12),
          ],
          TextField(controller: _reorderLevel, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum stock level')),
          const SizedBox(height: 12),
          TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)')),
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
    final unitPrice = double.tryParse(_unitPrice.text) ?? 0;
    final purchasePrice = double.tryParse(_purchasePrice.text) ?? 0;
    final retailPrice = double.tryParse(_retailPrice.text);
    final reorderLevel = int.tryParse(_reorderLevel.text) ?? 0;

    if (_isEditing) {
      widget.controller.updateProduct(
        widget.product!,
        userName: widget.auth.currentUser?.name ?? '',
        name: _name.text.trim(),
        category: _category,
        sku: _sku.text.trim(),
        brand: _brand.text.trim(),
        unit: _unit,
        customUnitLabel: _customUnitLabel.text.trim(),
        unitPrice: unitPrice,
        purchasePrice: purchasePrice,
        retailPrice: retailPrice,
        reorderLevel: reorderLevel,
        description: _description.text.trim(),
        isActive: _isActive,
      );
    } else {
      widget.controller.createProduct(
        name: _name.text.trim(),
        category: _category,
        sku: _sku.text.trim(),
        brand: _brand.text.trim(),
        unit: _unit,
        customUnitLabel: _customUnitLabel.text.trim(),
        unitPrice: unitPrice,
        purchasePrice: purchasePrice,
        retailPrice: retailPrice,
        stockQty: int.tryParse(_stockQty.text) ?? 0,
        reorderLevel: reorderLevel,
        description: _description.text.trim(),
      );
    }
    Navigator.pop(context);
  }
}
