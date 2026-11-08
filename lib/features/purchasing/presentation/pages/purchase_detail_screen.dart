import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/core/widgets/correction_dialogs.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/pages/new_purchase_screen.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

/// One purchase. Purchases are never edited: one entered by mistake is
/// reversed, or corrected (reversed and entered again), when [purchasing]
/// and friends are given and the user may.
class PurchaseDetailScreen extends StatelessWidget {
  const PurchaseDetailScreen({super.key, required this.purchase, this.openSupplier, this.purchasing, this.suppliers, this.inventory, this.auth});

  final Purchase purchase;
  final PurchasingController? purchasing;
  final SuppliersController? suppliers;
  final InventoryController? inventory;
  final AuthController? auth;

  /// Makes the supplier name a link. Null when opened from the supplier.
  final VoidCallback? openSupplier;

  @override
  Widget build(BuildContext context) => purchasing == null ? _build(context) : ListenableBuilder(listenable: purchasing!, builder: (context, _) => _build(context));

  Future<void> _reverse(BuildContext context, bool owner) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await askReason(context,
        title: 'Reverse purchase ${purchase.id}?',
        message: 'Use this for a purchase entered twice or by mistake. Its stock comes back out, ${purchase.supplier.businessName} is owed less'
            '${purchase.paidAmount > 0 ? ', ${formatNpr(purchase.paidAmount)} goes back to ${accountName(purchase.account)}' : ''}, and the books are reversed.');
    if (reason == null) return;
    try {
      purchasing!.reversePurchase(purchase, reason, userName: auth!.currentUser?.name ?? '', owner: owner);
      messenger.showSnackBar(const SnackBar(content: Text('Purchase reversed.')));
    } on AccountingException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _build(BuildContext context) {
    final p = purchase;
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final owner = auth?.currentUser?.role == UserRole.owner;
    final canFix = purchasing != null && !p.isReversed && (auth?.can(Permission.reconcileCash) ?? false) && (owner || isToday(p.date));
    final replacement = purchasing?.correctionOf(p);
    return Scaffold(
      appBar: AppBar(title: Text('Purchase ${p.id}')),
      bottomNavigationBar: !canFix
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => _reverse(context, owner), child: const Text('Reverse'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pushReplacement(
                          context, MaterialPageRoute(builder: (_) => NewPurchaseScreen(purchasing: purchasing!, suppliers: suppliers!, inventory: inventory!, auth: auth!, corrects: p))),
                      child: const Text('Correct'),
                    ),
                  ),
                ]),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (p.isReversed)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                title: Text(replacement == null ? 'Reversed' : 'Corrected: replaced by ${replacement.id}'),
                subtitle: Text('${formatDate(p.reversedAt!)} by ${p.reversedByName}: ${p.reversalReason}'),
              ),
            ),
          if (p.corrects != null) Text('Corrects purchase ${p.corrects}', style: muted),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p.supplier.businessName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Supplier'),
            trailing: openSupplier == null ? null : const Icon(Icons.chevron_right),
            onTap: openSupplier,
          ),
          _Row(label: 'Date', value: formatDate(p.date)),
          if (p.supplierBillNo.isNotEmpty) _Row(label: 'Supplier bill no.', value: p.supplierBillNo),
          if (p.supplierBillDate != null) _Row(label: 'Supplier bill date', value: formatDate(p.supplierBillDate!)),
          const SizedBox(height: 24),
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          ...p.items.map((i) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(i.product.name),
                subtitle: Text('${formatQty(i.qty)} ${i.unit}'
                    '${i.size != 1 ? ' (${formatQty(i.baseQty)} ${i.product.unitLabel})' : ''}'
                    ' × ${formatNpr(i.unitCost)}/${i.unit}'),
                trailing: Text(formatNpr(i.lineTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
          const Divider(height: 32),
          if (p.vatAmount > 0) ...[
            _Row(label: 'Goods', value: formatNpr(p.goodsTotal)),
            _Row(label: 'VAT', value: formatNpr(p.vatAmount)),
          ],
          _Row(label: 'Total', value: formatNpr(p.total)),
          _Row(label: p.paidAmount > 0 ? 'Paid now (${accountName(p.account)})' : 'Paid now', value: formatNpr(p.paidAmount)),
          _Row(label: 'Unpaid at purchase', value: formatNpr(p.remainingAmount)),
          if (p.remainingAmount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Later supplier payments show on the supplier, not here.', style: muted),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

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
