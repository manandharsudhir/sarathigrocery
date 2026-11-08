import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/signature_pad.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/delivery_type.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/customers/presentation/pdf/payment_documents.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/pdf/order_slip_pdf.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/invoice_screen.dart';
import 'package:sarathigrocery/features/sales/presentation/pdf/invoice_pdf.dart';

/// Marks [order] delivered and records what the customer paid at the door
/// (and, for an order billed at dispatch, any goods they refused), then
/// offers its bill (like after a sale).
Future<void> showDeliverSheet(BuildContext context, CustomerOrder order, OrderingController ordering, AuthController auth, SalesController sales) async {
  // The tile that opened this may be gone once the order is delivered.
  final navigator = Navigator.of(context);
  final billed = order.invoiceId != null;
  final paid = ordering.paidFor(order);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => CollectPaymentForm(
      customer: order.customer,
      submitLabel: 'Deliver & Collect',
      orderTotal: order.total,
      orderAlreadyPaid: billed && order.prepaid > paid ? order.prepaid : paid,
      allowZero: true,
      alreadyBilled: billed,
      refusableLines: billed ? [for (final i in order.items) (label: i.product.name, qty: i.qty, unit: i.unit)] : null,
      refusedValue: (refused) => ordering.refusedValue(order, refused),
      signatureRequired: ordering.signatureRequired,
      onSubmit: (input) async {
        await ordering.deliverAndCollect(order,
            amount: input.amount,
            method: input.method,
            reference: input.reference,
            signature: input.signature,
            signedName: input.signedName,
            refused: input.refused,
            collector: auth.currentUser!);
        return input.amount == 0 ? 'Delivered on credit.' : 'Delivered — ${formatNpr(input.amount)} recorded.';
      },
    ),
  );
  final sale = order.status == OrderStatus.delivered ? sales.invoiceForOrder(order.id) : null;
  if (sale == null || !navigator.mounted) return;
  showDialog(
    context: navigator.context,
    builder: (context) => AlertDialog(
      title: Text(sale.invoiceNumber == null ? 'Delivered' : 'Delivered · Tax invoice ${sale.invoiceNumber}'),
      content: Text('${order.customer.name}\nTotal: ${formatNpr(sale.total)}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context)
            ..pop()
            ..push(MaterialPageRoute(builder: (_) => InvoiceScreen(sale: sale, sales: sales, auth: auth))),
          child: const Text('View bill'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    ),
  );
}

/// The order's bill once issued (if this device has it), else the order
/// slip. [print]: two pages (customer + shop copy) to the printer.
Future<void> shareOrder(CustomerOrder order, OrderingController ordering, SalesController sales, {bool print = false}) async {
  final sale = sales.invoiceForOrder(order.id);
  final copies = print ? const ['Customer copy', 'Shop copy'] : const [''];
  if (sale != null) {
    final bytes = await billPdf(sale, sales.seller, paid: sales.paidOn(sale), returned: sales.returnedOn(sale), copies: copies);
    return print ? printPdf(bytes, billFileName(sale, null)) : sharePdf(bytes, billFileName(sale, null));
  }
  final bytes = await orderSlipPdf(order, sales.seller, paid: ordering.paidFor(order));
  return print ? printPdf(bytes, orderSlipFileName(order)) : sharePdf(bytes, orderSlipFileName(order));
}

/// Sends [order] out for delivery (issuing its bill), then offers to print
/// the two copies that travel with the goods.
Future<void> dispatchOrder(BuildContext context, CustomerOrder order, OrderingController ordering, AuthController auth, SalesController sales) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    await ordering.dispatch(order, by: auth.currentUser!);
  } on PaymentException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!navigator.mounted) return;
  showDialog(
    context: navigator.context,
    builder: (context) => AlertDialog(
      title: Text('Bill ${order.invoiceNumber} issued'),
      content: Text('${order.customer.name} · ${formatNpr(order.total)}${order.prepaid > 0 ? '\nPaid ${formatNpr(order.prepaid)} · collect ${formatNpr((order.total - order.prepaid).clamp(0, double.infinity))}' : ''}'),
      actions: [
        TextButton(onPressed: () => shareOrder(order, ordering, sales, print: true), child: const Text('Print (2 copies)')),
        TextButton(onPressed: () => shareOrder(order, ordering, sales), child: const Text('Share')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    ),
  );
}

enum _Viewer { staff, deliverer, readOnly }

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.order, required this.controller, required this.auth, required this.sales, this.staffView = false});

  final CustomerOrder order;
  final OrderingController controller;
  final AuthController auth;

  /// The order's bill, once delivered, and the shop as printed on slips.
  final SalesController sales;

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
      listenable: Listenable.merge([controller, sales]),
      builder: (context, _) {
        final viewer = _viewer;
        final invoice = sales.invoiceForOrder(order.id);
        final user = auth.currentUser!;
        final open = order.status != OrderStatus.delivered && order.status != OrderStatus.cancelled;
        final payments = controller.paymentsFor(order);

        return Scaffold(
          appBar: AppBar(
            title: Text('Order ${order.id}'),
            actions: [
              if (order.status != OrderStatus.cancelled) ...[
                IconButton(
                  tooltip: invoice != null ? 'Print bill (2 copies)' : 'Print order',
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () => shareOrder(order, controller, sales, print: true),
                ),
                IconButton(
                  tooltip: invoice != null ? 'Share bill' : 'Share order',
                  icon: const Icon(Icons.share),
                  onPressed: () => shareOrder(order, controller, sales),
                ),
              ],
            ],
          ),
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
                if (order.invoiceId != null) StatusBadge(label: 'Bill ${order.invoiceNumber}', color: Colors.teal),
                if (order.invoiceId != null && order.prepaid > 0) StatusBadge(label: 'Paid before dispatch ${formatNpr(order.prepaid)}', color: Colors.green),
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
              if (invoice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(invoice.invoiceNumber == null ? 'View bill' : 'View tax invoice ${invoice.invoiceNumber}'),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceScreen(sale: invoice, sales: sales, auth: auth))),
                  ),
                ),
              if (order.placedByStaffName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Order taken by ${order.placedByStaffName}')),
              if (order.status == OrderStatus.delivered && order.invoiceId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: order.shopCopyAt != null
                      ? Text('Signed shop copy received by ${order.shopCopyByName} · ${formatDate(order.shopCopyAt!)}')
                      : user.can(Permission.reconcileCash)
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Signed shop copy received'),
                              onPressed: () => runPaymentAction(context, () => controller.markShopCopyReceived(order, by: user)),
                            )
                          : const Text('Signed shop copy not back yet.', style: TextStyle(color: Colors.orange)),
                ),
              if (payments.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Payments', style: Theme.of(context).textTheme.titleMedium),
                for (final p in payments) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: PaymentReceipt(payment: p, businessName: controller.businessName)),
              ],
              const SizedBox(height: 24),
              if (viewer == _Viewer.staff && open) _StaffActions(order: order, controller: controller, auth: auth, sales: sales),
              if (viewer == _Viewer.deliverer && open) _DelivererActions(order: order, controller: controller, auth: auth, sales: sales),
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
  const _StaffActions({required this.order, required this.controller, required this.auth, required this.sales});

  final CustomerOrder order;
  final OrderingController controller;
  final AuthController auth;
  final SalesController sales;

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
        if (order.invoiceId == null && user.can(Permission.recordPayments)) ...[
          OutlinedButton.icon(
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Record payment before dispatch'),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => CollectPaymentForm(
                customer: order.customer,
                submitLabel: 'Record Payment',
                orderTotal: order.total,
                orderAlreadyPaid: controller.paidFor(order),
                onSubmit: (input) async {
                  controller.prepay(order, input.amount, method: input.method, reference: input.reference, collector: user);
                  return 'Payment recorded for order ${order.id}.';
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            if (nextStatus != null)
              Expanded(
                child: NextOrderButton(order: order, ordering: controller, auth: auth, sales: sales),
              ),
            if (nextStatus != null) const SizedBox(width: 12),
            if (order.invoiceId == null)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => controller.advanceOrderStatus(order, OrderStatus.cancelled, userName: user.name, userId: user.id),
                  child: const Text('Cancel Order'),
                ),
              )
            else if (user.can(Permission.cancelSales))
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _notDelivered(context, user),
                  child: const Text('Not delivered'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

extension on _StaffActions {
  Future<void> _notDelivered(BuildContext context, AppUser user) async {
    final reason = await promptText(context, title: 'Not delivered', label: 'Why? (customer away, refused all, ...)');
    if (reason == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await controller.notDelivered(order, reason, by: user);
      messenger.showSnackBar(const SnackBar(content: Text('Bill cancelled; the order is back to Ready. Destroy the printed copies.')));
    } on PaymentException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Delivery staff: take it out, then deliver & collect. Nothing else.
class _DelivererActions extends StatelessWidget {
  const _DelivererActions({required this.order, required this.controller, required this.auth, required this.sales});

  final CustomerOrder order;
  final OrderingController controller;
  final AuthController auth;
  final SalesController sales;

  @override
  Widget build(BuildContext context) {
    if (order.status == OrderStatus.outForDelivery) {
      return FilledButton.icon(
        icon: const Icon(Icons.handshake_outlined),
        onPressed: () => showDeliverSheet(context, order, controller, auth, sales),
        label: const Text('Deliver & Collect'),
      );
    }
    if (order.status == OrderStatus.ready) {
      return FilledButton.icon(
        icon: const Icon(Icons.local_shipping_outlined),
        onPressed: () => dispatchOrder(context, order, controller, auth, sales),
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
  const NextOrderButton({super.key, required this.order, required this.ordering, required this.auth, required this.sales});

  final CustomerOrder order;
  final OrderingController ordering;
  final AuthController auth;
  final SalesController sales;

  @override
  Widget build(BuildContext context) {
    final next = nextOrderStatus(order.status)!;
    return FilledButton(
      onPressed: () => switch (next) {
        OrderStatus.delivered => showDeliverSheet(context, order, ordering, auth, sales),
        OrderStatus.outForDelivery => dispatchOrder(context, order, ordering, auth, sales),
        _ => ordering.advanceOrderStatus(order, next, userName: auth.currentUser?.name ?? '', userId: auth.currentUser?.id),
      },
      child: Text(switch (next) {
        OrderStatus.delivered => 'Deliver & Collect',
        OrderStatus.outForDelivery => 'Dispatch & Bill',
        _ => 'Next: ${orderStatusLabel(next)}',
      }),
    );
  }
}
