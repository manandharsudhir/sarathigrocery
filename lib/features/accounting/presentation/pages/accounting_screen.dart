import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/empty_state.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/journal_entry.dart';
import 'package:sarathigrocery/features/accounting/domain/statements.dart';
import 'package:sarathigrocery/features/accounting/presentation/controllers/accounting_controller.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/accounting_forms.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

/// A reporting period: start (inclusive) to end (inclusive, end of day).
typedef Period = ({String label, DateTime from, DateTime to});

DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

Period todayPeriod() {
  final now = DateTime.now();
  return (label: 'Today', from: DateTime(now.year, now.month, now.day), to: _endOfDay(now));
}

/// Current BS month, current fiscal year, or today if outside the calendar.
List<Period> standardPeriods() {
  final now = DateTime.now();
  final periods = [todayPeriod()];
  try {
    final bs = BsDate.fromAd(now);
    final monthStart = BsDate(bs.year, bs.month, 1).toAd();
    periods.add((label: 'This month (${BsDate.monthNames[bs.month - 1]})', from: monthStart, to: _endOfDay(now)));
    final (fyStart, _) = BsDate.fiscalYearRange(bs.fiscalYear);
    periods.add((label: 'This fiscal year (${BsDate.fiscalYearLabel(bs.fiscalYear)})', from: fyStart, to: _endOfDay(now)));
  } on RangeError {
    periods.add((label: 'This month', from: DateTime(now.year, now.month), to: _endOfDay(now)));
  }
  return periods;
}

/// Accounting in two views: Simple (plain language) and the accountant's
/// statements (P&L, Balance Sheet, trial balance, journal).
class AccountingScreen extends StatefulWidget {
  const AccountingScreen({super.key, required this.controller, required this.auth, required this.suppliers, this.onExport});

  final AccountingController controller;
  final AuthController auth;
  final SuppliersController suppliers;

  /// Shares the accountant's CSV + PDF for a period.
  final Future<void> Function(Period period)? onExport;

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  late Period _period = standardPeriods().last;

  AccountingController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.postMissingCosts();
  }

  Future<void> _pickPeriod() async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final p in standardPeriods()) ListTile(title: Text(p.label), onTap: () => Navigator.pop(context, p)),
          ListTile(title: const Text('Custom dates…'), onTap: () => Navigator.pop(context, 'custom')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'custom') {
      final range = await showDateRangePicker(context: context, firstDate: DateTime(2018), lastDate: DateTime.now());
      if (range == null) return;
      setState(() => _period = (label: '${formatDate(range.start)} – ${formatDate(range.end)}', from: range.start, to: _endOfDay(range.end)));
    } else {
      setState(() => _period = choice as Period);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.auth.currentUser?.role == UserRole.owner;
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Accounts'),
            actions: [
              if (widget.onExport != null)
                IconButton(tooltip: 'Export for accountant', icon: const Icon(Icons.ios_share), onPressed: () => widget.onExport!(_period)),
              if (owner)
                PopupMenuButton<String>(
                  onSelected: (v) => switch (v) {
                    'setup' => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountsSetupScreen(controller: _c, auth: widget.auth))),
                    'opening' => Navigator.push(context, MaterialPageRoute(builder: (_) => OpeningBalancesScreen(controller: _c, auth: widget.auth, suppliers: widget.suppliers))),
                    'manual' => Navigator.push(context, MaterialPageRoute(builder: (_) => ManualEntryScreen(controller: _c, auth: widget.auth))),
                    'close' => showCloseYearDialog(context, _c, widget.auth),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'setup', child: Text('Owners & accounts setup')),
                    if (!_c.openingLocked) const PopupMenuItem(value: 'opening', child: Text('Opening balances')),
                    const PopupMenuItem(value: 'manual', child: Text('Adjustment entry')),
                    const PopupMenuItem(value: 'close', child: Text('Close fiscal year')),
                  ],
                ),
            ],
            bottom: const TabBar(isScrollable: true, tabs: [
              Tab(text: 'Simple'),
              Tab(text: 'Profit & Loss'),
              Tab(text: 'Balance Sheet'),
              Tab(text: 'Trial Balance'),
              Tab(text: 'Journal'),
            ]),
          ),
          body: Column(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.date_range),
                title: Text(_period.label),
                subtitle: Text('${formatDate(_period.from)} – ${formatDate(_period.to)} · ${formatBs(_period.from)} – ${formatBs(_period.to)}'),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: _pickPeriod,
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(children: [
                  _SimpleView(controller: _c, period: _period),
                  _ProfitLossView(pl: _c.statements.profitAndLoss(_period.from, _period.to)),
                  _BalanceSheetView(bs: _c.statements.balanceSheet(_period.to)),
                  _TrialBalanceView(controller: _c, period: _period),
                  _JournalView(entries: [for (final e in _c.journal) if (!e.date.isBefore(_period.from) && !e.date.isAfter(_period.to)) e]),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _row(String label, double amount, {bool bold = false, Color? color, String? hint}) => ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
      subtitle: hint == null ? null : Text(hint),
      trailing: Text(formatNpr(amount), style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
    );

Widget _heading(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );

/// Plain language: where the owners' money is now, and what it earned.
class _SimpleView extends StatelessWidget {
  const _SimpleView({required this.controller, required this.period});

  final AccountingController controller;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final bs = controller.statements.balanceSheet(period.to);
    final pl = controller.statements.profitAndLoss(period.from, period.to);
    final put = bs.equity.entries.where((e) => e.key.startsWith('capital')).fold(0.0, (s, e) => s + e.value);
    final taken = -bs.equity.entries.where((e) => e.key.startsWith('drawings:') || e.key == Acc.dividends).fold(0.0, (s, e) => s + e.value);
    final worth = bs.totalAssets - bs.totalLiabilities;
    final money = bs.assets.entries.where((e) => Acc.isMoney(e.key)).fold(0.0, (s, e) => s + e.value);
    final checks = controller.checks;
    final ok = controller.booksBalanced;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: ok ? Colors.green.shade50 : Colors.orange.shade50,
          child: ListTile(
            leading: Icon(ok ? Icons.verified : Icons.warning_amber, color: ok ? Colors.green : Colors.orange),
            title: Text(ok ? 'Books balanced' : 'Books and records differ'),
            subtitle: Text(ok
                ? 'Every account agrees with the cash book, customers, suppliers and stock.'
                : [for (final c in checks) if ((c.books - c.records).abs() >= 1) '${c.label}: books ${formatNpr(c.books)}, records ${formatNpr(c.records)}'].join('\n')),
          ),
        ),
        if (controller.salesWithoutCost.isNotEmpty)
          Card(
            color: Colors.orange.shade50,
            child: ListTile(
              leading: const Icon(Icons.price_change_outlined, color: Colors.orange),
              title: Text('${controller.salesWithoutCost.length} sale${controller.salesWithoutCost.length == 1 ? '' : 's'} with no cost yet'),
              subtitle: Text('Sold before the product was ever purchased, so for now their profit counts the full price: '
                  '${{for (final s in controller.salesWithoutCost) for (final i in s.items) if (i.cost == 0) i.product.name}.join(', ')}. '
                  'Their cost is booked from the first purchase of each product.'),
            ),
          ),
        _heading(context, 'Owners\' money'),
        _row('Put in by owners', put, hint: 'Capital, including opening balances'),
        _row('Taken out by owners', taken, hint: 'Drawings and dividends'),
        _heading(context, 'What the business has now'),
        _row('Money (cash, bank, wallet)', money),
        for (final e in bs.assets.entries)
          if (!Acc.isMoney(e.key)) _row(accountName(e.key), e.value),
        _row('Everything it has', bs.totalAssets, bold: true),
        if (bs.liabilities.isNotEmpty) ...[
          _heading(context, 'What it owes'),
          for (final e in bs.liabilities.entries) _row(accountName(e.key), e.value),
          _row('Everything it owes', bs.totalLiabilities, bold: true),
        ],
        _heading(context, 'Result'),
        _row('Business is worth', worth, bold: true, hint: 'What it has minus what it owes'),
        _row('Earned since the start', worth - (put - taken), color: worth - (put - taken) >= 0 ? Colors.green : Colors.red, hint: 'Worth minus what owners put in net'),
        _row('Profit in ${period.label.toLowerCase()}', pl.profit, bold: true, color: pl.profit >= 0 ? Colors.green : Colors.red),
        _row('  Sales', pl.income[Acc.sales] ?? 0),
        _row('  Cost of the goods sold', pl.costs[Acc.cogs] ?? 0),
        _row('  Expenses and losses', pl.totalCosts - (pl.costs[Acc.cogs] ?? 0)),
      ],
    );
  }
}

class _ProfitLossView extends StatelessWidget {
  const _ProfitLossView({required this.pl});

  final ProfitAndLoss pl;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _heading(context, 'Income'),
        for (final e in pl.income.entries) _row(accountName(e.key), e.value),
        _row('Total income', pl.totalIncome, bold: true),
        _heading(context, 'Costs and expenses'),
        for (final e in pl.costs.entries) _row(accountName(e.key), e.value),
        _row('Total costs', pl.totalCosts, bold: true),
        const Divider(),
        _row(pl.profit >= 0 ? 'Net profit' : 'Net loss', pl.profit, bold: true, color: pl.profit >= 0 ? Colors.green : Colors.red),
      ],
    );
  }
}

class _BalanceSheetView extends StatelessWidget {
  const _BalanceSheetView({required this.bs});

  final BalanceSheet bs;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _heading(context, AccountType.asset.label),
        for (final e in bs.assets.entries) _row(accountName(e.key), e.value),
        _row('Total assets', bs.totalAssets, bold: true),
        _heading(context, AccountType.liability.label),
        for (final e in bs.liabilities.entries) _row(accountName(e.key), e.value),
        _row('Total liabilities', bs.totalLiabilities, bold: true),
        _heading(context, AccountType.equity.label),
        for (final e in bs.equity.entries) _row(accountName(e.key), e.value),
        _row('Profit not yet closed', bs.profitNotClosed),
        _row('Total owners\' money', bs.totalEquity, bold: true),
        const Divider(),
        _row('Liabilities + owners\' money', bs.totalLiabilities + bs.totalEquity, bold: true,
            color: bs.balanced ? Colors.green : Colors.red, hint: bs.balanced ? 'Equals total assets ✓' : 'Does not equal total assets'),
      ],
    );
  }
}

/// Every account's debit/credit total for the period; tap for its ledger.
class _TrialBalanceView extends StatelessWidget {
  const _TrialBalanceView({required this.controller, required this.period});

  final AccountingController controller;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final b = controller.statements.balances(to: period.to);
    final rows = [for (final a in controller.accounts) if ((b[a] ?? 0).abs() >= 0.005) a];
    final debit = rows.fold(0.0, (s, a) => s + (b[a]! > 0 ? b[a]! : 0));
    final credit = rows.fold(0.0, (s, a) => s + (b[a]! < 0 ? -b[a]! : 0));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Balances as of ${formatDate(period.to)}', style: Theme.of(context).textTheme.bodySmall),
        for (final a in rows)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(accountName(a)),
            subtitle: Text(accountType(a).label),
            trailing: Text('${b[a]! > 0 ? 'Dr' : 'Cr'} ${formatNpr(b[a]!.abs())}'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountLedgerScreen(controller: controller, account: a))),
          ),
        const Divider(),
        _row('Total debits', debit, bold: true),
        _row('Total credits', credit, bold: true, hint: (debit - credit).abs() < 0.01 ? 'Equal ✓' : 'Not equal'),
      ],
    );
  }
}

class _JournalView extends StatelessWidget {
  const _JournalView({required this.entries});

  final List<JournalEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const EmptyState(message: 'No entries in this period.');
    final list = entries.reversed.toList();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, i) => JournalEntryTile(entry: list[i]),
    );
  }
}

class JournalEntryTile extends StatelessWidget {
  const JournalEntryTile({super.key, required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.memo, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('${formatDate(entry.date)} · ${formatBs(entry.date)}${entry.byName.isEmpty ? '' : ' · ${entry.byName}'}', style: small),
        for (final l in entry.lines.entries)
          Padding(
            padding: EdgeInsets.only(left: l.value > 0 ? 0 : 24, top: 2),
            child: Row(children: [
              Expanded(child: Text('${l.value > 0 ? 'Dr' : 'Cr'} ${accountName(l.key)}')),
              Text(formatNpr(l.value.abs())),
            ]),
          ),
      ],
    );
  }
}

/// Every entry touching [account], with the running balance.
class AccountLedgerScreen extends StatelessWidget {
  const AccountLedgerScreen({super.key, required this.controller, required this.account});

  final AccountingController controller;
  final String account;

  @override
  Widget build(BuildContext context) {
    var running = 0.0;
    final rows = [
      for (final e in controller.journal)
        if (e.lines.containsKey(account)) (e, running += e.lines[account]!),
    ].reversed.toList();
    return Scaffold(
      appBar: AppBar(title: Text(accountName(account))),
      body: rows.isEmpty
          ? const EmptyState(message: 'Nothing posted to this account.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, i) {
                final (e, balance) = rows[i];
                final v = e.lines[account]!;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.memo),
                  subtitle: Text('${formatDate(e.date)} · balance ${formatNpr(Statements.natural(account, balance))}'),
                  trailing: Text('${v > 0 ? 'Dr' : 'Cr'} ${formatNpr(v.abs())}'),
                );
              },
            ),
    );
  }
}
