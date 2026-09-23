import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

class SupplierDetailScreen extends StatelessWidget {
  const SupplierDetailScreen({super.key, required this.supplier, required this.controller, required this.purchasing, required this.cash, required this.auth});

  final Supplier supplier;
  final SuppliersController controller;
  final PurchasingController purchasing;
  final CashController cash;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, purchasing, cash]),
      builder: (context, _) {
        final purchases = purchasing.purchases.where((p) => p.supplier.id == supplier.id).toList().reversed.toList();
        final payments = cash.ledger.where((e) => e.type == CashEntryType.supplierPayment && e.reference == supplier.id).toList().reversed.toList();

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
              const SizedBox(height: 24),
              Text('Purchase History', style: Theme.of(context).textTheme.titleMedium),
              ...purchases.map((p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Purchase ${p.id}'),
                    subtitle: Text(formatDate(p.date)),
                    trailing: Text(formatNpr(p.total)),
                  )),
              if (purchases.isEmpty) const Text('No purchases yet.'),
              const SizedBox(height: 24),
              Text('Payment History', style: Theme.of(context).textTheme.titleMedium),
              ...payments.map((e) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.note),
                    subtitle: Text(formatDate(e.date)),
                    trailing: Text(formatNpr(e.amount)),
                  )),
              if (payments.isEmpty) const Text('No payments yet.'),
            ],
          ),
        );
      },
    );
  }

  void _showPaySheet(BuildContext context) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0) return;
                  controller.recordPayment(supplier, amount, noteController.text, userName: auth.currentUser?.name ?? '');
                  Navigator.pop(context);
                },
                child: const Text('Record Payment'),
              ),
            ),
          ],
        ),
      ),
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
