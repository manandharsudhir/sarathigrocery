import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/empty_state.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/pages/new_purchase_screen.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key, required this.purchasing, required this.suppliers, required this.inventory, required this.auth});

  final PurchasingController purchasing;
  final SuppliersController suppliers;
  final InventoryController inventory;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: purchasing,
      builder: (context, _) {
        final purchases = purchasing.purchases.reversed.toList();
        final canBuy = auth.can(Permission.createPurchases) && suppliers.suppliers.isNotEmpty;
        void newPurchase() => Navigator.push(context, MaterialPageRoute(builder: (_) => NewPurchaseScreen(purchasing: purchasing, suppliers: suppliers, inventory: inventory, auth: auth)));
        return Scaffold(
          appBar: AppBar(title: const Text('Purchases')),
          body: purchases.isEmpty
              ? EmptyState(message: 'No purchases recorded yet.', actionLabel: 'New purchase', onAction: canBuy ? newPurchase : null)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: purchases.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final p = purchases[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.supplier.businessName),
                      subtitle: Text('${p.id} · ${formatDate(p.date)} · ${p.items.length} items'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatNpr(p.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (p.remainingAmount > 0) Text('Due ${formatNpr(p.remainingAmount)}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                      ),
                    );
                  },
                ),
          floatingActionButton: canBuy
              ? FloatingActionButton.extended(heroTag: null, 
                  icon: const Icon(Icons.add),
                  label: const Text('New Purchase'),
                  onPressed: newPurchase,
                )
              : null,
        );
      },
    );
  }
}
