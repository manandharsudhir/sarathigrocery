import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/pages/product_form_screen.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/presentation/controllers/settings_controller.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.controller, required this.auth, required this.settings, this.returnToSupplier});

  final InventoryController controller;

  /// Set (by AppShell) when this user may return goods to suppliers.
  final void Function(BuildContext context, Product product)? returnToSupplier;
  final AuthController auth;
  final SettingsController settings;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canManage = widget.auth.can(Permission.manageProducts);
    final products = controller.products.where((p) => p.matches(_query)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search products, category, SKU',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: products.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _ProductTile(
                returnToSupplier: widget.returnToSupplier,
                product: products[index],
                controller: controller,
                auth: widget.auth,
                settings: widget.settings,
                canManage: canManage,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(heroTag: null, 
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(controller: controller, auth: widget.auth, settings: widget.settings))),
            )
          : null,
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.controller, required this.auth, required this.settings, required this.canManage, this.returnToSupplier});

  final void Function(BuildContext context, Product product)? returnToSupplier;
  final Product product;
  final InventoryController controller;
  final AuthController auth;
  final SettingsController settings;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final canAdjust = auth.can(Permission.adjustInventory);
    final nearExpiry = settings.has(Feature.expiry) && product.isNearExpiry;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        onTap: canManage || returnToSupplier != null
            ? () => _showActionsSheet(context, canAdjust)
            : (canAdjust ? () => _showAdjustSheet(context) : null),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${settings.has(Feature.categories) ? '${product.category} · ' : ''}${[for (final u in product.sellUnits) u.price > 0 ? '${formatNpr(u.price)} / ${u.label}' : '${u.label}: ${product.isUnpriced(u.label) ? 'no price yet' : 'at cost'}'].join(' · ')}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${product.describeQty(product.availableStock)} in stock'),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!product.isActive) const StatusBadge(label: 'Inactive', color: Colors.grey),
                if (product.isLowStock) const StatusBadge(label: 'Low Stock', color: Colors.red),
                if (product.isLowStock && nearExpiry) const SizedBox(width: 4),
                if (nearExpiry) const StatusBadge(label: 'Near Expiry', color: Colors.amber),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showActionsSheet(BuildContext context, bool canAdjust) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canManage)
              ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Product'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(controller: controller, auth: auth, settings: settings, product: product)));
              },
            ),
            if (canAdjust)
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Adjust Stock'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showAdjustSheet(context);
                },
              ),
            if (returnToSupplier != null)
              ListTile(
                leading: const Icon(Icons.assignment_return_outlined),
                title: const Text('Return to supplier'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  returnToSupplier!(context, product);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showAdjustSheet(BuildContext context) {
    final qtyController = TextEditingController();
    final noteController = TextEditingController();
    var type = AdjustmentType.damaged;
    var unit = product.primary;

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
              Text('Adjust stock: ${product.name}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<AdjustmentType>(
                segments: const [
                  ButtonSegment(value: AdjustmentType.damaged, label: Text('Damaged')),
                  ButtonSegment(value: AdjustmentType.expired, label: Text('Expired')),
                  ButtonSegment(value: AdjustmentType.returned, label: Text('Customer return')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setSheetState(() => type = s.first),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      labelText: product.packs.isEmpty ? 'Quantity (${product.unitLabel})' : 'Quantity',
                      helperText: unit.size == 1 || (double.tryParse(qtyController.text) ?? 0) <= 0
                          ? null
                          : '= ${formatQty((double.tryParse(qtyController.text) ?? 0) * unit.size)} ${product.unitLabel}',
                    ),
                  ),
                ),
                if (product.packs.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: unit.label,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: [
                        for (final u in product.sellUnits)
                          DropdownMenuItem(value: u.label, child: Text(u.size == 1 ? u.label : '${u.label} (${formatQty(u.size)} ${product.unitLabel})')),
                      ],
                      onChanged: (label) => setSheetState(() => unit = product.sellUnit(label ?? unit.label)),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note (required)'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final qty = double.tryParse(qtyController.text) ?? 0;
                    if (qty <= 0 || noteController.text.trim().isEmpty) return;
                    controller.adjustStock(product, type, qty * unit.size, noteController.text, userName: auth.currentUser?.name ?? '');
                    Navigator.pop(context);
                  },
                  child: const Text('Log Adjustment'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
