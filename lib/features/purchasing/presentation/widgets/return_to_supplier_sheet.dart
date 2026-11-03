import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';

/// Goods going back to a supplier: stock down, what we owe them down.
/// Opened from a supplier (pick the product) or a product (pick the
/// supplier, starting on the one it was last bought from).
void showReturnToSupplierSheet(
  BuildContext context, {
  required PurchasingController purchasing,
  required List<Supplier> suppliers,
  required List<Product> products,
  Supplier? supplier,
  Product? product,
  required String userName,
}) {
  if (supplier == null && suppliers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a supplier first.')));
    return;
  }
  final returnable = products.where((p) => p.availableStock > 0).toList()..sort((a, b) => a.name.compareTo(b.name));
  if (product == null && returnable.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No products in stock to return.')));
    return;
  }
  var p = product ?? returnable.first;
  var s = supplier ?? lastSupplierOf(p, purchasing) ?? suppliers.first;
  var unit = p.primary;
  final qty = TextEditingController();
  final cost = TextEditingController();
  final reason = TextEditingController();
  void resetCost() => cost.text = p.purchasePrice > 0 ? (p.purchasePrice * unit.size).toStringAsFixed(2) : '';
  resetCost();
  String? error;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(builder: (context, setSheet) {
      final q = double.tryParse(qty.text) ?? 0;
      final c = double.tryParse(cost.text) ?? 0;
      final value = q * c;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Return to supplier', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (supplier == null)
                DropdownButtonFormField<Supplier>(
                  initialValue: s,
                  decoration: const InputDecoration(labelText: 'Supplier'),
                  items: [for (final x in suppliers) DropdownMenuItem(value: x, child: Text(x.businessName))],
                  onChanged: (x) => setSheet(() => s = x ?? s),
                )
              else
                Text('Supplier: ${s.businessName}'),
              const SizedBox(height: 8),
              if (product == null)
                DropdownButtonFormField<Product>(
                  initialValue: p,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: [for (final x in returnable) DropdownMenuItem(value: x, child: Text(x.name, overflow: TextOverflow.ellipsis))],
                  onChanged: (x) => setSheet(() {
                    p = x ?? p;
                    unit = p.primary;
                    resetCost();
                  }),
                )
              else
                Text('Product: ${p.name}'),
              const SizedBox(height: 4),
              Text('In stock (free): ${p.describeQty(p.availableStock)}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setSheet(() {}),
                    decoration: InputDecoration(
                      labelText: p.packs.isEmpty ? 'Quantity (${p.unitLabel})' : 'Quantity',
                      helperText: unit.size == 1 || q <= 0 ? null : '= ${formatQty(q * unit.size)} ${p.unitLabel}',
                    ),
                  ),
                ),
                if (p.packs.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(p.id),
                      initialValue: unit.label,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: [
                        for (final u in p.sellUnits)
                          DropdownMenuItem(value: u.label, child: Text(u.size == 1 ? u.label : '${u.label} (${formatQty(u.size)} ${p.unitLabel})')),
                      ],
                      onChanged: (label) => setSheet(() {
                        unit = p.sellUnit(label ?? unit.label);
                        resetCost();
                      }),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setSheet(() {}),
                decoration: InputDecoration(
                  labelText: 'Cost per ${unit.label}',
                  helperText: 'Starts at average cost. Use the bill\'s price to undo a wrong purchase line.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (required)')),
              if (value > 0) ...[
                const SizedBox(height: 12),
                Text('Return value: ${formatNpr(value)}'),
                if (value > s.amountPayable + 0.005)
                  Text(
                    'You owe ${s.businessName} ${formatNpr(s.amountPayable)}. After this they will owe you ${formatNpr(value - s.amountPayable)}.',
                    style: const TextStyle(color: Colors.orange),
                  ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final problem = returnProblem(p, q * unit.size, c / unit.size, reason.text);
                  if (problem != null) return setSheet(() => error = problem);
                  purchasing.recordPurchaseReturn(s, p, q * unit.size, reason.text.trim(), userName: userName, unitCost: c / unit.size);
                  Navigator.pop(context);
                },
                child: const Text('Record Return'),
              ),
            ],
          ),
        ),
      );
    }),
  );
}

/// The supplier [p] was most recently bought from, if any.
Supplier? lastSupplierOf(Product p, PurchasingController purchasing) {
  for (final purchase in purchasing.purchases.reversed) {
    if (purchase.items.any((i) => i.product.id == p.id)) return purchase.supplier;
  }
  return null;
}

/// Why a return of [baseQty] at [costPerUnit] can't be recorded, or null.
String? returnProblem(Product p, double baseQty, double costPerUnit, String reason) {
  if (baseQty <= 0) return 'Enter a quantity.';
  if (baseQty > p.availableStock + 1e-9) return 'Only ${p.describeQty(p.availableStock)} free in stock.';
  if (costPerUnit <= 0) return 'Enter the cost.';
  // ponytail: a return at a cost other than average re-prices what's left;
  // returning everything leaves nothing to absorb the difference, so it
  // must go back at average cost.
  final left = p.stockQty - baseQty;
  final avg = p.purchasePrice;
  if (left <= 1e-9 && (costPerUnit - avg).abs() > 0.005) return 'Returning all stock: use the average cost, ${formatNpr(avg)} per ${p.unitLabel}.';
  if (baseQty * costPerUnit > p.stockQty * avg + 0.005) return 'That is worth more than all ${p.name} in stock at cost (${formatNpr(p.stockQty * avg)}). Check the cost.';
  if (reason.trim().isEmpty) return 'Enter a reason.';
  return null;
}
