import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/cash/presentation/pages/cash_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_detail_screen.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/new_sale_screen.dart';

/// Quick actions, filtered to what the signed-in user is actually allowed to
/// do. Previously every role was offered "Add Expense", including shop
/// employees who don't hold [Permission.manageExpenses].
class QuickActionFab extends StatelessWidget {
  const QuickActionFab({
    super.key,
    required this.sales,
    required this.inventory,
    required this.customers,
    required this.cash,
    required this.auth,
  });

  final SalesController sales;
  final InventoryController inventory;
  final CustomersController customers;
  final CashController cash;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final actions = _actionsFor(context);
    if (actions.isEmpty) return const SizedBox.shrink();

    // One permitted action doesn't deserve a menu — go straight there.
    if (actions.length == 1) {
      final only = actions.single;
      return FloatingActionButton.extended(heroTag: null, 
        icon: Icon(only.icon),
        label: Text(only.label),
        onPressed: only.run,
      );
    }

    return FloatingActionButton.extended(heroTag: null, 
      icon: const Icon(Icons.add),
      label: const Text('Quick Action'),
      onPressed: () => showModalBottomSheet(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: actions
                .map((a) => ListTile(
                      leading: Icon(a.icon),
                      title: Text(a.label),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        a.run();
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  List<_QuickAction> _actionsFor(BuildContext context) => [
        if (auth.can(Permission.createSales))
          _QuickAction(
            icon: Icons.point_of_sale,
            label: 'New Sale',
            run: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NewSaleScreen(sales: sales, inventory: inventory, customers: customers, auth: auth)),
            ),
          ),
        if (auth.can(Permission.recordPayments))
          _QuickAction(
            icon: Icons.payments,
            label: 'Collect Payment',
            run: () => _pickCustomerForCollection(context),
          ),
        if (auth.can(Permission.manageExpenses))
          _QuickAction(
            icon: Icons.receipt_long,
            label: 'Add Expense',
            run: () => showAddExpenseSheet(context, cash),
          ),
      ];

  void _pickCustomerForCollection(BuildContext context) {
    // Only customers who actually owe something can take a collection.
    final owing = customers.customers.where((c) => c.outstandingBalance > 0).toList()
      ..sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: owing.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No customer has an outstanding balance.', textAlign: TextAlign.center),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: owing
                    .map((c) => ListTile(
                          title: Text(c.name),
                          subtitle: Text('Outstanding: ${formatNpr(c.outstandingBalance)}'),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            showCollectPaymentSheet(context, c, customers, auth);
                          },
                        ))
                    .toList(),
              ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({required this.icon, required this.label, required this.run});

  final IconData icon;
  final String label;
  final VoidCallback run;
}
