import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/signature_pad.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
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
      allowZero: true,
      signatureRequired: ordering.signatureRequired,
      onSubmit: (input) async {
        await ordering.deliverAndCollect(order,
            amount: input.amount,
            method: input.method,
            reference: input.reference,
            signature: input.signature,
            signedName: input.signedName,
            collector: auth.currentUser!);
        return input.amount == 0 ? 'Delivered on credit.' : 'Delivered — ${formatNpr(input.amount)} recorded.';
      },
    ),
  );
}

enum _Viewer { staff, deliverer, readOnly }

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.order, required this.controller, required this.auth, this.staffView = false});

  final CustomerOrder order;
  final OrderingController controller;
  final AuthController auth;

  /// Owner/employee view (manage the order). Delivery staff get their own
  /// view automatically.
  final bool staffView;

  _Viewer get _viewer {
    final user = auth.currentUser!;
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

        return Scaffold(
          appBar: AppBar(title: Text('Order ${order.id}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(order.customer.name, style: Theme.of(context).textTheme.titleMedium),
              Text('${order.deliveryType == DeliveryType.delivery ? 'Delivery' : 'Pickup'} · ${formatDate(order.createdDate)}'),
              if (order.address.isNotEmpty) Text('Address: ${order.address}'),
              if (order.notes.isNotEmpty) Text('Notes: ${order.notes}'),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusBadge(label: order.assignedToId == null ? 'Not assigned' : 'Delivery: ${order.assignedToName}', color: Colors.indigo),
                StatusBadge(label: 'Customer balance ${formatNpr(order.customer.outstandingBalance)}', color: Colors.blueGrey),
              ]),
              const SizedBox(height: 16),
              if (order.status != OrderStatus.cancelled) _StatusTimeline(current: order.status) else const Text('This order was cancelled.', style: TextStyle(color: Colors.red)),
              const SizedBox(height: 24),
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              ...order.items.map((item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.product.name),
                    subtitle: Text('${formatQty(item.qty)} ${item.unit} × ${formatNpr(item.price)}'),
                    trailing: Text(formatNpr(item.lineTotal)),
                  )),
              const Divider(),
              if (order.vatAmount > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text('VAT${order.vatIncluded ? ' (included)' : ''}'), Text(formatNpr(order.vatAmount))],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)), Text(formatNpr(order.total), style: const TextStyle(fontWeight: FontWeight.bold))],
              ),
              if (Signature.decode(order.receivedSignature) case final signature?) ...[
                const SizedBox(height: 16),
                Text('Received by ${order.receivedBy}', style: Theme.of(context).textTheme.titleSmall),
                SignatureView(signature: signature),
              ],
              if (order.placedByStaffName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Order taken by ${order.placedByStaffName}')),
              if (payments.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Payments at delivery', style: Theme.of(context).textTheme.titleMedium),
                for (final p in payments) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: PaymentReceipt(payment: p, businessName: controller.businessName)),
              ],
              const SizedBox(height: 24),
              if (viewer == _Viewer.staff && open) _StaffActions(order: order, controller: controller, auth: auth),
              if (viewer == _Viewer.deliverer && open) _DelivererActions(order: order, controller: controller, auth: auth),
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
        const SizedBox(height: 12),
        Row(
          children: [
            if (nextStatus != null)
              Expanded(
                child: NextOrderButton(order: order, ordering: controller, auth: auth),
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

/// The one primary button that moves an order to its next status.
/// The delivered step opens Deliver & Collect instead of advancing directly.
class NextOrderButton extends StatelessWidget {
  const NextOrderButton({super.key, required this.order, required this.ordering, required this.auth});

  final CustomerOrder order;
  final OrderingController ordering;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final next = nextOrderStatus(order.status)!;
    return FilledButton(
      onPressed: () => next == OrderStatus.delivered
          ? showDeliverSheet(context, order, ordering, auth)
          : ordering.advanceOrderStatus(order, next, userName: auth.currentUser?.name ?? '', userId: auth.currentUser?.id),
      child: Text(next == OrderStatus.delivered ? 'Deliver & Collect' : 'Next: ${orderStatusLabel(next)}'),
    );
  }
}
