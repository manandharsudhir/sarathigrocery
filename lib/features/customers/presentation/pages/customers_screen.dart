import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/empty_state.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_detail_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_form_sheet.dart';

/// Quick filters on the customer list.
enum CustomerFilter {
  all('All'),
  owes('Owe money'),
  overLimit('Over limit'),
  noPayment('No payment 30+ days'),
  clear('Paid up');

  const CustomerFilter(this.label);
  final String label;

  bool matches(Customer c) => switch (this) {
    all => true,
    owes => c.outstandingBalance > 0.005,
    overLimit => c.outstandingBalance > c.creditLimit + 0.005,
    noPayment => c.outstandingBalance > 0.005 && (c.lastPaymentDate == null || DateTime.now().difference(c.lastPaymentDate!).inDays > 30),
    clear => c.outstandingBalance <= 0.005,
  };
}

enum CustomerSort {
  name('Name'),
  owed('Most owed'),
  lastPaid('Longest since payment');

  const CustomerSort(this.label);
  final String label;
}

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.controller, required this.auth, this.newSale});

  final CustomersController controller;
  final AuthController auth;

  /// Opens New Sale for a customer (null: no sales from here).
  final void Function(BuildContext context, Customer customer)? newSale;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _query = '';
  CustomerFilter _filter = CustomerFilter.all;
  CustomerSort _sort = CustomerSort.name;

  CustomersController get controller => widget.controller;
  AuthController get auth => widget.auth;

  List<Customer> _visible() {
    final q = _query.toLowerCase();
    final list = controller.customers.where((c) => _filter.matches(c) && (q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.contains(q) || c.location.toLowerCase().contains(q))).toList();
    int lastPaid(Customer c) => c.lastPaymentDate?.millisecondsSinceEpoch ?? 0;
    list.sort(switch (_sort) {
      CustomerSort.name => (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      CustomerSort.owed => (a, b) => b.outstandingBalance.compareTo(a.outstandingBalance),
      CustomerSort.lastPaid => (a, b) => lastPaid(a).compareTo(lastPaid(b)),
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = auth.can(Permission.manageCustomers) || auth.can(Permission.createCustomers);
    void add() => showCustomerFormSheet(context, controller, auth);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Customers & Udharo'),
          actions: [
            PopupMenuButton<CustomerSort>(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              initialValue: _sort,
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => [for (final v in CustomerSort.values) CheckedPopupMenuItem(value: v, checked: v == _sort, child: Text(v.label))],
            ),
          ],
        ),
        floatingActionButton: canAdd ? FloatingActionButton.extended(heroTag: null, onPressed: add, icon: const Icon(Icons.person_add_alt), label: const Text('Add Customer')) : null,
        body: controller.customers.isEmpty
            ? EmptyState(message: 'No customers yet.', actionLabel: 'Add customer', onAction: canAdd ? add : null)
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextField(
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Name, phone or place', isDense: true, border: OutlineInputBorder()),
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        for (final f in CustomerFilter.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(label: Text('${f.label} (${controller.customers.where(f.matches).length})'), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final visible = _visible();
                        if (visible.isEmpty) return const Center(child: Text('No customers match.'));
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final customer = visible[index];
                            final (label, color) = creditStatusVisual(customer.creditStatus);
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Theme.of(context).dividerColor),
                              ),
                              child: ListTile(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CustomerDetailScreen(customer: customer, controller: controller, auth: auth, newSale: widget.newSale),
                                  ),
                                ),
                                title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${customer.location} · Limit ${formatNpr(customer.creditLimit)}'),
                                    const SizedBox(height: 4),
                                    StatusBadge(label: label, color: color),
                                  ],
                                ),
                                trailing: Text(formatNpr(customer.outstandingBalance), style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
