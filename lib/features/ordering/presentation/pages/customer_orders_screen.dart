import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/order_detail_screen.dart';

class CustomerOrdersScreen extends StatelessWidget {
  const CustomerOrdersScreen({super.key, required this.controller, required this.auth});

  final OrderingController controller;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final customerId = auth.currentUser?.linkedCustomerId;
        final orders = customerId == null
            ? const []
            : controller.orders.where((o) => o.customer.id == customerId).toList().reversed.toList();

        return Scaffold(
          appBar: AppBar(title: const Text('My Orders')),
          body: orders.isEmpty
              ? const Center(child: Text('No orders placed yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Order ${order.id}'),
                      subtitle: Text('${formatDate(order.createdDate)} · ${orderStatusLabel(order.status)}'),
                      trailing: Text(formatNpr(order.total)),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order, controller: controller, auth: auth))),
                    );
                  },
                ),
        );
      },
    );
  }
}
