import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.ordering, required this.customers, required this.auth});

  final OrderingController ordering;
  final CustomersController customers;
  final AuthController auth;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  DeliveryType _deliveryType = DeliveryType.pickup;
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...widget.ordering.cart.map((item) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.product.name),
                subtitle: Text('x${item.qty}'),
                trailing: Text(formatNpr(item.lineTotal)),
              )),
          const Divider(),
          Text('Total: ${formatNpr(widget.ordering.cartTotal)}', style: Theme.of(context).textTheme.headlineSmall),
          Builder(builder: (context) {
            final customer = widget.customers.customers.where((c) => c.id == widget.auth.currentUser?.linkedCustomerId).firstOrNull;
            if (customer == null) return const SizedBox.shrink();
            final after = widget.ordering.creditExposure(customer) + widget.ordering.cartTotal;
            final over = after > customer.creditLimit;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                over
                    ? 'With open orders this comes to ${formatNpr(after)}, over your ${formatNpr(customer.creditLimit)} credit limit. You can still order; the shop will confirm first.'
                    : 'Credit after this order: ${formatNpr(after)} of ${formatNpr(customer.creditLimit)}.',
                style: TextStyle(color: over ? Theme.of(context).colorScheme.error : null),
              ),
            );
          }),
          const SizedBox(height: 24),
          SegmentedButton<DeliveryType>(
            segments: const [
              ButtonSegment(value: DeliveryType.pickup, label: Text('Pickup'), icon: Icon(Icons.storefront)),
              ButtonSegment(value: DeliveryType.delivery, label: Text('Delivery'), icon: Icon(Icons.local_shipping)),
            ],
            selected: {_deliveryType},
            onSelectionChanged: (s) => setState(() => _deliveryType = s.first),
          ),
          if (_deliveryType == DeliveryType.delivery) ...[
            const SizedBox(height: 12),
            TextField(controller: _addressController, decoration: const InputDecoration(labelText: 'Delivery address')),
          ],
          const SizedBox(height: 12),
          TextField(controller: _notesController, decoration: const InputDecoration(labelText: 'Notes (optional)')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: widget.ordering.cart.isEmpty ? null : _placeOrder,
            child: const Text('Place Order'),
          ),
        ),
      ),
    );
  }

  void _placeOrder() {
    final customerId = widget.auth.currentUser?.linkedCustomerId;
    final matches = widget.customers.customers.where((c) => c.id == customerId);
    if (matches.isEmpty) return;
    final customer = matches.first;

    final order = widget.ordering.placeOrder(
      customer,
      deliveryType: _deliveryType,
      address: _addressController.text.trim(),
      notes: _notesController.text.trim(),
      userName: widget.auth.currentUser?.name ?? '',
      userId: widget.auth.currentUser?.id,
    );
    if (order == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Order Placed'),
        content: Text('Order ${order.id} placed for ${formatNpr(order.total)}.'
            '${order.overCreditLimit ? '\n\nThis takes you over your credit limit, so the shop will confirm before delivering.' : ''}'
            '\n\nOn delivery, open the order to see your delivery code. Give it to the delivery person only once you agree the amount you are paying.'),
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
