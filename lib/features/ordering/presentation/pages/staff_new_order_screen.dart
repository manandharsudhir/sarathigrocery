import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_form_sheet.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/new_sale_screen.dart';

/// Staff take an order for a customer — typically one who phoned or sent a
/// WhatsApp message and may not have the app. It then follows the normal
/// order → delivery → Deliver & Collect flow.
class StaffNewOrderScreen extends StatefulWidget {
  const StaffNewOrderScreen({super.key, required this.ordering, required this.customers, required this.inventory, required this.auth});

  final OrderingController ordering;
  final CustomersController customers;
  final InventoryController inventory;
  final AuthController auth;

  @override
  State<StaffNewOrderScreen> createState() => _StaffNewOrderScreenState();
}

class _StaffNewOrderScreenState extends State<StaffNewOrderScreen> {
  Customer? _customer;
  DeliveryType _deliveryType = DeliveryType.delivery;
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final Map<Product, int> _items = {};

  double get _subtotal => _items.entries.fold(0.0, (sum, e) => sum + e.key.unitPrice * e.value);

  void _place() {
    final customer = _customer!;
    try {
      final order = widget.ordering.placeOrderFor(customer, _items,
          deliveryType: _deliveryType, address: _address.text.trim(), notes: _notes.text.trim(), staff: widget.auth.currentUser!);
      if (order == null) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order ${order.id} placed for ${customer.name} (${formatNpr(order.total)})'
            '${order.overCreditLimit ? ' — over credit limit' : ''}'),
      ));
    } on PaymentException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.customers, widget.inventory]),
      builder: (context, _) {
        final products = widget.inventory.products.where((p) => p.isActive).toList();
        final customer = _customer;
        return Scaffold(
          appBar: AppBar(title: const Text('New Order for Customer')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<Customer>(
                    initialValue: customer,
                    decoration: const InputDecoration(labelText: 'Customer'),
                    items: [for (final c in widget.customers.customers) DropdownMenuItem(value: c, child: Text(c.name))],
                    onChanged: (c) => setState(() {
                      _customer = c;
                      if (_address.text.isEmpty && c != null) _address.text = c.location;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'New customer',
                  icon: const Icon(Icons.person_add_alt),
                  onPressed: () => showCustomerFormSheet(context, widget.customers, widget.auth),
                ),
              ]),
              if (customer != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Balance ${formatNpr(customer.outstandingBalance)} of ${formatNpr(customer.creditLimit)} limit · '
                    '${customer.hasAppLogin ? 'uses the app' : 'no app — will sign on delivery'}',
                  ),
                ),
              const SizedBox(height: 12),
              SegmentedButton<DeliveryType>(
                segments: const [
                  ButtonSegment(value: DeliveryType.delivery, label: Text('Delivery'), icon: Icon(Icons.local_shipping)),
                  ButtonSegment(value: DeliveryType.pickup, label: Text('Pickup'), icon: Icon(Icons.storefront)),
                ],
                selected: {_deliveryType},
                onSelectionChanged: (s) => setState(() => _deliveryType = s.first),
              ),
              if (_deliveryType == DeliveryType.delivery) TextField(controller: _address, decoration: const InputDecoration(labelText: 'Delivery address')),
              TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (e.g. "ordered by phone")')),
              const SizedBox(height: 16),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              for (final p in products)
                ProductQtyRow(
                  product: p,
                  qty: _items[p] ?? 0,
                  onChanged: (qty) => setState(() => qty <= 0 ? _items.remove(p) : _items[p] = qty),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: customer == null || _items.isEmpty ? null : _place,
                child: Text('Place Order · ${formatNpr(_subtotal - _subtotal * (customer?.defaultDiscountPercent ?? 0) / 100)}'),
              ),
            ),
          ),
        );
      },
    );
  }
}
