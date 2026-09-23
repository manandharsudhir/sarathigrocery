import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';

/// Owner/accountant view of customer payments: cash to receive from
/// collectors, problems (disputes, unconfirmed, shortfalls), and history.
class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key, required this.payments, required this.auth, this.initialTab = 0});

  final PaymentsController payments;
  final AuthController auth;
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: payments,
      builder: (context, _) {
        final pending = payments.pendingHandover;
        final byCollector = <String, List<CustomerPayment>>{};
        for (final p in pending) {
          (byCollector[p.collectedByName] ??= []).add(p);
        }
        final issues = [...payments.disputed, ...payments.shortfalls, ...payments.unconfirmed.where((p) => DateTime.now().difference(p.date).inHours >= 24)];
        return DefaultTabController(
          length: 3,
          initialIndex: initialTab,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Customer Payments'),
              bottom: TabBar(tabs: [
                Tab(text: 'To receive (${pending.length})'),
                Tab(text: 'Issues (${issues.length})'),
                const Tab(text: 'All'),
              ]),
            ),
            body: TabBarView(children: [
              byCollector.isEmpty
                  ? const Center(child: Text('Nothing waiting — all collections are in the till.'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final entry in byCollector.entries) ...[
                          Text('${entry.key} · ${formatNpr(entry.value.fold(0.0, (s, p) => s + p.amount))}', style: Theme.of(context).textTheme.titleMedium),
                          for (final p in entry.value) _PaymentTile(payment: p, payments: payments, auth: auth, showReceive: true),
                          const Divider(),
                        ],
                      ],
                    ),
              issues.isEmpty
                  ? const Center(child: Text('No disputes, shortfalls or long-unconfirmed payments.'))
                  : ListView(padding: const EdgeInsets.all(16), children: [for (final p in issues.toSet()) _PaymentTile(payment: p, payments: payments, auth: auth)]),
              ListView(padding: const EdgeInsets.all(16), children: [for (final p in payments.payments.reversed) _PaymentTile(payment: p, payments: payments, auth: auth)]),
            ]),
          ),
        );
      },
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment, required this.payments, required this.auth, this.showReceive = false});

  final CustomerPayment payment;
  final PaymentsController payments;
  final AuthController auth;
  final bool showReceive;

  Future<void> _receive(BuildContext context) async {
    final isCash = payment.method == PaymentMethod.cash;
    final counted = await promptText(
      context,
      title: isCash ? 'Count the cash' : 'Verify ${paymentMethodLabel(payment.method)} ${payment.reference}',
      label: isCash ? 'Amount counted (NPR)' : 'Amount received per statement (NPR)',
      initial: payment.amount.toStringAsFixed(0),
      keyboardType: TextInputType.number,
    );
    if (counted == null || !context.mounted) return;
    final value = double.tryParse(counted.trim());
    if (value == null) return;
    runPaymentAction(
      context,
      () => payments.settle(payment, value, receiver: auth.currentUser!),
      success: value < payment.amount ? 'Recorded — shortfall of ${formatNpr(payment.amount - value)} flagged.' : 'Received.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${payment.customer.name} · ${formatNpr(payment.amount)}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${paymentMethodLabel(payment.method)}${payment.reference.isEmpty ? '' : ' ${payment.reference}'} · ${payment.collectedByName} · ${formatDate(payment.date)}'
              '${payment.orderId == null ? '' : ' · order ${payment.orderId}'}'),
          if (payment.isDisputed) Text('"${payment.disputeNote}"', style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 4),
          PaymentStatusRow(payment: payment),
        ],
      ),
      trailing: showReceive && auth.can(Permission.reconcileCash)
          ? FilledButton.tonal(onPressed: () => _receive(context), child: const Text('Receive'))
          : null,
      onTap: () => showModalBottomSheet(context: context, builder: (_) => Padding(padding: const EdgeInsets.all(16), child: PaymentReceipt(payment: payment))),
    );
  }
}
