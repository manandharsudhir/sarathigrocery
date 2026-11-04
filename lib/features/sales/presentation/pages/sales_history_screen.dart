import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/core/widgets/empty_state.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/invoice_screen.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/new_sale_screen.dart';
import 'package:sarathigrocery/features/sales/presentation/widgets/collect_on_bill.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_statement.dart';

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
        final visibleSales = sales.sales.reversed.toList();
        final canSell = auth.can(Permission.createSales);
        final canCollect = auth.can(Permission.recordPayments);
        final statements = <String, CustomerStatement>{};
        void openBill(Sale sale) => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceScreen(sale: sale, sales: sales, auth: auth)));
        void newSale() => Navigator.push(context, MaterialPageRoute(builder: (_) => NewSaleScreen(sales: sales, inventory: inventory, customers: customers, auth: auth)));

        return Scaffold(
          appBar: AppBar(title: const Text('Sales')),
          body: visibleSales.isEmpty
              ? EmptyState(message: 'No sales recorded yet.', actionLabel: 'New sale', onAction: canSell ? newSale : null)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: visibleSales.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final sale = visibleSales[index];
                    final paid = sales.paidOn(sale, statements);
                    final due = paid == null ? 0.0 : sale.total - paid;
                    final payState = !sale.isCredit || (paid != null && due < 0.005)
                        ? 'Paid'
                        : paid == null || paid < 0.005
                            ? 'Udharo'
                            : 'Part paid · Due ${formatNpr(due)}';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => openBill(sale),
                      title: Text(sale.customer?.name ?? 'Walk-in customer'),
                      subtitle: Text('${sale.invoiceNumber ?? sale.id} · ${formatDate(sale.date)} · $payState'),
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
                          else ...[
                            if (sale.flaggedForApproval) const Text('Over credit limit', style: TextStyle(color: Colors.orange, fontSize: 12)),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              if (canCollect && due > 0.005)
                                TextButton(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 0)),
                                  onPressed: () async {
                                    if (await collectOnBill(context, sale, sales, auth) && context.mounted) openBill(sale);
                                  },
                                  child: const Text('Collect', style: TextStyle(fontSize: 12)),
                                ),
                              if (auth.can(Permission.cancelSales))
                                TextButton(
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 0)),
                                  onPressed: () => _showCancelReturnSheet(context, sale),
                                  child: const Text('Cancel / Return', style: TextStyle(fontSize: 12)),
                                ),
                            ]),
                          ],
                        ],
                      ),
                    );
                  },
                ),
          floatingActionButton: !canSell
              ? null
              : FloatingActionButton.extended(heroTag: null, 
                  icon: const Icon(Icons.add),
                  label: const Text('New Sale'),
                  onPressed: newSale,
                ),
        );
      },
    );
  }

  /// Cancel/return; a tax invoice gets a numbered credit note (online).
  Future<void> _reverse(BuildContext sheetContext, Sale sale, SaleStatus status, String reason) async {
    if (reason.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(sheetContext);
    final navigator = Navigator.of(sheetContext);
    try {
      await sales.reverse(sale, status, reason.trim(), userName: auth.currentUser?.name ?? '');
      navigator.pop();
      final note = sales.creditNoteFor(sale);
      if (note != null) messenger.showSnackBar(SnackBar(content: Text('Credit note ${note.number} issued.')));
    } on AccountingException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
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
                    onPressed: () => _reverse(sheetContext, sale, SaleStatus.cancelled, reasonController.text),
                    child: const Text('Cancel Sale'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _reverse(sheetContext, sale, SaleStatus.returned, reasonController.text),
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
