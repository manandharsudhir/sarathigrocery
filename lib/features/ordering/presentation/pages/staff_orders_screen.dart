import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/ordering/domain/entities/order_status.dart';
import 'package:sarathigrocery/features/ordering/presentation/controllers/ordering_controller.dart';
import 'package:sarathigrocery/features/ordering/presentation/pages/order_detail_screen.dart';

class StaffOrdersScreen extends StatefulWidget {
  const StaffOrdersScreen({super.key, required this.controller, required this.auth});

  final OrderingController controller;
  final AuthController auth;

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

        return Scaffold(
          appBar: AppBar(title: const Text('Orders')),
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
                    ? const Center(child: Text('No orders here.'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: orders.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(order.customer.name),
                            subtitle: Text('${order.id} · ${formatDate(order.createdDate)}'),
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
                                  staffView: widget.auth.currentUser?.role != UserRole.accountant,
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
