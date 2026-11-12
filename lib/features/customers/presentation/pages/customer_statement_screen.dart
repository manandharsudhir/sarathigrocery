import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/accounting_screen.dart' show Period, standardPeriods;
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_statement.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pdf/payment_documents.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_sheet.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/invoice_screen.dart' show fileDay, pdfFileName;

/// The account both sides trust: every bill (cash and udharo) and payment in
/// the chosen period, running balance, and a check that the stored balance
/// matches the records. Tapping a bill shows its items; tapping a payment
/// opens its receipt and actions (phone confirmation, undo).
class CustomerStatementScreen extends StatefulWidget {
  const CustomerStatementScreen({super.key, required this.customer, required this.payments, required this.auth});

  final Customer customer;
  final PaymentsController payments;
  final AuthController auth;

  @override
  State<CustomerStatementScreen> createState() => _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  /// Null = all time.
  Period? _period;

  Customer get customer => widget.customer;
  PaymentsController get payments => widget.payments;

  Future<void> _pickCustom() async {
    final range = await showDateRangePicker(context: context, firstDate: DateTime(2018), lastDate: DateTime.now());
    if (range == null || !mounted) return;
    final end = range.end;
    setState(() => _period = (label: '${formatDate(range.start)} – ${formatDate(end)}', from: range.start, to: DateTime(end.year, end.month, end.day, 23, 59, 59, 999)));
  }

  Future<void> _share(CustomerStatement statement, FullStatement full) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Full statement'),
            subtitle: Text('${_period?.label ?? 'All time'}: every bill with items, and payments'),
            onTap: () => Navigator.pop(context, 'full'),
          ),
          ListTile(
            leading: const Icon(Icons.request_quote_outlined),
            title: const Text('Amount due'),
            subtitle: Text('Unpaid udharo bills with items, as of today (${formatNpr(amountDue(statement).total)})'),
            onTap: () => Navigator.pop(context, 'due'),
          ),
        ]),
      ),
    );
    if (choice == 'full') {
      await sharePdf(await fullStatementPdf(customer, full, businessName: payments.businessName, period: _period?.label ?? 'All time'), pdfFileName([customer.name.trim(), fileDay(DateTime.now()), 'Statement', _period?.label ?? 'All time']));
    } else if (choice == 'due') {
      await sharePdf(await amountDuePdf(customer, statement, businessName: payments.businessName), pdfFileName([customer.name.trim(), fileDay(DateTime.now()), 'Credit']));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: payments,
      builder: (context, _) {
        final statement = payments.statementFor(customer);
        final full = payments.fullStatementFor(customer, from: _period?.from, to: _period?.to);
        final lines = full.lines.reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: Text('Statement · ${customer.name}'),
            actions: [
              if (widget.auth.can(Permission.viewSales))
                IconButton(tooltip: 'Share as PDF', icon: const Icon(Icons.share_outlined), onPressed: () => _share(statement, full)),
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
              Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(label: const Text('All time'), selected: _period == null, onSelected: (_) => setState(() => _period = null)),
                for (final p in standardPeriods()) ChoiceChip(label: Text(p.label), selected: _period?.label == p.label, onSelected: (_) => setState(() => _period = p)),
                ChoiceChip(
                  label: Text(_period != null && !standardPeriods().any((p) => p.label == _period!.label) ? _period!.label : 'Custom…'),
                  selected: _period != null && !standardPeriods().any((p) => p.label == _period!.label),
                  onSelected: (_) => _pickCustom(),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Bought ${formatNpr(full.bought)}${full.returned > 0 ? ' · returned ${formatNpr(full.returned)}' : ''} · paid ${formatNpr(full.paid)} · closing ${formatNpr(full.closing)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (lines.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No bills or payments in this period.'))),
              for (final line in lines)
                _LineTile(
                  line: line,
                  statement: statement,
                  onTap: line.payment != null ? () => showPaymentSheet(context, line.payment!, payments, widget.auth) : () => _showItems(context, line),
                ),
              if (_period == null) _OpeningTile(statement: statement) else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: const Text('Brought forward'),
                  trailing: Text(formatNpr(full.broughtForward), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        );
      },
    );
  }
}

void _showItems(BuildContext context, HistoryLine line) {
  final sale = line.sale!;
  String item(SaleItem i) => '${i.product.name}: ${formatQty(i.qty)} ${i.unit} × ${formatNpr(i.unitPrice)}';
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        Text(line.title, style: Theme.of(context).textTheme.titleMedium),
        Text(formatDate(sale.soldDate)),
        for (final i in sale.items) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(item(i)), trailing: Text(formatNpr(i.lineTotal))),
        for (final r in line.returns) ...[
          Text('Returned ${formatDate(r.date)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final i in r.items) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(item(i)), trailing: Text(formatNpr(i.lineTotal))),
        ],
        const Divider(),
        ListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Total'), trailing: Text(formatNpr(sale.total - line.returnedAmount))),
      ]),
    ),
  );
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.statement, this.onTap});

  final HistoryLine line;
  final CustomerStatement statement;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sale = line.sale;
    final payment = line.payment;
    Widget? badge;
    if (sale != null && !sale.isCredit) {
      badge = const StatusBadge(label: 'Cash · paid', color: Colors.green);
    } else if (sale != null && !sale.isDoorReturn) {
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
        sale != null && !sale.isCredit ? formatNpr(sale.total - line.returnedAmount) : line.change == 0 ? '—' : '${line.change > 0 ? '+' : '−'}${formatNpr(line.change.abs())}',
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
