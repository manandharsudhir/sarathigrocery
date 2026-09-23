import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.order, required this.controller, required this.auth, this.staffView = false});

  final CustomerOrder order;
  final OrderingController controller;
  final AuthController auth;
  final bool staffView;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text('Order ${order.id}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(order.customer.name, style: Theme.of(context).textTheme.titleMedium),
              Text('${order.deliveryType == DeliveryType.delivery ? 'Delivery' : 'Pickup'} · ${formatDate(order.createdDate)}'),
              if (order.address.isNotEmpty) Text('Address: ${order.address}'),
              if (order.notes.isNotEmpty) Text('Notes: ${order.notes}'),
              const SizedBox(height: 16),
              if (order.status != OrderStatus.cancelled) _StatusTimeline(current: order.status) else const Text('This order was cancelled.', style: TextStyle(color: Colors.red)),
              const SizedBox(height: 24),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              ...order.items.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.product.name),
                    subtitle: Text('x${item.qty}'),
                    trailing: Text(formatNpr(item.lineTotal)),
                  )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)), Text(formatNpr(order.total), style: const TextStyle(fontWeight: FontWeight.bold))],
              ),
              const SizedBox(height: 24),
              if (staffView && order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled)
                _StaffActions(order: order, controller: controller, auth: auth),
              if (!staffView && (order.status == OrderStatus.delivered || order.status == OrderStatus.cancelled))
                FilledButton.icon(
                  onPressed: () {
                    controller.repeatOrder(order);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Items added to cart')));
                  },
                  icon: const Icon(Icons.replay),
                  label: const Text('Repeat Order'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.current});

  final OrderStatus current;

  @override
  Widget build(BuildContext context) {
    final currentIndex = orderLifecycle.indexOf(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: orderLifecycle.asMap().entries.map((entry) {
        final reached = entry.key <= currentIndex;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(reached ? Icons.check_circle : Icons.radio_button_unchecked, color: reached ? Colors.green : Colors.grey, size: 20),
              const SizedBox(width: 8),
              Text(orderStatusLabel(entry.value), style: TextStyle(fontWeight: entry.key == currentIndex ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _StaffActions extends StatelessWidget {
  const _StaffActions({required this.order, required this.controller, required this.auth});

  final CustomerOrder order;
  final OrderingController controller;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final nextStatus = nextOrderStatus(order.status);
    final userName = auth.currentUser?.name ?? '';

    return Row(
      children: [
        if (nextStatus != null)
          Expanded(
            child: FilledButton(
              onPressed: () => controller.advanceOrderStatus(order, nextStatus, userName: userName),
              child: Text('Mark ${orderStatusLabel(nextStatus)}'),
            ),
          ),
        if (nextStatus != null) const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: () => controller.advanceOrderStatus(order, OrderStatus.cancelled, userName: userName),
            child: const Text('Cancel Order'),
          ),
        ),
      ],
    );
  }
}
