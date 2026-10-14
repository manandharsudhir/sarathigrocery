import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/empty_state.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/accounting/domain/statements.dart';
import 'package:sarathigrocery/features/accounting/presentation/controllers/accounting_controller.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';

/// Money: every account's cash book, expenses, and the owners' money
/// (capital, drawings, loans, dividends).
class CashScreen extends StatelessWidget {
  const CashScreen({super.key, required this.controller, required this.accounting, required this.auth, this.initialTabIndex = 0});

  final CashController controller;
  final AccountingController accounting;
  final AuthController auth;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, accounting]),
      builder: (context, _) => DefaultTabController(
        length: 3,
        initialIndex: initialTabIndex,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Money'),
            bottom: const TabBar(tabs: [Tab(text: 'Money in & out'), Tab(text: 'Expenses'), Tab(text: 'Owners & loans')]),
          ),
          body: TabBarView(
            children: [
              _LedgerTab(controller: controller),
              _ExpensesTab(controller: controller, auth: auth),
              _OwnersTab(accounting: accounting),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            icon: const Icon(Icons.add),
            label: const Text('Record'),
            onPressed: () => _showActions(context),
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    final owner = auth.currentUser?.role == UserRole.owner;
    final user = auth.currentUser?.name ?? '';
    final c = controller;
    Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            item(Icons.receipt_long, 'Expense', () => showAddExpenseSheet(context, c, userName: user)),
            item(Icons.swap_horiz, 'Transfer between accounts', () => showMoneySheet(context, c, title: 'Transfer', toAccount: true, note: true,
                onSave: (v) => c.transfer(v.account, v.to!, v.amount, v.note, userName: user))),
            item(Icons.help_outline, 'Other payment (for accountant)', () => showMoneySheet(context, c, title: 'Other payment', note: true,
                noteHint: 'What was it? e.g. shelves, fridge, rent deposit', onSave: (v) => c.otherPayment(v.amount, v.account, v.note, userName: user))),
            if (owner) ...[
              const Divider(),
              item(Icons.savings_outlined, 'Capital put in', () => showMoneySheet(context, c, title: 'Capital put in', person: 'Who put it in',
                  onSave: (v) => c.capitalIn(v.person, v.amount, v.account, userName: user))),
              item(Icons.person_remove_outlined, 'Drawings (taken for personal use)', () => showMoneySheet(context, c, title: 'Drawings', person: 'Who took it', note: true,
                  onSave: (v) => c.drawing(v.person, v.amount, v.account, v.note, userName: user))),
              item(Icons.person_add_alt_outlined, 'Drawings returned (paid back)', () => showMoneySheet(context, c, title: 'Drawings returned', person: 'Who paid it back', note: true,
                  onSave: (v) => c.drawingReturned(v.person, v.amount, v.account, v.note, userName: user))),
              item(Icons.account_balance_outlined, 'Loan received', () => showMoneySheet(context, c, title: 'Loan received', person: 'Lender (bank or person)', anyPerson: true,
                  onSave: (v) => c.loanReceived(v.person, v.amount, v.account, userName: user))),
              item(Icons.payments_outlined, 'Loan repaid', () => showMoneySheet(context, c, title: 'Loan repaid', person: 'Lender', anyPerson: true,
                  onSave: (v) => c.loanRepaid(v.person, v.amount, v.account, userName: user))),
              item(Icons.card_giftcard, 'Dividend to owners', () => showMoneySheet(context, c, title: 'Dividend',
                  onSave: (v) => c.dividend(v.amount, v.account, userName: user))),
            ],
          ]),
        ),
      ),
    );
  }
}

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({required this.controller});

  final CashController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.ledger.reversed.toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in controller.moneyAccounts)
                Chip(label: Text('${accountName(a)}: ${formatNpr(controller.balanceOf(a))}', style: a == Acc.cash ? Theme.of(context).textTheme.titleMedium : null)),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? const EmptyState(message: 'No money in or out yet.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final e = entries[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.note),
                      subtitle: Text('${accountName(e.account)} · ${_ledgerLabel(e)} · ${formatDate(e.date)}'),
                      trailing: Text(
                        '${e.isOutflow ? '-' : '+'}${formatNpr(e.amount)}',
                        style: TextStyle(color: e.isOutflow ? Colors.red : Colors.green, fontWeight: FontWeight.w600),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _ledgerLabel(CashLedgerEntry e) => switch (e.type) {
        CashEntryType.sale => 'Sale',
        CashEntryType.collection => 'Collection',
        CashEntryType.expense => 'Expense',
        CashEntryType.supplierPayment => 'Supplier payment',
        CashEntryType.refund => 'Refund',
        CashEntryType.moneyIn => 'Money in',
        CashEntryType.moneyOut => 'Money out',
      };
}

class _ExpensesTab extends StatelessWidget {
  const _ExpensesTab({required this.controller, required this.auth});

  final CashController controller;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final expenses = controller.expenses.reversed.toList();
    if (expenses.isEmpty) {
      return EmptyState(
        message: 'No expenses logged yet.',
        actionLabel: 'Add expense',
        onAction: () => showAddExpenseSheet(context, controller, userName: auth.currentUser?.name ?? ''),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: expenses.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final e = expenses[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(e.category),
          subtitle: Text('${e.note.isEmpty ? 'No note' : e.note} · ${formatDate(e.date)}'),
          trailing: Text('-${formatNpr(e.amount)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
        );
      },
    );
  }
}

/// Each owner's capital and drawings, loans outstanding, dividends paid.
class _OwnersTab extends StatelessWidget {
  const _OwnersTab({required this.accounting});

  final AccountingController accounting;

  @override
  Widget build(BuildContext context) {
    final b = accounting.statements.balances();
    final rows = [
      for (final e in b.entries)
        if (e.key.startsWith('capital') || e.key.startsWith('drawings:') || e.key.startsWith('loan:') || e.key == Acc.dividends)
          if (e.value.abs() >= 0.005) (accountName(e.key), Statements.natural(e.key, e.value).abs()),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (rows.isEmpty) return const EmptyState(message: 'No capital, drawings or loans recorded yet.');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        for (final (name, amount) in rows) ListTile(contentPadding: EdgeInsets.zero, title: Text(name), trailing: Text(formatNpr(amount))),
      ],
    );
  }
}

/// Values entered in [showMoneySheet].
typedef MoneyEntry = ({String account, String? to, double amount, String person, String note});

/// One sheet for every money action: amount, the account it moves through
/// (and [toAccount] for transfers), optionally a [person] and a [note].
/// [onSave] throws [AccountingException] to show an error.
void showMoneySheet(
  BuildContext context,
  CashController controller, {
  required String title,
  required void Function(MoneyEntry entry) onSave,
  String? person,
  bool anyPerson = false,
  bool toAccount = false,
  bool note = false,
  String noteHint = '',
}) {
  final amount = TextEditingController();
  final noteText = TextEditingController();
  final personText = TextEditingController();
  final accounts = controller.moneyAccounts;
  var account = accounts.first;
  var to = accounts.length > 1 ? accounts[1] : accounts.first;
  final owners = controller.ownerNames;
  String? chosen = owners.isEmpty ? null : owners.first;
  String? error;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (person != null)
              if (!anyPerson && owners.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: chosen,
                  decoration: InputDecoration(labelText: person),
                  items: [for (final o in owners) DropdownMenuItem(value: o, child: Text(o))],
                  onChanged: (v) => setState(() => chosen = v),
                )
              else
                TextField(controller: personText, decoration: InputDecoration(labelText: person)),
            TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
            DropdownButtonFormField<String>(
              initialValue: account,
              decoration: InputDecoration(labelText: toAccount ? 'From' : 'Account'),
              items: [for (final a in accounts) DropdownMenuItem(value: a, child: Text(accountName(a)))],
              onChanged: (v) => setState(() => account = v ?? account),
            ),
            if (toAccount)
              DropdownButtonFormField<String>(
                initialValue: to,
                decoration: const InputDecoration(labelText: 'To'),
                items: [for (final a in accounts) DropdownMenuItem(value: a, child: Text(accountName(a)))],
                onChanged: (v) => setState(() => to = v ?? to),
              ),
            if (note) TextField(controller: noteText, decoration: InputDecoration(labelText: 'Note', hintText: noteHint)),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final who = !anyPerson && owners.isNotEmpty ? (chosen ?? '') : personText.text.trim();
                  if (person != null && who.isEmpty) return setState(() => error = 'Enter a name.');
                  try {
                    onSave((account: account, to: toAccount ? to : null, amount: double.tryParse(amount.text) ?? 0, person: who, note: noteText.text.trim()));
                    Navigator.pop(context);
                  } on AccountingException catch (e) {
                    setState(() => error = e.message);
                  }
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void showAddExpenseSheet(BuildContext context, CashController controller, {String userName = ''}) {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  final categories = controller.expenseCategories;
  var category = categories.first;
  var account = controller.moneyAccounts.first;
  String? error;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Expense', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSheetState(() => category = v!),
            ),
            TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount')),
            DropdownButtonFormField<String>(
              initialValue: account,
              decoration: const InputDecoration(labelText: 'Paid from'),
              items: [for (final a in controller.moneyAccounts) DropdownMenuItem(value: a, child: Text(accountName(a)))],
              onChanged: (v) => setSheetState(() => account = v ?? account),
            ),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  try {
                    controller.addExpense(category, double.tryParse(amountController.text) ?? 0, noteController.text, createdByName: userName, account: account);
                    Navigator.pop(context);
                  } on AccountingException catch (e) {
                    setSheetState(() => error = e.message);
                  }
                },
                child: const Text('Save Expense'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
