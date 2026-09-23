import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_constants.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key, required this.sales, required this.inventory, required this.customers, required this.auth});

  final SalesController sales;
  final InventoryController inventory;
  final CustomersController customers;
  final AuthController auth;

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  Customer? _customer;
  bool _isCredit = false;
  double _discountPercent = 0;
  final _discountController = TextEditingController(text: '0');
  final Map<Product, int> _cart = {};

  double get _subtotal => _cart.entries.fold(0.0, (sum, e) => sum + e.key.unitPrice * e.value);
  double get _total => _subtotal - _subtotal * _discountPercent / 100;

  @override
  Widget build(BuildContext context) {
    final products = widget.inventory.products.where((p) => p.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('New Sale')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<Customer?>(
            initialValue: _customer,
            decoration: const InputDecoration(labelText: 'Customer (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Walk-in / Cash customer')),
              ...widget.customers.customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))),
            ],
            onChanged: (c) => setState(() {
              _customer = c;
              if (c == null) {
                _isCredit = false;
              } else if (c.defaultDiscountPercent > 0 && _discountPercent == 0) {
                _discountPercent = c.defaultDiscountPercent;
                _discountController.text = _discountPercent.toStringAsFixed(0);
              }
            }),
          ),
          const SizedBox(height: 16),
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...products.map((p) => _ProductRow(
                product: p,
                qty: _cart[p] ?? 0,
                onChanged: (qty) => setState(() {
                  if (qty <= 0) {
                    _cart.remove(p);
                  } else {
                    _cart[p] = qty;
                  }
                }),
              )),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discountController,
                  decoration: const InputDecoration(labelText: 'Discount %'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => _discountPercent = double.tryParse(v) ?? 0),
                ),
              ),
              const SizedBox(width: 16),
              if (_customer != null)
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Udharo (Credit)'),
                    value: _isCredit,
                    onChanged: (v) => setState(() => _isCredit = v),
                  ),
                ),
            ],
          ),
          if (_discountPercent > kMaxAutoApprovedDiscountPercent)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Discount above 10% needs joint approval.',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          const SizedBox(height: 24),
          Text('Total: ${formatNpr(_total)}', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _cart.isEmpty ? null : _submit,
            child: const Text('Complete Sale'),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final items = _cart.entries
        .map((e) => SaleItem(product: e.key, qty: e.value, unitPrice: e.key.unitPrice))
        .toList();

    final sale = widget.sales.recordSale(
      items: items,
      discountPercent: _discountPercent,
      isCredit: _isCredit,
      customer: _customer,
      userName: widget.auth.currentUser?.name ?? '',
      userId: widget.auth.currentUser?.id,
    );
    final needsApproval = sale.flaggedForApproval;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(needsApproval ? 'Sale Flagged for Approval' : 'Sale Complete'),
        content: Text(
          '${_customer?.name ?? 'Walk-in customer'}\n'
          'Total: ${formatNpr(_total)}\n'
          '${_isCredit ? 'Recorded as Udharo (Credit)' : 'Paid in cash'}'
          '${needsApproval ? '\n\nThis order exceeds normal discount or credit limits and needs joint sign-off.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.qty, required this.onChanged});

  final Product product;
  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(product.name),
      subtitle: Text('${formatNpr(product.unitPrice)} · ${product.availableStock} available'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: qty > 0 ? () => onChanged(qty - 1) : null,
          ),
          SizedBox(width: 24, child: Text('$qty', textAlign: TextAlign.center)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: qty < product.availableStock ? () => onChanged(qty + 1) : null,
          ),
        ],
      ),
    );
  }
}
