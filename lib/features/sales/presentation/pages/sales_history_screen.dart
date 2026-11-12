import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
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
import 'package:sarathigrocery/features/sales/presentation/widgets/fix_sale_sheet.dart';
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
        // Goods refused at the door show on their bill, not as sales; an
        // edited sale shows once, its latest version, on the day it was sold.
        final replaced = {for (final s in sales.sales) if (s.corrects != null) s.corrects};
        final visibleSales = sales.sales.reversed.where((s) => !s.isDoorReturn && !replaced.contains(s.id)).toList()
          ..sort((a, b) => b.soldDate.compareTo(a.soldDate));
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
                    final returned = sales.returnedOn(sale, statements);
                    final due = paid == null ? 0.0 : sale.total - returned - paid;
                    final payState = !sale.isCredit || (paid != null && due < 0.005)
                        ? 'Paid'
                        : paid == null || paid < 0.005
                            ? 'Udharo'
                            : 'Part paid · Due ${formatNpr(due)}';
                    final completed = sale.status == SaleStatus.completed;
                    final showCollect = completed && canCollect && due > 0.005;
                    final showFix = completed && auth.can(Permission.cancelSales);
                    final status = !completed
                        ? (sales.correctionOf(sale) != null ? 'corrected' : sale.status.name, Colors.red)
                        : sale.flaggedForApproval
                            ? ('Over credit limit', Colors.orange)
                            : sale.corrects != null
                                ? ('Edited', Colors.blue)
                                : null;
                    // Actions get their own full-size row under the sale, so
                    // a near miss doesn't open the bill instead.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () => openBill(sale),
                          title: Text(sale.customer?.name ?? 'Walk-in customer'),
                          subtitle: Text('${sale.invoiceNumber ?? sale.id} · ${formatDate(sale.soldDate)} · $payState'
                              '${returned > 0.005 ? ' · ${formatNpr(returned)} returned' : ''}${sale.corrects != null ? ' · edited ${formatDate(sale.date)}' : ''}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatNpr(sale.total),
                                style: TextStyle(fontWeight: FontWeight.w600, decoration: completed ? null : TextDecoration.lineThrough),
                              ),
                              if (status != null) Text(status.$1, style: TextStyle(color: status.$2, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (showCollect || showFix)
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            children: [
                              if (showCollect)
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.payments_outlined, size: 18),
                                  label: const Text('Collect'),
                                  onPressed: () async {
                                    if (await collectOnBill(context, sale, sales, auth) && context.mounted) openBill(sale);
                                  },
                                ),
                              if (showFix)
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.edit_note, size: 18),
                                  label: const Text('Fix'),
                                  onPressed: () => showFixSaleSheet(context, sale, sales: sales, inventory: inventory, customers: customers, auth: auth),
                                ),
                            ],
                          ),
                      ],
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
}
