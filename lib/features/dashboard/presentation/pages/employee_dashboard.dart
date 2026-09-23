import 'package:flutter/material.dart';

import 'package:sarathigrocery/app/widgets/dashboard_actions.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/dashboard/presentation/dashboard_nav.dart';
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

/// Shop-floor home: what to do next, not what the business is worth.
/// Everything here is one tap from the action that clears it.
class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({
    super.key,
    required this.sales,
    required this.ordering,
    required this.inventory,
    required this.customers,
    required this.auth,
    required this.notifications,
    this.nav = const DashboardNav(),
  });

  final SalesController sales;
  final OrderingController ordering;
  final InventoryController inventory;
  final CustomersController customers;
  final AuthController auth;
  final NotificationRepository notifications;
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
                      subtitle: Text('Reorder level ${p.reorderLevel}'),
                      trailing: Text(
                        '${p.availableStock} left',
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
                      child: FilledButton(
                        onPressed: () => ordering.advanceOrderStatus(order, next, userName: auth.currentUser?.name ?? ''),
                        child: Text('Mark ${orderStatusLabel(next)}'),
                      ),
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
