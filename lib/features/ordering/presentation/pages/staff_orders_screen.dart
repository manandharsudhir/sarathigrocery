import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/empty_state.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/order_detail_screen.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/staff_new_order_screen.dart';

class StaffOrdersScreen extends StatefulWidget {
  const StaffOrdersScreen({super.key, required this.controller, required this.auth, this.customers, this.inventory});

  final OrderingController controller;
  final AuthController auth;

  /// Given where staff may take orders for customers (the "New Order" button).
  final CustomersController? customers;
  final InventoryController? inventory;

  @override
  State<StaffOrdersScreen> createState() => _StaffOrdersScreenState();
}

class _StaffOrdersScreenState extends State<StaffOrdersScreen> {
  OrderStatus? _filter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final orders = widget.controller.orders
            .where((o) => _filter == null || o.status == _filter)
            .toList()
            .reversed
            .toList();
        final canOrder = widget.customers != null && widget.inventory != null && widget.auth.can(Permission.createSales);
        void newOrder() => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StaffNewOrderScreen(ordering: widget.controller, customers: widget.customers!, inventory: widget.inventory!, auth: widget.auth),
              ),
            );

        return Scaffold(
          appBar: AppBar(title: const Text('Orders')),
          floatingActionButton: canOrder
              ? FloatingActionButton.extended(
                  heroTag: null,
                  icon: const Icon(Icons.add_call),
                  label: const Text('New Order'),
                  onPressed: newOrder,
                )
              : null,
          body: Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                    ),
                    ...OrderStatus.values.map((s) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(label: Text(orderStatusLabel(s)), selected: _filter == s, onSelected: (_) => setState(() => _filter = s)),
                        )),
                  ],
                ),
              ),
              Expanded(
                child: orders.isEmpty
                    ? EmptyState(message: 'No orders here.', actionLabel: 'New order', onAction: canOrder && _filter == null ? newOrder : null)
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: orders.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(order.customer.name),
                            subtitle: Text([
                              '${order.id} · ${formatDate(order.createdDate)}',
                              if (order.assignedToName.isNotEmpty) 'Delivery: ${order.assignedToName}',
                              orderPaymentSummary(order, widget.controller.paymentsFor(order)),
                            ].where((s) => s.isNotEmpty).join(' · ')),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(formatNpr(order.total)),
                                Text(orderStatusLabel(order.status), style: TextStyle(color: order.status == OrderStatus.cancelled ? Colors.red : Colors.teal, fontSize: 12)),
                              ],
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderDetailScreen(
                                  order: order,
                                  controller: widget.controller,
                                  auth: widget.auth,
                                  staffView: true,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
