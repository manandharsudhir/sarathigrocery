import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/order_detail_screen.dart';

/// Delivery staff home: orders assigned to me, each with its next step.
class DeliveriesScreen extends StatelessWidget {
  const DeliveriesScreen({super.key, required this.ordering, required this.auth});

  final OrderingController ordering;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ordering,
      builder: (context, _) {
        final user = auth.currentUser!;
        final mine = ordering.assignedTo(user)..sort((a, b) => b.updatedDate.compareTo(a.updatedDate));
        final open = mine.where((o) => o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled).toList();
        final done = mine.where((o) => o.status == OrderStatus.delivered).take(20).toList();

        Widget tile(CustomerOrder order) {
          final isOpen = open.contains(order);
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
            child: ListTile(
              title: Text(order.customer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                '${order.id} · ${formatNpr(order.total)} · ${orderStatusLabel(order.status)}',
                if (order.address.isNotEmpty) order.address,
                if (isOpen) 'Customer balance ${formatNpr(order.customer.outstandingBalance)}'
                else orderPaymentSummary(order, ordering.paymentsFor(order)),
              ].join('\n')),
              isThreeLine: true,
              trailing: isOpen && order.status == OrderStatus.outForDelivery
                  ? FilledButton(onPressed: () => showDeliverSheet(context, order, ordering, auth), child: const Text('Deliver'))
                  : isOpen && order.status == OrderStatus.ready
                      ? FilledButton.tonal(
                          onPressed: () => ordering.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: user.name, userId: user.id),
                          child: const Text('Start'),
                        )
                      : null,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order, controller: ordering, auth: auth))),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('My Deliveries')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (open.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No deliveries assigned right now.'))),
              ...open.map(tile),
              if (done.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Delivered', style: Theme.of(context).textTheme.titleMedium),
                ...done.map(tile),
              ],
            ],
          ),
        );
      },
    );
  }
}
