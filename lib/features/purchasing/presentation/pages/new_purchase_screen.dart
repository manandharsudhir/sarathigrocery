import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

class NewPurchaseScreen extends StatefulWidget {
  const NewPurchaseScreen({super.key, required this.purchasing, required this.suppliers, required this.inventory, required this.auth});

  final PurchasingController purchasing;
  final SuppliersController suppliers;
  final InventoryController inventory;
  final AuthController auth;

  @override
  State<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends State<NewPurchaseScreen> {
  Supplier? _supplier;
  final Map<Product, int> _qty = {};
  final Map<Product, double> _cost = {};
  final _paidController = TextEditingController(text: '0');

  double get _total => _qty.entries.fold(0.0, (sum, e) => sum + e.value * (_cost[e.key] ?? e.key.purchasePrice));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Purchase')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<Supplier>(
            initialValue: _supplier,
            decoration: const InputDecoration(labelText: 'Supplier'),
            items: widget.suppliers.suppliers.map((s) => DropdownMenuItem(value: s, child: Text(s.businessName))).toList(),
            onChanged: (s) => setState(() => _supplier = s),
          ),
          const SizedBox(height: 16),
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...widget.inventory.products.map((p) => _PurchaseRow(
                product: p,
                qty: _qty[p] ?? 0,
                cost: _cost[p] ?? p.purchasePrice,
                onQtyChanged: (v) => setState(() {
                  if (v <= 0) {
                    _qty.remove(p);
                  } else {
                    _qty[p] = v;
                  }
                }),
                onCostChanged: (v) => setState(() => _cost[p] = v),
              )),
          const SizedBox(height: 16),
          TextField(
            controller: _paidController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Paid now (NPR)'),
          ),
          const SizedBox(height: 24),
          Text('Total: ${formatNpr(_total)}', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _supplier == null || _qty.isEmpty ? null : _submit,
            child: const Text('Receive Stock'),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final items = _qty.entries
        .map((e) => PurchaseItem(product: e.key, qty: e.value, unitCost: _cost[e.key] ?? e.key.purchasePrice))
        .toList();
    widget.purchasing.createPurchase(
      supplier: _supplier!,
      items: items,
      paidAmount: double.tryParse(_paidController.text) ?? 0,
      userName: widget.auth.currentUser?.name ?? '',
    );
    Navigator.pop(context);
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.product, required this.qty, required this.cost, required this.onQtyChanged, required this.onCostChanged});

  final Product product;
  final int qty;
  final double cost;
  final ValueChanged<int> onQtyChanged;
  final ValueChanged<double> onCostChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(product.name, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: cost.toStringAsFixed(0),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cost', isDense: true),
              onChanged: (v) => onCostChanged(double.tryParse(v) ?? cost),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: qty > 0 ? () => onQtyChanged(qty - 1) : null),
          SizedBox(width: 24, child: Text('$qty', textAlign: TextAlign.center)),
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => onQtyChanged(qty + 1)),
        ],
      ),
    );
  }
}
