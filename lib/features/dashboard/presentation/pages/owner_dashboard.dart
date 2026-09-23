import 'package:flutter/material.dart';

import 'package:sarathigrocery/app/widgets/dashboard_actions.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/metric_card.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/credit_status.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/payments_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customers_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/payments_screen.dart';
import 'package:sarathigrocery/features/dashboard/presentation/dashboard_nav.dart';
import 'package:sarathigrocery/features/dashboard/presentation/widgets/attention_tile.dart';
import 'package:sarathigrocery/features/dashboard/presentation/widgets/section_header.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

class OwnerDashboard extends StatelessWidget {
  const OwnerDashboard({
    super.key,
    required this.sales,
    required this.cash,
    required this.customers,
    required this.suppliers,
    required this.ordering,
    required this.inventory,
    required this.auth,
    required this.notifications,
    this.nav = const DashboardNav(),
  });

  final SalesController sales;
  final CashController cash;
  final CustomersController customers;
  final SuppliersController suppliers;
  final OrderingController ordering;
  final InventoryController inventory;
  final AuthController auth;
  final NotificationRepository notifications;
  final DashboardNav nav;

  @override
  Widget build(BuildContext context) {
    final profitLoss = sales.totalRevenue - sales.totalCostOfGoods - cash.totalExpensesAllTime;
    final overdueCount = customers.customers.where((c) => c.creditStatus == CreditStatus.overdue).length;

    void openCustomers() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CustomersScreen(controller: customers, auth: auth)),
        );

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('Owner Dashboard'),
          floating: true,
          actions: dashboardActions(context, auth, notifications),
        ),

        // The two numbers an owner opens the app to see.
        const SliverToBoxAdapter(child: SectionHeader('Today')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              MetricCard(
                label: "Today's Sales",
                value: formatNpr(sales.todayRevenue),
                color: Colors.green,
                icon: Icons.trending_up,
                onTap: nav.openSales,
              ),
              MetricCard(
                label: 'Profit / Loss',
                value: formatNpr(profitLoss),
                color: profitLoss >= 0 ? Colors.green : Colors.red,
                icon: Icons.insights,
              ),
            ],
          ),
        ),

        _NeedsAttention(
          pendingOrders: ordering.pendingCount,
          lowStock: inventory.lowStockCount,
          nearExpiry: inventory.nearExpiryCount,
          overdueCustomers: overdueCount,
          uninvoiced: ordering.uninvoicedDeliveries.length,
          onInvoice: () async {
            final n = ordering.uninvoicedDeliveries.length;
            final ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Bill $n delivered ${n == 1 ? 'order' : 'orders'}?'),
                content: const Text('These were delivered before deliveries created invoices, so the customers were never charged. '
                    'Each order total will be added to its customer\'s balance and appear on their statement.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create invoices')),
                ],
              ),
            );
            if (ok == true) ordering.invoiceUninvoicedDeliveries(by: auth.currentUser!);
          },
          overLimitOrders: ordering.orders.where((o) => o.overCreditLimit && o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled).length,
          payments: customers.payments,
          unbalancedCustomers: customers.customers.where((c) => !customers.payments.statementFor(c).balanced).length,
          nav: nav,
          onOpenCustomers: openCustomers,
          onOpenPayments: (tab) => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsScreen(payments: customers.payments, auth: auth, initialTab: tab))),
        ),

        const SliverToBoxAdapter(child: SectionHeader('Money')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              MetricCard(label: 'Cash in Hand', value: formatNpr(cash.cashInHand), color: Colors.blue, icon: Icons.payments),
              MetricCard(
                label: 'Money Receivable',
                value: formatNpr(customers.totalOutstanding),
                color: Colors.orange,
                icon: Icons.call_received,
                onTap: openCustomers,
              ),
              MetricCard(label: 'Money Payable', value: formatNpr(suppliers.totalPayable), color: Colors.deepOrange, icon: Icons.call_made),
              MetricCard(label: "Today's Expenses", value: formatNpr(cash.todayExpenses), color: Colors.purple, icon: Icons.receipt_long),
            ],
          ),
        ),

        const SliverToBoxAdapter(child: SectionHeader('Recent Activity')),
        SliverList.list(
          children: recentActivity(sales, cash)
              .map((line) => ListTile(dense: true, leading: const Icon(Icons.circle, size: 8), title: Text(line)))
              .toList(),
        ),

        const SliverToBoxAdapter(child: SectionHeader('Staff Activity Today')),
        SliverList.list(children: _staffActivity(context, sales)),

        const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
      ],
    );
  }

  /// Answers the owner's "what are my employees doing?" — today's completed
  /// sales grouped by whoever recorded them.
  List<Widget> _staffActivity(BuildContext context, SalesController sales) {
    final today = DateTime.now();
    final byStaff = <String, (int, double)>{};
    for (final s in sales.sales) {
      if (s.status != SaleStatus.completed) continue;
      if (s.date.year != today.year || s.date.month != today.month || s.date.day != today.day) continue;
      if (s.createdByName.isEmpty) continue;
      final existing = byStaff[s.createdByName] ?? (0, 0.0);
      byStaff[s.createdByName] = (existing.$1 + 1, existing.$2 + s.total);
    }

    if (byStaff.isEmpty) {
      return [
        const ListTile(dense: true, leading: Icon(Icons.person_outline), title: Text('No staff sales recorded today.')),
      ];
    }

    return byStaff.entries
        .map((e) => ListTile(
              dense: true,
              leading: CircleAvatar(radius: 14, child: Text(e.key.isEmpty ? '?' : e.key[0])),
              title: Text(e.key),
              subtitle: Text('${e.value.$1} ${e.value.$1 == 1 ? 'sale' : 'sales'}'),
              trailing: Text(formatNpr(e.value.$2), style: const TextStyle(fontWeight: FontWeight.w600)),
            ))
        .toList();
  }
}

/// Only renders the rows that actually need the owner to act — a clean
/// section is a meaningful signal, so nothing is shown when all is well.
class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({
    required this.pendingOrders,
    required this.lowStock,
    required this.nearExpiry,
    required this.overdueCustomers,
    required this.uninvoiced,
    required this.onInvoice,
    required this.overLimitOrders,
    required this.payments,
    required this.unbalancedCustomers,
    required this.nav,
    required this.onOpenCustomers,
    required this.onOpenPayments,
  });

  final int uninvoiced;
  final VoidCallback onInvoice;
  final int overLimitOrders;
  final PaymentsController payments;
  final int unbalancedCustomers;
  final void Function(int tab) onOpenPayments;

  final int pendingOrders;
  final int lowStock;
  final int nearExpiry;
  final int overdueCustomers;
  final DashboardNav nav;
  final VoidCallback onOpenCustomers;

  @override
  Widget build(BuildContext context) {
    final disputed = payments.disputed.length;
    final toReceive = payments.pendingHandover;
    final toReceiveTotal = toReceive.fold(0.0, (s, p) => s + p.amount);
    final shortfall = payments.shortfalls.fold(0.0, (s, p) => s + p.shortfall);
    final tiles = <Widget>[
      if (uninvoiced > 0)
        AttentionTile(
          icon: Icons.receipt_long_outlined,
          color: Colors.red,
          label: '$uninvoiced delivered ${uninvoiced == 1 ? 'order was' : 'orders were'} never billed',
          actionLabel: 'Bill now',
          onTap: onInvoice,
        ),
      if (disputed > 0)
        AttentionTile(
          icon: Icons.report_outlined,
          color: Colors.red,
          label: '$disputed ${disputed == 1 ? 'payment is' : 'payments are'} disputed by customers',
          actionLabel: 'Review',
          onTap: () => onOpenPayments(1),
        ),
      if (unbalancedCustomers > 0)
        AttentionTile(
          icon: Icons.rule,
          color: Colors.red,
          label: "$unbalancedCustomers ${unbalancedCustomers == 1 ? "customer's balance doesn't" : "customers' balances don't"} match their records",
          actionLabel: 'Check',
          onTap: onOpenCustomers,
        ),
      if (shortfall > 0)
        AttentionTile(
          icon: Icons.money_off,
          color: Colors.red,
          label: '${formatNpr(shortfall)} short in cash handovers',
          actionLabel: 'Review',
          onTap: () => onOpenPayments(1),
        ),
      if (toReceive.isNotEmpty)
        AttentionTile(
          icon: Icons.account_balance_wallet_outlined,
          color: Colors.orange,
          label: '${formatNpr(toReceiveTotal)} collected, not yet in the till',
          actionLabel: 'Receive',
          onTap: () => onOpenPayments(0),
        ),
      if (overLimitOrders > 0)
        AttentionTile(
          icon: Icons.credit_card_off_outlined,
          color: Colors.deepOrange,
          label: '$overLimitOrders ${overLimitOrders == 1 ? 'order goes' : 'orders go'} over the credit limit',
          actionLabel: 'Decide',
          onTap: nav.openOrders,
        ),
      if (pendingOrders > 0)
        AttentionTile(
          icon: Icons.list_alt,
          color: Colors.indigo,
          label: '$pendingOrders ${pendingOrders == 1 ? 'order' : 'orders'} waiting',
          actionLabel: 'View orders',
          onTap: nav.openOrders,
        ),
      if (overdueCustomers > 0)
        AttentionTile(
          icon: Icons.person_off_outlined,
          color: Colors.red,
          label: '$overdueCustomers ${overdueCustomers == 1 ? 'customer is' : 'customers are'} over their credit limit',
          actionLabel: 'Collect udharo',
          onTap: onOpenCustomers,
        ),
      if (lowStock > 0)
        AttentionTile(
          icon: Icons.inventory_2_outlined,
          color: Colors.deepOrange,
          label: '$lowStock ${lowStock == 1 ? 'item is' : 'items are'} low on stock',
          actionLabel: 'Reorder',
          onTap: nav.openInventory,
        ),
      if (nearExpiry > 0)
        AttentionTile(
          icon: Icons.event_busy,
          color: Colors.amber,
          label: '$nearExpiry ${nearExpiry == 1 ? 'item expires' : 'items expire'} soon',
          actionLabel: 'Check stock',
          onTap: nav.openInventory,
        ),
    ];

    if (tiles.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverMainAxisGroup(
      slivers: [
        const SliverToBoxAdapter(child: SectionHeader('Needs Attention')),
        SliverList.list(children: tiles),
      ],
    );
  }
}

List<String> recentActivity(SalesController sales, CashController cash) {
  final entries = <MapEntry<DateTime, String>>[
    ...sales.sales.map((s) => MapEntry(s.date, 'Sale ${s.id} · ${formatNpr(s.total)}${s.customer != null ? ' · ${s.customer!.name}' : ''}')),
    ...cash.expenses.map((e) => MapEntry(e.date, 'Expense · ${e.category} · ${formatNpr(e.amount)}')),
    ...cash.ledger.where((e) => e.type.name == 'collection').map((e) => MapEntry(e.date, 'Payment collected · ${formatNpr(e.amount)}')),
  ]..sort((a, b) => b.key.compareTo(a.key));

  if (entries.isEmpty) return ['No activity yet today.'];
  return entries.take(5).map((e) => e.value).toList();
}
