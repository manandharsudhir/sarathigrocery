import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_statement.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';

/// The account both sides trust: every bill and payment, running balance,
/// and a check that the stored balance matches the records. Customers
/// confirm or dispute payments here; the owner can reverse unsettled ones.
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
        final isCustomer = auth.currentUser?.role == UserRole.customer;
        return Scaffold(
          appBar: AppBar(title: Text(isCustomer ? 'My Statement' : 'Statement · ${customer.name}')),
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
                    title: const Text("Balance doesn't match the records"),
                    subtitle: Text('Bills and payments add up to ${formatNpr(statement.expectedBalance)}, '
                        'but the balance is ${formatNpr(statement.actualBalance)} (${formatNpr(statement.unexplainedDifference)} unexplained). '
                        '${isCustomer ? 'The owner has been shown this too.' : 'Check the audit log for balance changes outside sales and payments.'}'),
                  ),
                ),
              if (!statement.verifiable)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Opening balance was not recorded for this customer, so it is inferred from the current balance.', style: TextStyle(color: Colors.grey)),
                ),
              const SizedBox(height: 8),
              if (lines.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No bills or payments yet.'))),
              for (final line in lines) _LineTile(line: line, statement: statement, onTap: line.payment == null ? null : () => _openPayment(context, line.payment!, isCustomer)),
              _OpeningTile(statement: statement),
            ],
          ),
        );
      },
    );
  }

  void _openPayment(BuildContext context, CustomerPayment payment, bool isCustomer) {
    final user = auth.currentUser!;
    final canRespond = isCustomer && !payment.isReversed;
    final canReverse = user.role == UserRole.owner && !payment.isReversed;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Payment receipt', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            PaymentReceipt(payment: payment),
            const SizedBox(height: 16),
            if (canRespond && !payment.isCustomerConfirmed && !payment.isDisputed)
              FilledButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('This is correct'),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  runPaymentAction(context, () => payments.confirm(payment, customerUser: user), success: 'Thanks — payment confirmed.');
                },
              ),
            if (canRespond && !payment.isDisputed)
              TextButton.icon(
                icon: const Icon(Icons.report_outlined),
                label: const Text('Report a problem'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final note = await promptText(context, title: 'What is wrong?', label: 'e.g. I paid 7,000, not 5,000');
                  if (note != null && context.mounted) {
                    runPaymentAction(context, () => payments.dispute(payment, note, customerUser: user), success: 'Reported — the owner has been notified.');
                  }
                },
              ),
            if (canReverse)
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('Reverse payment'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final reason = await promptText(
                    context,
                    title: payment.isSettled ? 'Reverse and refund ${formatNpr(payment.settledAmount!)}?' : 'Reverse this payment?',
                    label: 'Reason (the customer will see it)',
                  );
                  if (reason != null && context.mounted) {
                    runPaymentAction(context, () => payments.reverse(payment, reason, owner: user), success: 'Payment reversed.');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
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
      title: const Text('Opening balance'),
      subtitle: open > 0 ? Text(left <= 0.01 ? 'Paid off' : '${formatNpr(left)} still due') : null,
      trailing: Text(formatNpr(open), style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}
