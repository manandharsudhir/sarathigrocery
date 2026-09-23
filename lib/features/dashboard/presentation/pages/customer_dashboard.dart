import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_detail_screen.dart';
import 'package:sarathigrocery/features/dashboard/presentation/dashboard_nav.dart';
import 'package:sarathigrocery/features/dashboard/presentation/widgets/section_header.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/notifications/presentation/pages/notifications_screen.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/customer_order.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/order_detail_screen.dart';

class CustomerDashboard extends StatelessWidget {
  const CustomerDashboard({
    super.key,
    required this.auth,
    required this.customers,
    required this.ordering,
    required this.notifications,
    this.nav = const DashboardNav(),
  });

  final AuthController auth;
  final CustomersController customers;
  final OrderingController ordering;
  final NotificationRepository notifications;
  final DashboardNav nav;

  @override
  Widget build(BuildContext context) {
    final linkedId = auth.currentUser?.linkedCustomerId;
    final matches = customers.customers.where((c) => c.id == linkedId);
    final customer = matches.isEmpty ? null : matches.first;
    final user = auth.currentUser;
    final unread = user == null ? 0 : notifications.unreadCountFor(user);

    final myOrders = customer == null
        ? <CustomerOrder>[]
        : (ordering.orders.where((o) => o.customer.id == customer.id).toList()..sort((a, b) => b.createdDate.compareTo(a.createdDate)));

    final active = myOrders
        .where((o) => o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled)
        .toList();
    final lastCompleted = myOrders.where((o) => o.status == OrderStatus.delivered).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${auth.currentUser?.name ?? ''}'),
        actions: [
          IconButton(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_outlined)),
            onPressed: user == null
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(currentUser: user, repository: notifications))),
          ),
        ],
      ),
      body: customer == null
          ? const Center(child: Text('No account data linked to this login yet.'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _AccountCard(customer: customer),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.shopping_bag_outlined),
                      label: const Text('Browse Products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      onPressed: nav.openProducts,
                    ),
                  ),
                ),

                if (lastCompleted.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.replay),
                        label: Text('Reorder last (${lastCompleted.first.items.length} items)'),
                        onPressed: () {
                          ordering.repeatOrder(lastCompleted.first);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Items added to cart'),
                              action: nav.openCart == null ? null : SnackBarAction(label: 'View cart', onPressed: nav.openCart!),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                if (active.isNotEmpty) ...[
                  const SectionHeader('Order on the way'),
                  ...active.take(2).map((o) => _ActiveOrderCard(
                        order: o,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => OrderDetailScreen(order: o, controller: ordering, auth: auth)),
                        ),
                      )),
                ],

                Row(
                  children: [
                    const Expanded(child: SectionHeader('Recent Orders')),
                    if (myOrders.length > 3 && nav.openOrders != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextButton(onPressed: nav.openOrders, child: const Text('See all')),
                      ),
                  ],
                ),
                if (myOrders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('No orders placed yet.'),
                  )
                else
                  ...myOrders.take(3).map((o) => ListTile(
                        title: Text('Order ${o.id}'),
                        subtitle: Text('${formatDate(o.createdDate)} · ${orderStatusLabel(o.status)}'),
                        trailing: Text(formatNpr(o.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => OrderDetailScreen(order: o, controller: ordering, auth: auth)),
                        ),
                      )),
              ],
            ),
    );
  }
}

/// Balance, limit and headroom in one block — a wholesale buyer's first
/// question is "how much more can I take on credit?".
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final (label, color) = creditStatusVisual(customer.creditStatus);
    final headroom = customer.creditLimit - customer.outstandingBalance;
    final overLimit = headroom <= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your Udharo', style: Theme.of(context).textTheme.bodyMedium),
              StatusBadge(label: label, color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatNpr(customer.outstandingBalance),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            overLimit
                ? 'Over your ${formatNpr(customer.creditLimit)} limit — settle up to order on credit.'
                : '${formatNpr(headroom)} still available of your ${formatNpr(customer.creditLimit)} limit',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order, required this.onTap});

  final CustomerOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stage = orderLifecycle.indexOf(order.status) + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Order ${order.id}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Text(formatNpr(order.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: stage / orderLifecycle.length,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 6),
                Text(
                  '${orderStatusLabel(order.status)} · step $stage of ${orderLifecycle.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
