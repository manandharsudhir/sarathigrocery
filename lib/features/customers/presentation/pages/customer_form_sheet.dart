import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';

/// Add ([existing] null) or edit a customer. Balance is never edited here —
/// it only moves through sales, returns and payments.
void showCustomerFormSheet(BuildContext context, CustomersController controller, AuthController auth, {Customer? existing}) {
  final name = TextEditingController(text: existing?.name);
  final phone = TextEditingController(text: existing?.phone);
  final location = TextEditingController(text: existing?.location);
  final limit = TextEditingController(text: existing?.creditLimit.toStringAsFixed(0));
  final discount = TextEditingController(text: existing == null ? '0' : existing.defaultDiscountPercent.toString());
  String? error;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(existing == null ? 'Add Customer' : 'Edit Customer', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Shop / customer name')),
            const SizedBox(height: 8),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 8),
            TextField(controller: location, decoration: const InputDecoration(labelText: 'Location')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Credit limit (NPR)'))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: discount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Default discount %'))),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final creditLimit = double.tryParse(limit.text.trim());
                  final discountPercent = double.tryParse(discount.text.trim());
                  if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
                    setSheetState(() => error = 'Name and phone are required.');
                    return;
                  }
                  if (creditLimit == null || creditLimit < 0) {
                    setSheetState(() => error = 'Enter a credit limit of 0 or more.');
                    return;
                  }
                  if (discountPercent == null || discountPercent < 0 || discountPercent > 100) {
                    setSheetState(() => error = 'Discount must be between 0 and 100.');
                    return;
                  }
                  final userName = auth.currentUser?.name ?? '';
                  if (existing == null) {
                    controller.createCustomer(name: name.text.trim(), phone: phone.text.trim(), location: location.text.trim(), creditLimit: creditLimit, defaultDiscountPercent: discountPercent, userName: userName);
                  } else {
                    controller.updateCustomer(existing, name: name.text.trim(), phone: phone.text.trim(), location: location.text.trim(), creditLimit: creditLimit, defaultDiscountPercent: discountPercent, userName: userName);
                  }
                  Navigator.pop(context);
                },
                child: Text(existing == null ? 'Add Customer' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Creates the customer's own app login (to browse and place orders).
void showCreateCustomerLoginSheet(BuildContext context, Customer customer, CustomersController controller, AuthController auth) {
  final phone = TextEditingController(text: customer.phone);
  final password = TextEditingController();
  String? error;
  var busy = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App login for ${customer.name}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('They will see the product catalogue, their own orders and their own balance only.'),
            const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Login phone')),
            const SizedBox(height: 8),
            TextField(controller: password, decoration: const InputDecoration(labelText: 'Temporary password (min 8 characters)')),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setSheetState(() {
                          busy = true;
                          error = null;
                        });
                        final result = await controller.createLogin(customer, phone: phone.text.trim(), password: password.text, userName: auth.currentUser?.name ?? '');
                        if (!context.mounted) return;
                        if (result == null) {
                          Navigator.pop(context);
                        } else {
                          setSheetState(() {
                            busy = false;
                            error = result;
                          });
                        }
                      },
                child: const Text('Create Login'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
