import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';

/// Read-only view of one purchase. Purchases are never edited after they're
/// recorded, so this doesn't listen for changes.
class PurchaseDetailScreen extends StatelessWidget {
  const PurchaseDetailScreen({super.key, required this.purchase, this.openSupplier});

  final Purchase purchase;

  /// Makes the supplier name a link. Null when opened from the supplier.
  final VoidCallback? openSupplier;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: Text('Purchase ${p.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
