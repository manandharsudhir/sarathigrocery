import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/widgets/cart_editor.dart';
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
  final List<CartLine> _lines = [];
  final _paidController = TextEditingController(text: '0');
  String _account = 'cash';
  final _billNo = TextEditingController();
  final _vat = TextEditingController();
  DateTime _billDate = DateTime.now();
  String? _error;

  /// Whoever manages products also sets new selling prices here.
  bool get _setsPrices => widget.auth.can(Permission.manageProducts);

  double get _total => _lines.fold(0.0, (sum, l) => sum + l.total) + (double.tryParse(_vat.text) ?? 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Purchase')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownMenu<Supplier>(
            initialSelection: _supplier,
            label: const Text('Supplier'),
            expandedInsets: EdgeInsets.zero,
            enableFilter: true,
            requestFocusOnTap: true,
            dropdownMenuEntries: [for (final s in widget.suppliers.suppliers) DropdownMenuEntry(value: s, label: s.businessName)],
            onSelected: (s) => setState(() => _supplier = s),
          ),
          const SizedBox(height: 16),
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          CartEditor(
            products: widget.inventory.products,
            lines: _lines,
            onChanged: () => setState(() => _error = null),
            priceFor: (product, unit) => product.purchasePrice * unit.size,
            priceLabel: 'Cost',
            showMinimum: false,
            editSellPrice: _setsPrices,
            startUnit: (p) => p.primary,
            marginPercent: widget.purchasing.marginPercent,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (widget.purchasing.recordsVat) ...[
            const SizedBox(height: 16),
            Text('Supplier\'s bill (for the Purchase Book)', style: Theme.of(context).textTheme.titleSmall),
            TextField(controller: _billNo, decoration: const InputDecoration(labelText: 'Supplier bill no.')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bill date'),
              subtitle: Text('${formatDate(_billDate)} · ${formatBs(_billDate)}'),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _billDate, firstDate: DateTime(2018), lastDate: DateTime.now());
                if (d != null) setState(() => _billDate = d);
              },
            ),
            TextField(
              controller: _vat,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'VAT on the bill', helperText: 'Costs above are without VAT'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _paidController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Paid now (NPR)'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _account,
            decoration: const InputDecoration(labelText: 'Paid from'),
            items: [for (final a in widget.purchasing.moneyAccounts) DropdownMenuItem(value: a, child: Text(accountName(a)))],
            onChanged: (v) => setState(() => _account = v ?? _account),
          ),
          const SizedBox(height: 24),
          Text('Total: ${formatNpr(_total)}', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _supplier == null || _lines.isEmpty ? null : _submit,
            child: const Text('Receive Stock'),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final problem = cartProblem(_lines);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final userName = widget.auth.currentUser?.name ?? '';
    widget.purchasing.createPurchase(
      supplier: _supplier!,
      items: [for (final l in _lines) PurchaseItem(product: l.product, qty: l.qtyValue, unitCost: l.priceValue, unit: l.unit.label, size: l.unit.size)],
      paidAmount: double.tryParse(_paidController.text) ?? 0,
      userName: userName,
      account: _account,
      vatAmount: double.tryParse(_vat.text) ?? 0,
      supplierBillNo: _billNo.text.trim(),
      supplierBillDate: widget.purchasing.recordsVat ? _billDate : null,
    );
    for (final l in _lines) {
      final price = double.tryParse(l.sellPrice.text);
      if (price == null) continue;
      final p = l.product;
      if (l.unit.size == 1 && l.unit.label == p.unitLabel) {
        widget.inventory.updateProduct(p, userName: userName, unitPrice: price);
      } else {
        widget.inventory.updateProduct(p, userName: userName, packs: [
          for (final k in p.packs) k.label == l.unit.label ? ProductPack(label: k.label, size: k.size, price: price) : k,
        ]);
      }
    }
    widget.purchasing.notifyPricesNeeded({for (final l in _lines) l.product}, userName: userName);
    Navigator.pop(context);
  }
}
