import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';

const _expenseCategories = ['Rent', 'Transport', 'Utilities', 'Packaging', 'Tea/Misc'];

class CashScreen extends StatelessWidget {
  const CashScreen({super.key, required this.controller, this.initialTabIndex = 0});

  final CashController controller;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cash & Finance'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Daily Ledger'),
            Tab(text: 'Expenses'),
            Tab(text: 'Partner Capital'),
          ]),
        ),
        body: TabBarView(
          children: [
            _DailyLedgerTab(controller: controller),
            _ExpensesTab(controller: controller),
            _PartnerTab(controller: controller),
          ],
        ),
        floatingActionButton: Builder(
          builder: (context) {
            final tabController = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: tabController,
              builder: (context, _) => _buildFab(context, tabController.index, controller),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFab(BuildContext context, int tabIndex, CashController controller) {
    if (tabIndex == 1) {
      return FloatingActionButton.extended(heroTag: null, 
        onPressed: () => showAddExpenseSheet(context, controller),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      );
    }
    if (tabIndex == 2) {
      return FloatingActionButton.extended(heroTag: null, 
        onPressed: () => _showAddPartnerEntry(context, controller),
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
      );
    }
    return FloatingActionButton.extended(heroTag: null, 
      onPressed: () => _showAddDeposit(context, controller),
      icon: const Icon(Icons.account_balance),
      label: const Text('Bank Deposit'),
    );
  }
}

class _DailyLedgerTab extends StatelessWidget {
  const _DailyLedgerTab({required this.controller});

  final CashController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.ledger.reversed.toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Cash in Hand: ${formatNpr(controller.cashInHand)}', style: Theme.of(context).textTheme.titleLarge),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final e = entries[index];
              final isOutflow = e.type == CashEntryType.expense || e.type == CashEntryType.deposit || e.type == CashEntryType.supplierPayment;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.note),
                subtitle: Text('${_ledgerLabel(e.type)} · ${formatDate(e.date)}'),
                trailing: Text(
                  '${isOutflow ? '-' : '+'}${formatNpr(e.amount)}',
                  style: TextStyle(
                    color: isOutflow ? Colors.red : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _ledgerLabel(CashEntryType type) {
    switch (type) {
      case CashEntryType.opening:
        return 'Opening';
      case CashEntryType.sale:
        return 'Money In · Sale';
      case CashEntryType.collection:
        return 'Money In · Collection';
      case CashEntryType.expense:
        return 'Money Out · Expense';
      case CashEntryType.deposit:
        return 'Money Out · Bank Deposit';
      case CashEntryType.supplierPayment:
        return 'Money Out · Supplier Payment';
    }
  }
}

class _ExpensesTab extends StatelessWidget {
  const _ExpensesTab({required this.controller});

  final CashController controller;

  @override
  Widget build(BuildContext context) {
    final expenses = controller.expenses.reversed.toList();
    if (expenses.isEmpty) {
      return const Center(child: Text('No expenses logged yet.'));
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

class _PartnerTab extends StatelessWidget {
  const _PartnerTab({required this.controller});

  final CashController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.partnerLedger.reversed.toList();
    final byPartner = <String, double>{};
    for (final e in controller.partnerLedger) {
      final sign = e.type == 'repayment' ? -1 : 1;
      byPartner[e.partnerName] = (byPartner[e.partnerName] ?? 0) + sign * e.amount;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: byPartner.entries
                .map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${e.key}: ${formatNpr(e.value)} balance', style: Theme.of(context).textTheme.titleMedium),
                    ))
                .toList(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final e = entries[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${e.partnerName} · ${e.type}'),
                subtitle: Text('${e.note.isEmpty ? '' : '${e.note} · '}${formatDate(e.date)}'),
                trailing: Text(formatNpr(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
              );
            },
          ),
        ),
      ],
    );
  }
}

void showAddExpenseSheet(BuildContext context, CashController controller) {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  var category = _expenseCategories.first;

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
              items: _expenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSheetState(() => category = v!),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount (NPR)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Attach receipt photo'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0) return;
                  controller.addExpense(category, amount, noteController.text);
                  Navigator.pop(context);
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

void _showAddDeposit(BuildContext context, CashController controller) {
  final amountController = TextEditingController();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bank Deposit', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: amountController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (NPR)'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0) return;
                controller.addBankDeposit(amount, '');
                Navigator.pop(context);
              },
              child: const Text('Save Deposit'),
            ),
          ),
        ],
      ),
    ),
  );
}

void _showAddPartnerEntry(BuildContext context, CashController controller) {
  final amountController = TextEditingController();
  final noteController = TextEditingController();
  final nameController = TextEditingController();
  var type = 'loan';

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
            Text('Partner Ledger Entry', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Partner name'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'loan', child: Text('Loan / Capital')),
                DropdownMenuItem(value: 'repayment', child: Text('Repayment')),
                DropdownMenuItem(value: 'profit_share', child: Text('Profit Distribution')),
              ],
              onChanged: (v) => setSheetState(() => type = v!),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount (NPR)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0 || nameController.text.isEmpty) return;
                  controller.addPartnerEntry(nameController.text, amount, type, noteController.text);
                  Navigator.pop(context);
                },
                child: const Text('Save Entry'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
