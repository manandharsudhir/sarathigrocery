import 'package:flutter/material.dart';

import 'package:sarathigrocery/app/widgets/dashboard_actions.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/metric_card.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/cash/presentation/pages/cash_screen.dart';
import 'package:sarathigrocery/features/customers/domain/entities/credit_status.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customers_screen.dart';
import 'package:sarathigrocery/features/dashboard/presentation/dashboard_nav.dart';
import 'package:sarathigrocery/features/dashboard/presentation/widgets/attention_tile.dart';
import 'package:sarathigrocery/features/dashboard/presentation/widgets/section_header.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

class AccountantDashboard extends StatelessWidget {
  const AccountantDashboard({
    super.key,
    required this.sales,
    required this.cash,
    required this.customers,
    required this.suppliers,
    required this.auth,
    required this.notifications,
    this.nav = const DashboardNav(),
  });

  final SalesController sales;
  final CashController cash;
  final CustomersController customers;
  final SuppliersController suppliers;
  final AuthController auth;
  final NotificationRepository notifications;
  final DashboardNav nav;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    bool isToday(DateTime d) => d.year == today.year && d.month == today.month && d.day == today.day;

    final collectedToday = cash.ledger
        .where((e) => e.type == CashEntryType.collection && isToday(e.date))
        .fold(0.0, (sum, e) => sum + e.amount);

    final profitLoss = sales.totalRevenue - sales.totalCostOfGoods - cash.totalExpensesAllTime;
    final overdue = customers.customers.where((c) => c.creditStatus == CreditStatus.overdue).toList();
    final suppliersOwed = suppliers.suppliers.where((s) => s.amountPayable > 0).length;

    void openLedger([int tab = 0]) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CashScreen(controller: cash, initialTabIndex: tab)),
        );
    void openCustomers() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CustomersScreen(controller: customers, auth: auth)),
        );

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('Accountant Dashboard'),
          floating: true,
          actions: dashboardActions(context, auth, notifications),
        ),

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
                label: 'Collected Today',
                value: formatNpr(collectedToday),
                color: Colors.teal,
                icon: Icons.call_received,
                onTap: () => openLedger(),
              ),
              MetricCard(
                label: "Today's Expenses",
                value: formatNpr(cash.todayExpenses),
                color: Colors.purple,
                icon: Icons.receipt_long,
                onTap: () => openLedger(1),
              ),
              MetricCard(
                label: 'Cash in Hand',
                value: formatNpr(cash.cashInHand),
                color: Colors.blue,
                icon: Icons.payments,
                onTap: () => openLedger(),
              ),
            ],
          ),
        ),

        if (overdue.isNotEmpty || suppliersOwed > 0) ...[
          const SliverToBoxAdapter(child: SectionHeader('Needs Attention')),
          SliverList.list(
            children: [
              if (overdue.isNotEmpty)
                AttentionTile(
                  icon: Icons.person_off_outlined,
                  color: Colors.red,
                  label: '${overdue.length} ${overdue.length == 1 ? 'customer is' : 'customers are'} over their credit limit',
                  actionLabel: 'Collect',
                  onTap: openCustomers,
                ),
              if (suppliersOwed > 0)
                AttentionTile(
                  icon: Icons.call_made,
                  color: Colors.deepOrange,
                  label: '$suppliersOwed ${suppliersOwed == 1 ? 'supplier is' : 'suppliers are'} awaiting payment',
                  actionLabel: 'Review',
                  onTap: () => openLedger(),
                ),
            ],
          ),
        ],

        const SliverToBoxAdapter(child: SectionHeader('Balances')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: [
              MetricCard(
                label: 'Customer Receivables',
                value: formatNpr(customers.totalOutstanding),
                color: Colors.orange,
                icon: Icons.call_received,
                onTap: openCustomers,
              ),
              MetricCard(
                label: 'Supplier Payables',
                value: formatNpr(suppliers.totalPayable),
                color: Colors.deepOrange,
                icon: Icons.call_made,
              ),
              MetricCard(
                label: 'Profit / Loss',
                value: formatNpr(profitLoss),
                color: profitLoss >= 0 ? Colors.green : Colors.red,
                icon: Icons.insights,
              ),
              MetricCard(
                label: 'Partner Capital',
                value: 'View',
                color: Colors.indigo,
                icon: Icons.account_balance,
                onTap: () => openLedger(2),
              ),
            ],
          ),
        ),

        const SliverToBoxAdapter(child: SectionHeader('Recent Transactions')),
        SliverList.list(children: _recentTransactions(context)),

        const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
      ],
    );
  }

  /// Straight off the cash ledger — every row is money that actually moved,
  /// which is what an accountant is reconciling against.
  List<Widget> _recentTransactions(BuildContext context) {
    final entries = cash.ledger.reversed.take(6).toList();
    if (entries.isEmpty) {
      return [const ListTile(dense: true, title: Text('No transactions recorded yet.'))];
    }

    return entries.map((e) {
      final isOutflow = e.type == CashEntryType.expense ||
          e.type == CashEntryType.deposit ||
          e.type == CashEntryType.supplierPayment;
      return ListTile(
        dense: true,
        leading: Icon(
          isOutflow ? Icons.arrow_upward : Icons.arrow_downward,
          size: 18,
          color: isOutflow ? Colors.red : Colors.green,
        ),
        title: Text(e.note),
        subtitle: Text(formatDate(e.date)),
        trailing: Text(
          '${isOutflow ? '-' : '+'}${formatNpr(e.amount)}',
          style: TextStyle(color: isOutflow ? Colors.red : Colors.green, fontWeight: FontWeight.w600),
        ),
      );
    }).toList();
  }
}
