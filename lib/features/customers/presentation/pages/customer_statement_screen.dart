import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_statement.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pdf/payment_documents.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_sheet.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';

/// The account both sides trust: every bill and payment, running balance,
/// and a check that the stored balance matches the records. Tapping a
/// payment opens its receipt and actions (phone confirmation, undo).
class CustomerStatementScreen extends StatelessWidget {
  const CustomerStatementScreen({super.key, required this.customer, required this.payments, required this.auth});

  final Customer customer;
  final PaymentsController payments;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: payments,
      builder: (context, _) {
        final statement = payments.statementFor(customer);
        final lines = statement.lines.reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: Text('Statement · ${customer.name}'),
            actions: [
              IconButton(
                tooltip: 'Share as PDF',
                icon: const Icon(Icons.share_outlined),
                onPressed: () async => sharePdf(await statementPdf(customer, statement, businessName: payments.businessName), 'statement-${customer.id}.pdf'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  title: const Text('Current balance'),
                  subtitle: Text('Credit limit ${formatNpr(customer.creditLimit)}'),
                  trailing: Text(formatNpr(customer.outstandingBalance), style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
              if (!statement.balanced)
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.report_problem_outlined),
                    title: const Text("Balance doesn't add up, check records"),
                    subtitle: Text('Bills and payments add up to ${formatNpr(statement.expectedBalance)}, '
                        'but the balance is ${formatNpr(statement.actualBalance)} (${formatNpr(statement.unexplainedDifference)} difference). '
                        'Check the audit log for balance changes outside sales and payments.'),
                  ),
                ),
              if (!statement.verifiable)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Old udharo (before app) was not recorded for this customer, so it is worked out from the current balance.', style: TextStyle(color: Colors.grey)),
                ),
              const SizedBox(height: 8),
              if (lines.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No bills or payments yet.'))),
              for (final line in lines) _LineTile(line: line, statement: statement, onTap: line.payment == null ? null : () => _openPayment(context, line.payment!)),
              _OpeningTile(statement: statement),
            ],
          ),
        );
      },
    );
  }

  void _openPayment(BuildContext context, CustomerPayment payment) => showPaymentSheet(context, payment, payments, auth);
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.statement, this.onTap});

  final StatementLine line;
  final CustomerStatement statement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sale = line.sale;
    final payment = line.payment;
    Widget? badge;
    if (sale != null && line.change > 0) {
      final due = statement.dueFor(sale);
      badge = StatusBadge(
        label: due <= 0.01 ? 'Paid' : (statement.paidFor(sale) > 0 ? 'Part paid · ${formatNpr(due)} due' : 'Unpaid'),
        color: due <= 0.01 ? Colors.green : Colors.orange,
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(payment != null ? Icons.payments_outlined : Icons.receipt_long_outlined, color: payment != null ? Colors.green : null),
      title: Text(line.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${formatDate(line.date)} · balance ${formatNpr(line.balance)}'),
          if (payment != null) Padding(padding: const EdgeInsets.only(top: 4), child: PaymentStatusRow(payment: payment, showSettlement: false)),
          if (badge != null) Padding(padding: const EdgeInsets.only(top: 4), child: badge),
        ],
      ),
      trailing: Text(
        line.change == 0 ? '—' : '${line.change > 0 ? '+' : '−'}${formatNpr(line.change.abs())}',
        style: TextStyle(fontWeight: FontWeight.w600, color: line.change < 0 ? Colors.green : null),
      ),
    );
  }
}

class _OpeningTile extends StatelessWidget {
  const _OpeningTile({required this.statement});

  final CustomerStatement statement;

  @override
  Widget build(BuildContext context) {
    final open = statement.opening;
    final left = open - statement.openingPaid;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history),
      title: const Text('Old udharo (before app)'),
      subtitle: open > 0 ? Text(left <= 0.01 ? 'Paid off' : '${formatNpr(left)} still due') : null,
      trailing: Text(formatNpr(open), style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
