import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_form_sheet.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/customer_picker.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_item.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/presentation/widgets/cart_editor.dart';

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
  final List<CartLine> _lines = [];
  String? _error;

  bool get _allowBelowMinimum => widget.auth.can(Permission.sellBelowMinimum);

  double get _total {
    final lines = _lines.fold(0.0, (sum, l) => sum + l.total);
    final terms = widget.ordering.vatTerms;
    final vat = vatOn(_lines.where((l) => !l.product.vatExempt).fold(0.0, (sum, l) => sum + l.total), terms);
    return lines + (terms != null && !terms.included ? vat : 0);
  }

  void _place() {
    final customer = _customer!;
    final problem = cartProblem(_lines, checkMinimum: true, allowBelowMinimum: _allowBelowMinimum, checkStock: true);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final items = [for (final l in _lines) OrderItem(product: l.product, qty: l.qtyValue, price: l.priceValue, unit: l.unit.label, size: l.unit.size)];
    try {
      final order = widget.ordering.placeOrderFor(customer, items,
          deliveryType: _deliveryType, address: _address.text.trim(), notes: _notes.text.trim(), staff: widget.auth.currentUser!);
      if (order == null) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order ${order.id} placed for ${customer.name} (${formatNpr(order.total)})'
            ''),
      ));
    } on PaymentException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } on BelowMinimumPriceException catch (e) {
      setState(() => _error = e.message);
    } on UnpricedProductException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.customers, widget.inventory]),
      builder: (context, _) {
        final customer = _customer;
        return Scaffold(
          appBar: AppBar(title: const Text('New Order for Customer')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(
                  child: CustomerPicker(
                    customers: widget.customers.customers,
                    selected: customer,
                    label: 'Customer',
                    onSelected: (c) => setState(() {
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
                    'Balance ${formatNpr(customer.outstandingBalance)} of ${formatNpr(customer.creditLimit)} limit',
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
              const SizedBox(height: 8),
              CartEditor(
                products: widget.inventory.products.where((p) => p.isActive).toList(),
                lines: _lines,
                onChanged: () => setState(() => _error = null),
                priceFor: (p, unit) => p.floorFor(unit.label) ?? 0,
                allowBelowMinimum: _allowBelowMinimum,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                onPressed: customer == null || _lines.isEmpty ? null : _place,
                child: Text('Place Order · ${formatNpr(_total)}'),
              ),
            ),
          ),
        );
      },
    );
  }
}
