import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/pages/product_form_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.controller, required this.auth});

  final InventoryController controller;
  final AuthController auth;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canManage = widget.auth.can(Permission.manageProducts);
    final products = controller.products.where((p) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) || p.category.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q);
    }).toList();

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
                product: products[index],
                controller: controller,
                auth: widget.auth,
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
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(controller: controller, auth: widget.auth))),
            )
          : null,
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.controller, required this.auth, required this.canManage});

  final Product product;
  final InventoryController controller;
  final AuthController auth;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final canAdjust = auth.can(Permission.adjustInventory);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        onTap: canManage
            ? () => _showActionsSheet(context, canAdjust)
            : (canAdjust ? () => _showAdjustSheet(context) : null),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${product.category} · ${formatNpr(product.unitPrice)} / ${product.unitLabel}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${product.availableStock} in stock'),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!product.isActive) const StatusBadge(label: 'Inactive', color: Colors.grey),
                if (product.isLowStock) const StatusBadge(label: 'Low Stock', color: Colors.red),
                if (product.isLowStock && product.isNearExpiry) const SizedBox(width: 4),
                if (product.isNearExpiry) const StatusBadge(label: 'Near Expiry', color: Colors.amber),
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
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Product'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(controller: controller, auth: auth, product: product)));
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
          ],
        ),
      ),
    );
  }

  void _showAdjustSheet(BuildContext context) {
    final qtyController = TextEditingController();
    final noteController = TextEditingController();
    var type = AdjustmentType.damaged;

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
                  ButtonSegment(value: AdjustmentType.returned, label: Text('Returned')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setSheetState(() => type = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
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
                    final qty = int.tryParse(qtyController.text) ?? 0;
                    if (qty <= 0 || noteController.text.trim().isEmpty) return;
                    controller.adjustStock(product, type, qty, noteController.text, userName: auth.currentUser?.name ?? '');
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
