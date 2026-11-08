import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/core/widgets/correction_dialogs.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/pages/purchase_detail_screen.dart';
import 'package:sarathigrocery/features/purchasing/presentation/widgets/return_to_supplier_sheet.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

class SupplierDetailScreen extends StatelessWidget {
  const SupplierDetailScreen({super.key, required this.supplier, required this.controller, required this.purchasing, required this.cash, required this.inventory, required this.auth});

  final Supplier supplier;
  final SuppliersController controller;
  final PurchasingController purchasing;
  final CashController cash;
  final InventoryController inventory;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, purchasing, cash]),
      builder: (context, _) {
        final purchases = purchasing.allPurchases.where((p) => p.supplier.id == supplier.id).toList().reversed.toList();
        final payments = controller.paymentsTo(supplier);
        final owner = auth.currentUser?.role == UserRole.owner;
        final canReverse = auth.can(Permission.reconcileCash);

        return Scaffold(
          appBar: AppBar(title: Text(supplier.businessName)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoRow(label: 'Contact', value: supplier.name),
              _InfoRow(label: 'Phone', value: supplier.phone),
              _InfoRow(label: 'Address', value: supplier.address),
              _InfoRow(label: 'Products Supplied', value: supplier.productsSupplied.isEmpty ? '—' : supplier.productsSupplied),
              _InfoRow(label: 'Amount Payable', value: formatNpr(supplier.amountPayable)),
              const SizedBox(height: 16),
              if (auth.can(Permission.manageSuppliers) && supplier.amountPayable > 0)
                FilledButton.icon(
                  onPressed: () => _showPaySheet(context),
                  icon: const Icon(Icons.payments),
                  label: const Text('Record Payment'),
                ),
              if (auth.can(Permission.createPurchases))
                OutlinedButton.icon(
                  onPressed: () => showReturnToSupplierSheet(context,
                      purchasing: purchasing, suppliers: controller.suppliers, products: inventory.products, supplier: supplier, userName: auth.currentUser?.name ?? ''),
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Return to supplier'),
                ),
              const SizedBox(height: 24),
              Text('Purchase History', style: Theme.of(context).textTheme.titleMedium),
              ...purchases.map((p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Purchase ${p.id}'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => PurchaseDetailScreen(purchase: p, purchasing: purchasing, suppliers: controller, inventory: inventory, auth: auth))),
                    subtitle: Text('${formatDate(p.date)}${p.isReversed ? ' · reversed' : ''}'),
                    trailing: Text(formatNpr(p.total), style: TextStyle(decoration: p.isReversed ? TextDecoration.lineThrough : null)),
                  )),
              if (purchases.isEmpty) const Text('No purchases yet.'),
              const SizedBox(height: 24),
              Text('Payment History', style: Theme.of(context).textTheme.titleMedium),
              ...payments.map((e) {
                final reversal = controller.reversalOf(e);
                return Opacity(
                  opacity: reversal == null ? 1 : 0.5,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.note),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${formatDate(e.date)} · ${accountName(e.account)}'),
                      if (reversal != null) ReversedNote('Reversed ${formatDate(reversal.date)}: ${reversal.note.split(' – ').last}'),
                    ]),
                    trailing: Text(formatNpr(e.amount), style: TextStyle(decoration: reversal == null ? null : TextDecoration.lineThrough)),
                    onTap: canReverse && reversal == null ? () => _reversePayment(context, e, owner) : null,
                  ),
                );
              }),
              if (payments.isEmpty) const Text('No payments yet.'),
            ],
          ),
        );
      },
    );
  }

  Future<void> _reversePayment(BuildContext context, CashLedgerEntry payment, bool owner) async {
    final messenger = ScaffoldMessenger.of(context);
    final problem = controller.reverseProblem(payment, owner: owner);
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    final reason = await askReason(context,
        title: 'Reverse this payment?',
        message: '${formatNpr(payment.amount)} to ${supplier.businessName} on ${formatDate(payment.date)}.\n'
            'The money goes back to ${accountName(payment.account)}, ${supplier.businessName} is owed it again, and the books are reversed.');
    if (reason == null) return;
    try {
      controller.reversePayment(supplier, payment, reason, userName: auth.currentUser?.name ?? '', owner: owner);
    } on AccountingException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _showPaySheet(BuildContext context) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var account = 'cash';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pay ${supplier.name}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (NPR)')),
            const SizedBox(height: 8),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
            DropdownButtonFormField<String>(
              initialValue: account,
              decoration: const InputDecoration(labelText: 'Paid from'),
              items: [for (final a in cash.moneyAccounts) DropdownMenuItem(value: a, child: Text(accountName(a)))],
              onChanged: (v) => setSheetState(() => account = v ?? account),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0) return;
                  final same = controller.similarPaymentToday(supplier, amount);
                  if (same != null &&
                      !await confirmNotDuplicate(context, '${formatNpr(amount)} to ${supplier.businessName} was already recorded today at ${formatTime(same.date)}.')) {
                    return;
                  }
                  if (!context.mounted) return;
                  controller.recordPayment(supplier, amount, noteController.text, userName: auth.currentUser?.name ?? '', account: account);
                  Navigator.pop(context);
                },
                child: const Text('Record Payment'),
              ),
            ),
          ],
        ),
      )),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
