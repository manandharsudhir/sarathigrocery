import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key, required this.ordering, required this.customers, required this.auth});

  final OrderingController ordering;
  final CustomersController customers;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ordering,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Cart')),
          body: ordering.cart.isEmpty
              ? const Center(child: Text('Your cart is empty.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: ordering.cart.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = ordering.cart[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.product.name),
                      subtitle: Text(formatNpr(item.price)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => ordering.updateCartQty(item, item.qty - 1)),
                          SizedBox(width: 24, child: Text('${item.qty}', textAlign: TextAlign.center)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: item.qty < item.product.availableStock ? () => ordering.updateCartQty(item, item.qty + 1) : null,
                          ),
                        ],
                      ),
                    );
                  },
                ),
          bottomNavigationBar: ordering.cart.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(child: Text('Total: ${formatNpr(ordering.cartTotal)}', style: Theme.of(context).textTheme.titleMedium)),
                        FilledButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CheckoutScreen(ordering: ordering, customers: customers, auth: auth))),
                          child: const Text('Checkout'),
                        ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
