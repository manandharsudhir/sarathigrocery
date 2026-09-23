import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';

/// Marks [order] delivered and records what the customer paid at the door.
void showDeliverSheet(BuildContext context, CustomerOrder order, OrderingController ordering, AuthController auth) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => CollectPaymentForm(
      customer: order.customer,
      submitLabel: 'Deliver & Collect',
      orderTotal: order.total,
      orderAlreadyPaid: ordering.paidFor(order),
      askForCode: true,
      allowZero: true,
      onSubmit: (amount, method, reference, code) async {
        await ordering.deliverAndCollect(order, amount: amount, method: method, reference: reference, deliveryCode: code, collector: auth.currentUser!);
        return amount == 0 ? 'Delivered on credit.' : 'Delivered — ${formatNpr(amount)} recorded.';
      },
    ),
  );
}

enum _Viewer { customer, staff, deliverer, readOnly }

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.order, required this.controller, required this.auth, this.staffView = false});

  final CustomerOrder order;
  final OrderingController controller;
  final AuthController auth;

  /// Owner/employee view (manage the order). Delivery staff and customers
  /// get their own views automatically.
  final bool staffView;

  _Viewer get _viewer {
    final user = auth.currentUser!;
    if (user.role == UserRole.customer) return _Viewer.customer;
    if (staffView) return _Viewer.staff;
    if (order.assignedToId == user.id && user.can(Permission.deliverOrders)) return _Viewer.deliverer;
    return _Viewer.readOnly;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final viewer = _viewer;
        final open = order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled;
        final payments = controller.paymentsFor(order);
        final code = viewer == _Viewer.customer && open ? controller.deliveryCodeFor(order) : null;

        return Scaffold(
          appBar: AppBar(title: Text('Order ${order.id}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(order.customer.name, style: Theme.of(context).textTheme.titleMedium),
              Text('${order.deliveryType == DeliveryType.delivery ? 'Delivery' : 'Pickup'} · ${formatDate(order.createdDate)}'),
              if (order.address.isNotEmpty) Text('Address: ${order.address}'),
              if (order.notes.isNotEmpty) Text('Notes: ${order.notes}'),
              if (viewer != _Viewer.customer) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (order.overCreditLimit) const StatusBadge(label: 'Over credit limit', color: Colors.red),
                  StatusBadge(label: order.assignedToId == null ? 'Not assigned' : 'Delivery: ${order.assignedToName}', color: Colors.indigo),
                  StatusBadge(label: 'Customer balance ${formatNpr(order.customer.outstandingBalance)}', color: Colors.blueGrey),
                ]),
              ],
              if (code != null) _DeliveryCodeCard(code: code),
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
              if (payments.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Payments at delivery', style: Theme.of(context).textTheme.titleMedium),
                for (final p in payments) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: PaymentReceipt(payment: p)),
              ],
              const SizedBox(height: 24),
              if (viewer == _Viewer.staff && open) _StaffActions(order: order, controller: controller, auth: auth),
              if (viewer == _Viewer.deliverer && open) _DelivererActions(order: order, controller: controller, auth: auth),
              if (viewer == _Viewer.customer && !open)
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

class _DeliveryCodeCard extends StatelessWidget {
  const _DeliveryCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 16),
      elevation: 0,
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Delivery code'),
            Text(code, style: Theme.of(context).textTheme.displaySmall?.copyWith(letterSpacing: 6, fontWeight: FontWeight.bold)),
            const Text('Give this to the delivery person only after you agree the amount you are paying. It proves you approved it — never share it earlier.'),
          ],
        ),
      ),
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
    final user = auth.currentUser!;
    final deliverers = controller.deliverers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: deliverers.any((d) => d.id == order.assignedToId) ? order.assignedToId : null,
          decoration: const InputDecoration(labelText: 'Delivered by'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Not assigned')),
            for (final d in deliverers) DropdownMenuItem(value: d.id, child: Text(d.id == user.id ? '${d.name} (me)' : d.name)),
          ],
          onChanged: (id) => controller.assign(order, deliverers.where((d) => d.id == id).firstOrNull, by: user),
        ),
        if (user.role == UserRole.owner)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.lock_reset, size: 18),
              label: const Text('Unlock delivery code'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final attempts = await controller.codeAttempts(order);
                if (attempts == 0) {
                  messenger.showSnackBar(const SnackBar(content: Text('No wrong codes tried for this order.')));
                  return;
                }
                controller.resetCodeAttempts(order, by: user);
                messenger.showSnackBar(SnackBar(content: Text('Reset after $attempts attempt${attempts == 1 ? '' : 's'}.')));
              },
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (nextStatus != null)
              Expanded(
                child: FilledButton(
                  onPressed: () => nextStatus == OrderStatus.delivered
                      ? showDeliverSheet(context, order, controller, auth)
                      : controller.advanceOrderStatus(order, nextStatus, userName: user.name, userId: user.id),
                  child: Text(nextStatus == OrderStatus.delivered ? 'Deliver & Collect' : 'Mark ${orderStatusLabel(nextStatus)}'),
                ),
              ),
            if (nextStatus != null) const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => controller.advanceOrderStatus(order, OrderStatus.cancelled, userName: user.name, userId: user.id),
                child: const Text('Cancel Order'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Delivery staff: take it out, then deliver & collect. Nothing else.
class _DelivererActions extends StatelessWidget {
  const _DelivererActions({required this.order, required this.controller, required this.auth});

  final CustomerOrder order;
  final OrderingController controller;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser!;
    if (order.status == OrderStatus.outForDelivery) {
      return FilledButton.icon(
        icon: const Icon(Icons.handshake_outlined),
        onPressed: () => showDeliverSheet(context, order, controller, auth),
        label: const Text('Deliver & Collect'),
      );
    }
    if (order.status == OrderStatus.ready) {
      return FilledButton.icon(
        icon: const Icon(Icons.local_shipping_outlined),
        onPressed: () => controller.advanceOrderStatus(order, OrderStatus.outForDelivery, userName: user.name, userId: user.id),
        label: const Text('Start Delivery'),
      );
    }
    return const Text('Waiting for the shop to get this order ready.');
  }
}

/// Shown on lists: how much of an order was paid at delivery.
String orderPaymentSummary(CustomerOrder order, List<CustomerPayment> payments) {
  final paid = payments.where((p) => !p.isReversed).fold(0.0, (s, p) => s + p.amount);
  if (order.status != OrderStatus.delivered) return '';
  if (paid <= 0) return 'On credit';
  return paid >= order.total ? 'Paid ${formatNpr(paid)}' : 'Part paid ${formatNpr(paid)}';
}
