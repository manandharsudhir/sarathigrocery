import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_detail_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_form_sheet.dart';

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({
    super.key,
    required this.controller,
    required this.auth,
  });

  final CustomersController controller;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Customers & Udharo')),
        floatingActionButton: auth.can(Permission.manageCustomers)
            ? FloatingActionButton.extended(heroTag: null, 
                onPressed: () =>
                    showCustomerFormSheet(context, controller, auth),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add Customer'),
              )
            : null,
        body: controller.customers.isEmpty
            ? const Center(child: Text('No customers yet.'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: controller.customers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final customer = controller.customers[index];
                  final (label, color) = creditStatusVisual(
                    customer.creditStatus,
                  );
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
                          builder: (_) => CustomerDetailScreen(
                            customer: customer,
                            controller: controller,
                            auth: auth,
                          ),
                        ),
                      ),
                      title: Text(
                        customer.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${customer.location} · Limit ${formatNpr(customer.creditLimit)}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatNpr(customer.outstandingBalance)),
                          const SizedBox(height: 4),
                          StatusBadge(label: label, color: color),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
