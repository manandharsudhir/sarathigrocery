import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/accounting/presentation/controllers/accounting_controller.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

Widget _errorText(BuildContext context, String? error) =>
    error == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 8), child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)));

/// Owners and their shares, named banks/wallets, extra expense categories.
class AccountsSetupScreen extends StatefulWidget {
  const AccountsSetupScreen({super.key, required this.controller, required this.auth, this.addOwner});

  final AccountingController controller;
  final AuthController auth;

  /// A new co-owner to give a share to (adds their row).
  final String? addOwner;

  @override
  State<AccountsSetupScreen> createState() => _AccountsSetupScreenState();
}

class _AccountsSetupScreenState extends State<AccountsSetupScreen> {
  late final _owners = [
    for (final o in widget.controller.settings.owners) (TextEditingController(text: o.name), TextEditingController(text: formatQty(o.percent))),
    if (widget.addOwner != null && !widget.controller.settings.owners.any((o) => o.name == widget.addOwner)) (TextEditingController(text: widget.addOwner), TextEditingController()),
  ];
  late final _accounts = [...widget.controller.settings.moneyAccounts];
  late final _categories = [...widget.controller.settings.expenseCategories];
  String? _error;

  Future<String?> _ask(String title, String label) {
    final text = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: text, autofocus: true, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, text.text.trim()), child: const Text('Add')),
        ],
      ),
    );
  }

  Future<void> _addAccount(String kind) async {
    final name = await _ask('New ${kind == 'bank' ? 'bank account' : 'wallet'}', kind == 'bank' ? 'Bank name, e.g. NIC Asia' : 'Wallet, e.g. eSewa');
    if (name == null || name.isEmpty || name.contains(':')) return;
    setState(() => _accounts.add('$kind:$name'));
  }

  void _save() {
    try {
      widget.controller.saveSetup(
        owners: [for (final (name, pct) in _owners) if (name.text.trim().isNotEmpty) OwnerShare(name.text.trim(), _num(pct))],
        moneyAccounts: _accounts,
        expenseCategories: _categories,
        by: widget.auth.currentUser!,
      );
      Navigator.pop(context);
    } on AccountingException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Owners & accounts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Owners', style: Theme.of(context).textTheme.titleMedium),
          const Text('Who owns the business and their share (%). Opening capital and dividends are split by these shares.', style: TextStyle(color: Colors.grey)),
          for (final (i, (name, pct)) in _owners.indexed)
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: pct, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Share %'))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _owners.removeAt(i))),
            ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add owner'),
              onPressed: () => setState(() => _owners.add((TextEditingController(), TextEditingController(text: _owners.isEmpty ? '100' : '')))),
            ),
          ),
          const Divider(height: 32),
          Text('Banks and wallets', style: Theme.of(context).textTheme.titleMedium),
          const Text('Cash, Bank and Wallet always exist. Add named ones to track each separately.', style: TextStyle(color: Colors.grey)),
          for (final a in _accounts)
            ListTile(contentPadding: EdgeInsets.zero, title: Text(accountName(a)), subtitle: Text(Acc.moneyKind(a)), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _accounts.remove(a)))),
          Wrap(spacing: 8, children: [
            TextButton.icon(icon: const Icon(Icons.add), label: const Text('Bank account'), onPressed: () => _addAccount('bank')),
            TextButton.icon(icon: const Icon(Icons.add), label: const Text('Wallet'), onPressed: () => _addAccount('wallet')),
          ]),
          const Divider(height: 32),
          Text('Expense categories', style: Theme.of(context).textTheme.titleMedium),
          Text('Built in: ${kExpenseCategories.join(', ')}', style: const TextStyle(color: Colors.grey)),
          for (final c in _categories)
            ListTile(contentPadding: EdgeInsets.zero, title: Text(c), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _categories.remove(c)))),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Category'),
              onPressed: () async {
                final name = await _ask('New expense category', 'Name');
                if (name != null && name.isNotEmpty && !_categories.contains(name) && !kExpenseCategories.contains(name)) setState(() => _categories.add(name));
              },
            ),
          ),
          _errorText(context, _error),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

/// One-time opening balances for a shop that already had money, stock or
/// debts. Stock is entered with each product, old udharo with each customer.
class OpeningBalancesScreen extends StatefulWidget {
  const OpeningBalancesScreen({super.key, required this.controller, required this.auth, required this.suppliers});

  final AccountingController controller;
  final AuthController auth;
  final SuppliersController suppliers;

  @override
  State<OpeningBalancesScreen> createState() => _OpeningBalancesScreenState();
}

class _OpeningBalancesScreenState extends State<OpeningBalancesScreen> {
  DateTime _date = DateTime.now();
  late final _money = {for (final a in [Acc.cash, Acc.bank, Acc.wallet, ...widget.controller.settings.moneyAccounts]) a: TextEditingController()};
  final _deposits = TextEditingController();
  final List<(TextEditingController, TextEditingController)> _loans = [];
  late final _suppliers = {for (final s in widget.suppliers.suppliers) s: TextEditingController()};
  String? _error;

  void _save() {
    try {
      widget.controller.postOpening(
        owns: {for (final m in _money.entries) m.key: _num(m.value), Acc.deposits: _num(_deposits)},
        loans: {for (final (name, amount) in _loans) if (name.text.trim().isNotEmpty) name.text.trim(): _num(amount)},
        suppliersOwed: <Supplier, double>{for (final s in _suppliers.entries) s.key: _num(s.value)},
        date: _date,
        by: widget.auth.currentUser!,
      );
      Navigator.pop(context);
    } on AccountingException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    TextField amount(TextEditingController c, String label) =>
        TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: label));
    return Scaffold(
      appBar: AppBar(title: const Text('Opening balances')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'What the business had and owed on its first day in the app. The difference becomes the owners\' opening capital, split by their shares. '
            'Enter stock with each product (opening stock and cost) and old udharo with each customer. Locked once the shop starts trading.',
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('As of'),
            subtitle: Text('${formatDate(_date)} · ${formatBs(_date)}'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2018), lastDate: DateTime.now());
              if (d != null) setState(() => _date = d);
            },
          ),
          Text('Money', style: Theme.of(context).textTheme.titleMedium),
          for (final m in _money.entries) amount(m.value, accountName(m.key)),
          amount(_deposits, 'Deposits (rent deposit, etc.)'),
          const SizedBox(height: 16),
          Text('Loans', style: Theme.of(context).textTheme.titleMedium),
          for (final (name, value) in _loans)
            Row(children: [
              Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Lender'))),
              const SizedBox(width: 8),
              Expanded(child: amount(value, 'Still owed')),
            ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(icon: const Icon(Icons.add), label: const Text('Loan'), onPressed: () => setState(() => _loans.add((TextEditingController(), TextEditingController())))),
          ),
          if (_suppliers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Owed to suppliers', style: Theme.of(context).textTheme.titleMedium),
            for (final s in _suppliers.entries) amount(s.value, s.key.businessName),
          ],
          _errorText(context, _error),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Post opening balances')),
        ],
      ),
    );
  }
}

/// Owner-only adjustment: balanced debits and credits with a reason (for
/// the accountant's corrections and year-end adjustments).
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({super.key, required this.controller, required this.auth});

  final AccountingController controller;
  final AuthController auth;

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final _reason = TextEditingController();
  DateTime _date = DateTime.now();
  final List<({String? account, TextEditingController debit, TextEditingController credit})> _lines = [
    (account: null, debit: TextEditingController(), credit: TextEditingController()),
    (account: null, debit: TextEditingController(), credit: TextEditingController()),
  ];
  String? _error;

  List<String> get _choices => [for (final a in widget.controller.accounts) if (!Acc.isMoney(a)) a];

  void _save() {
    final lines = <String, double>{};
    for (final l in _lines) {
      if (l.account == null) continue;
      lines[l.account!] = (lines[l.account!] ?? 0) + _num(l.debit) - _num(l.credit);
    }
    try {
      widget.controller.manualEntry(lines, _reason.text, _date, by: widget.auth.currentUser!);
      Navigator.pop(context);
    } on AccountingException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final debits = _lines.fold(0.0, (s, l) => s + _num(l.debit));
    final credits = _lines.fold(0.0, (s, l) => s + _num(l.credit));
    return Scaffold(
      appBar: AppBar(title: const Text('Adjustment entry')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('For your accountant: corrections, depreciation, profit shares, reclassifying "To classify" payments. Money accounts change only through real payments.'),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Reason (required)')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text('${formatDate(_date)} · ${formatBs(_date)}'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2018), lastDate: DateTime.now());
              if (d != null) setState(() => _date = d);
            },
          ),
          for (final (i, l) in _lines.indexed)
            Row(children: [
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  initialValue: l.account,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [for (final a in _choices) DropdownMenuItem(value: a, child: Text(accountName(a), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _lines[i] = (account: v, debit: l.debit, credit: l.credit)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: TextField(controller: l.debit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Debit'), onChanged: (_) => setState(() {}))),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: TextField(controller: l.credit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Credit'), onChanged: (_) => setState(() {}))),
            ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Line'),
              onPressed: () => setState(() => _lines.add((account: null, debit: TextEditingController(), credit: TextEditingController()))),
            ),
          ),
          Text('Debits ${formatNpr(debits)} · Credits ${formatNpr(credits)}', style: TextStyle(color: (debits - credits).abs() < 0.005 ? Colors.green : Colors.orange)),
          _errorText(context, _error),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Post adjustment')),
        ],
      ),
    );
  }
}

/// Closes the last ended fiscal year (Shrawan – Asar): profit moves to
/// retained earnings and nothing can be posted into it any more.
Future<void> showCloseYearDialog(BuildContext context, AccountingController controller, AuthController auth) {
  final now = DateTime.now();
  final int fy;
  try {
    fy = BsDate.fromAd(now).fiscalYear - 1;
  } on RangeError {
    return Future.value();
  }
  final (from, to) = BsDate.fiscalYearRange(fy);
  final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
  final closed = controller.settings.closedThrough;
  final profit = controller.statements.profitAndLoss(closed != null && closed.isAfter(from) ? closed : from, end).profit;
  String? error;
  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Close fiscal year ${BsDate.fiscalYearLabel(fy)}?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (closed != null && !closed.isBefore(end))
            const Text('This year is already closed.')
          else ...[
            Text('${formatDate(from)} – ${formatDate(to)}'),
            Text('${profit >= 0 ? 'Profit' : 'Loss'} ${formatNpr(profit)} moves to retained earnings. Nothing can be posted on or before ${formatDate(to)} afterwards.'),
            const SizedBox(height: 8),
            const Text('Post your accountant\'s year-end adjustments first.'),
          ],
          _errorText(context, error),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          if (closed == null || closed.isBefore(end))
            FilledButton(
              onPressed: () {
                try {
                  controller.closeYear(end, by: auth.currentUser!);
                  Navigator.pop(context);
                } on AccountingException catch (e) {
                  setState(() => error = e.message);
                }
              },
              child: const Text('Close year'),
            ),
        ],
      ),
    ),
  );
}
