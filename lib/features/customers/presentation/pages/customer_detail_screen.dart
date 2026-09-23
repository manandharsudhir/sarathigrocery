import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/status_badge.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/credit_status.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_statement_screen.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/payment_widgets.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_form_sheet.dart';

(String, Color) creditStatusVisual(CreditStatus status) {
  switch (status) {
    case CreditStatus.safe:
      return ('Safe', Colors.green);
    case CreditStatus.dueSoon:
      return ('Due Soon', Colors.amber);
    case CreditStatus.overdue:
      return ('Overdue / Limit Exceeded', Colors.red);
  }
}

class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.customer, required this.controller, required this.auth});

  final Customer customer;
  final CustomersController controller;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.payments]),
      builder: (context, _) {
        final (label, color) = creditStatusVisual(customer.creditStatus);
        final statement = controller.payments.statementFor(customer);
        final canManage = auth.can(Permission.manageCustomers);
        final login = controller.loginFor(customer);

        return Scaffold(
          appBar: AppBar(
            title: Text(customer.name),
            actions: [
              if (canManage)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => showCustomerFormSheet(context, controller, auth, existing: customer),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  StatusBadge(label: label, color: color),
                  if (!statement.balanced) ...[
                    const SizedBox(width: 8),
                    const StatusBadge(label: "Balance doesn't match records", color: Colors.red),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(label: 'Phone', value: customer.phone),
              _InfoRow(label: 'Location', value: customer.location),
              _InfoRow(label: 'Credit Limit', value: formatNpr(customer.creditLimit)),
              _InfoRow(label: 'Outstanding Balance', value: formatNpr(customer.outstandingBalance)),
              _InfoRow(
                label: 'Last Payment',
                value: customer.lastPaymentDate == null ? 'Never' : formatDaysAgo(customer.lastPaymentDate!),
              ),
              if (customer.defaultDiscountPercent > 0) _InfoRow(label: 'Default Discount', value: '${customer.defaultDiscountPercent}%'),
              _InfoRow(label: 'App Login', value: login == null ? 'None' : '${login.phone}${login.active ? '' : ' (deactivated)'}'),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: customer.outstandingBalance <= 0 ? null : () => showCollectPaymentSheet(context, customer, controller, auth),
                icon: const Icon(Icons.payments),
                label: const Text('Collect Payment'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerStatementScreen(customer: customer, payments: controller.payments, auth: auth))),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Statement'),
              ),
              if (canManage && login == null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => showCreateCustomerLoginSheet(context, customer, controller, auth),
                  icon: const Icon(Icons.phonelink_setup_outlined),
                  label: const Text('Create App Login'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

void showCollectPaymentSheet(BuildContext context, Customer customer, CustomersController controller, AuthController auth) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => CollectPaymentForm(
      customer: customer,
      submitLabel: 'Record Payment',
      onSubmit: (amount, method, reference, _) async {
        final payment = controller.payments.record(customer, amount, method: method, reference: reference, collector: auth.currentUser!);
        return payment.isSettled ? 'Payment recorded.' : 'Payment recorded — hand the ${method == PaymentMethod.cash ? 'cash' : 'reference'} to the owner/accountant.';
      },
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
