import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/invoice_screen.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/new_sale_screen.dart';

class SalesHistoryScreen extends StatelessWidget {
  const SalesHistoryScreen({super.key, required this.sales, required this.inventory, required this.customers, required this.auth});

  final SalesController sales;
  final InventoryController inventory;
  final CustomersController customers;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([sales, auth]),
      builder: (context, _) {
        final isCustomer = auth.currentUser?.role == UserRole.customer;
        final linkedCustomerId = auth.currentUser?.linkedCustomerId;
        final visibleSales = (isCustomer
                ? sales.sales.where((s) => s.customer?.id == linkedCustomerId)
                : sales.sales)
            .toList()
            .reversed
            .toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Sales')),
          body: visibleSales.isEmpty
              ? const Center(child: Text('No sales recorded yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: visibleSales.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final sale = visibleSales[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceScreen(sale: sale))),
                      title: Text(sale.customer?.name ?? 'Walk-in customer'),
                      subtitle: Text('${sale.id} · ${formatDate(sale.date)} · ${sale.isCredit ? 'Udharo' : 'Cash'}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatNpr(sale.total),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: sale.status != SaleStatus.completed ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (sale.status != SaleStatus.completed)
                            Text(sale.status.name, style: const TextStyle(color: Colors.red, fontSize: 12))
                          else if (sale.flaggedForApproval)
                            const Text('Needs approval', style: TextStyle(color: Colors.orange, fontSize: 12))
                          else if (!isCustomer && auth.can(Permission.cancelSales))
                            TextButton(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                              onPressed: () => _showCancelReturnSheet(context, sale),
                              child: const Text('Cancel / Return', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
          floatingActionButton: isCustomer || !auth.can(Permission.createSales)
              ? null
              : FloatingActionButton.extended(heroTag: null, 
                  icon: const Icon(Icons.add),
                  label: const Text('New Sale'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewSaleScreen(sales: sales, inventory: inventory, customers: customers, auth: auth))),
                ),
        );
      },
    );
  }

  void _showCancelReturnSheet(BuildContext context, Sale sale) {
    final reasonController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cancel or return sale ${sale.id}', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Reason (required)')),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (reasonController.text.trim().isEmpty) return;
                      sales.cancelSale(sale, reasonController.text.trim(), userName: auth.currentUser?.name ?? '');
                      Navigator.pop(sheetContext);
                    },
                    child: const Text('Cancel Sale'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (reasonController.text.trim().isEmpty) return;
                      sales.returnSale(sale, reasonController.text.trim(), userName: auth.currentUser?.name ?? '');
                      Navigator.pop(sheetContext);
                    },
                    child: const Text('Return Goods'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
