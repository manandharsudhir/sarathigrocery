import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';

/// What I collected and still hold — to hand over at the shop.
class MyCollectionsScreen extends StatelessWidget {
  const MyCollectionsScreen({super.key, required this.payments, required this.auth});

  final PaymentsController payments;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: payments,
      builder: (context, _) {
        final me = auth.currentUser!.id;
        final mine = payments.payments.where((p) => p.collectedById == me).toList().reversed.toList();
        final holding = mine.where((p) => p.isPendingHandover).toList();
        final cash = holding.where((p) => p.method == PaymentMethod.cash).fold(0.0, (s, p) => s + p.amount);
        final shortfall = mine.fold(0.0, (s, p) => s + p.shortfall);
        return Scaffold(
          appBar: AppBar(title: const Text('My Collections')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  title: const Text('Cash to hand over'),
                  subtitle: Text('${holding.length} payment${holding.length == 1 ? '' : 's'} not yet received at the shop'),
                  trailing: Text(formatNpr(cash), style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
              if (shortfall > 0)
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(leading: const Icon(Icons.warning_amber), title: Text('Shortfall recorded: ${formatNpr(shortfall)}')),
                ),
              const SizedBox(height: 8),
              if (mine.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No collections yet.'))),
              for (final p in mine)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${p.customer.name} · ${formatNpr(p.amount)}'),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${paymentMethodLabel(p.method)} · ${formatDate(p.date)}${p.orderId == null ? '' : ' · order ${p.orderId}'}'),
                    const SizedBox(height: 4),
                    PaymentStatusRow(payment: p),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}
