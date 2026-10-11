import 'package:flutter/material.dart';

import 'package:sarathigrocery/app/widgets/dashboard_actions.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/metric_card.dart';
import 'package:sarathigrocery/features/accounting/presentation/controllers/accounting_controller.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/accounting_screen.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/cash/presentation/pages/cash_screen.dart';
import 'package:sarathigrocery/features/customers/domain/entities/credit_status.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customers_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/my_collections_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/payments_screen.dart';
import 'package:sarathigrocery/features/dashboard/presentation/dashboard_nav.dart';
import 'package:sarathigrocery/features/dashboard/presentation/widgets/attention_tile.dart';
import 'package:sarathigrocery/features/dashboard/presentation/widgets/section_header.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/order_detail_screen.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/new_sale_screen.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/presentation/controllers/settings_controller.dart';

/// Shop-floor home: what to do next, not what the business is worth.
/// Everything here is one tap from the action that clears it. Staff who can
/// handle cash & accounts (`reconcileCash`) also get the money sections.
class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({
    super.key,
    required this.sales,
    required this.ordering,
    required this.inventory,
    required this.customers,
    required this.cash,
    required this.accounting,
    required this.suppliers,
    required this.auth,
    required this.notifications,
    required this.settings,
    this.nav = const DashboardNav(),
  });

  final SalesController sales;
  final OrderingController ordering;
  final InventoryController inventory;
  final CustomersController customers;
  final CashController cash;
  final SuppliersController suppliers;
  final AuthController auth;
  final NotificationRepository notifications;
  final SettingsController settings;
  final AccountingController accounting;
  final DashboardNav nav;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todaysSales = sales.sales
        .where((s) =>
            s.status == SaleStatus.completed &&
            s.date.year == today.year &&
            s.date.month == today.month &&
            s.date.day == today.day)
        .toList();

    // Oldest first — the order that has been waiting longest is the one to
    // work on next.
    final queue = ordering.orders
        .where((o) => o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled)
        .toList()
      ..sort((a, b) => a.createdDate.compareTo(b.createdDate));

    final lowStock = inventory.products.where((p) => p.isLowStock).toList();

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: Text('Hi, ${auth.currentUser?.name ?? ''}'),
          floating: true,
          actions: dashboardActions(context, auth, notifications),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _TodayStrip(count: todaysSales.length, total: todaysSales.fold(0.0, (sum, s) => sum + s.total)),
          ),
        ),

        // Money I collected (door or counter) that the shop hasn't counted in yet.
        SliverToBoxAdapter(
          child: Builder(builder: (context) {
            final holding = customers.payments.pendingHandoverBy(auth.currentUser?.id ?? '');
            if (holding.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text('You hold ${formatNpr(holding.fold(0.0, (s, p) => s + p.amount))} to hand over'),
                  subtitle: Text('${holding.length} collection${holding.length == 1 ? '' : 's'} with you, not yet counted in at the shop'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyCollectionsScreen(payments: customers.payments, auth: auth))),
                ),
              ),
            );
          }),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(
              height: 56,
              child: FilledButton.icon(
                icon: const Icon(Icons.point_of_sale),
                label: const Text('New Sale', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NewSaleScreen(sales: sales, inventory: inventory, customers: customers, auth: auth),
                  ),
                ),
              ),
            ),
          ),
        ),

        if (auth.currentUser?.can(Permission.reconcileCash) ?? false) ..._moneySlivers(context),

        SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(child: SectionHeader(queue.isEmpty ? 'Orders' : 'Orders to Prepare (${queue.length})')),
              if (queue.length > 3 && nav.openOrders != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(onPressed: nav.openOrders, child: const Text('See all')),
                ),
            ],
          ),
        ),
        if (queue.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('No orders waiting. All caught up.'),
            ),
          )
        else
          SliverList.list(
            children: queue
                .take(3)
                .map((order) => _OrderQueueCard(order: order, ordering: ordering, auth: auth))
                .toList(),
          ),

        SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(child: SectionHeader(lowStock.isEmpty ? 'Stock' : 'Low Stock (${lowStock.length})')),
              if (lowStock.length > 3 && nav.openInventory != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TextButton(onPressed: nav.openInventory, child: const Text('See all')),
                ),
            ],
          ),
        ),
        if (lowStock.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Everything is above its reorder level.'),
            ),
          )
        else
          SliverList.list(
            children: lowStock
                .take(3)
                .map((p) => ListTile(
                      leading: const Icon(Icons.inventory_2_outlined, color: Colors.red),
                      title: Text(p.name),
                      subtitle: Text('Reorder level ${p.describeQty(p.reorderLevel)}'),
                      trailing: Text(
                        '${p.describeQty(p.availableStock)} left',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      onTap: nav.openInventory,
                    ))
                .toList(),
          ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
      ],
    );
  }

  /// Cash & accounts: today's money, what needs counting or chasing, and the
  /// latest cash-ledger rows (money that actually moved).
  List<Widget> _moneySlivers(BuildContext context) {
    final today = DateTime.now();
    bool isToday(DateTime d) => d.year == today.year && d.month == today.month && d.day == today.day;
    final collectedToday = cash.ledger.where((e) => e.type == CashEntryType.collection && isToday(e.date)).fold(0.0, (sum, e) => sum + e.amount);
    final day = todayPeriod();
    final profitLoss = accounting.statements.profitAndLoss(day.from, day.to).profit;
    final overdue = customers.customers.where((c) => c.creditStatus == CreditStatus.overdue).length;
    final toReceive = customers.payments.pendingHandover;
    final hasSuppliers = settings.has(Feature.suppliers);
    final suppliersOwed = hasSuppliers ? suppliers.suppliers.where((s) => s.amountPayable > 0).length : 0;
    final recent = cash.ledger.reversed.take(6).toList();

    void openLedger([int tab = 0]) => Navigator.push(context, MaterialPageRoute(builder: (_) => CashScreen(controller: cash, accounting: accounting, auth: auth, initialTabIndex: tab)));
    void openCustomers() => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomersScreen(controller: customers, auth: auth)));

    return [
      const SliverToBoxAdapter(child: SectionHeader('Money')),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            MetricCard(label: 'Collected Today', value: formatNpr(collectedToday), color: Colors.teal, icon: Icons.call_received, onTap: () => openLedger()),
            MetricCard(label: "Today's Expenses", value: formatNpr(cash.todayExpenses), color: Colors.purple, icon: Icons.receipt_long, onTap: () => openLedger(1)),
            MetricCard(label: 'Cash in Hand', value: formatNpr(cash.cashInHand), color: Colors.blue, icon: Icons.payments, onTap: () => openLedger()),
            MetricCard(label: 'Customer Receivables', value: formatNpr(customers.totalOutstanding), color: Colors.orange, icon: Icons.call_received, onTap: openCustomers),
            if (hasSuppliers) MetricCard(label: 'Supplier Payables', value: formatNpr(suppliers.totalPayable), color: Colors.deepOrange, icon: Icons.call_made),
            MetricCard(
              label: "Today's Profit",
              value: formatNpr(profitLoss),
              color: profitLoss >= 0 ? Colors.green : Colors.red,
              icon: Icons.insights,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountingScreen(controller: accounting, auth: auth, suppliers: suppliers))),
            ),
          ],
        ),
      ),
      if (overdue > 0 || suppliersOwed > 0 || toReceive.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader('Needs Attention')),
        SliverList.list(
          children: [
            if (toReceive.isNotEmpty)
              AttentionTile(
                icon: Icons.account_balance_wallet_outlined,
                color: Colors.orange,
                label: '${formatNpr(toReceive.fold(0.0, (s, p) => s + p.amount))} with staff, not yet counted in',
                actionLabel: 'Count cash in',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentsScreen(payments: customers.payments, auth: auth))),
              ),
            if (overdue > 0)
              AttentionTile(
                icon: Icons.person_off_outlined,
                color: Colors.red,
                label: '$overdue ${overdue == 1 ? 'customer is' : 'customers are'} over their credit limit',
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
      const SliverToBoxAdapter(child: SectionHeader('Recent Transactions')),
      SliverList.list(
        children: recent.isEmpty
            ? [const ListTile(dense: true, title: Text('No transactions recorded yet.'))]
            : recent.map((e) {
                final color = e.isOutflow ? Colors.red : Colors.green;
                return ListTile(
                  dense: true,
                  leading: Icon(e.isOutflow ? Icons.arrow_upward : Icons.arrow_downward, size: 18, color: color),
                  title: Text(e.note),
                  subtitle: Text(formatDate(e.date)),
                  trailing: Text('${e.isOutflow ? '-' : '+'}${formatNpr(e.amount)}', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                );
              }).toList(),
      ),
    ];
  }
}

class _TodayStrip extends StatelessWidget {
  const _TodayStrip({required this.count, required this.total});

  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatNpr(total),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.green),
                ),
                Text('$count ${count == 1 ? 'sale' : 'sales'} today', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One waiting order with its single next step as a button — the whole point
/// is that preparing an order never needs a detail screen.
class _OrderQueueCard extends StatelessWidget {
  const _OrderQueueCard({required this.order, required this.ordering, required this.auth});

  final CustomerOrder order;
  final OrderingController ordering;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final next = nextOrderStatus(order.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(order.customer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text(formatNpr(order.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${order.id} · ${order.items.length} ${order.items.length == 1 ? 'item' : 'items'} · ${orderStatusLabel(order.status)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (next != null)
                    Expanded(
                      child: NextOrderButton(order: order, ordering: ordering, auth: auth),
                    ),
                  if (next != null) const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(order: order, controller: ordering, auth: auth, staffView: true),
                      ),
                    ),
                    child: const Text('Details'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
