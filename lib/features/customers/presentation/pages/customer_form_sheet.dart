import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';

/// Add ([existing] null) or edit a customer. Balance is never edited here —
/// it only moves through sales, returns and payments.
void showCustomerFormSheet(
  BuildContext context,
  CustomersController controller,
  AuthController auth, {
  Customer? existing,
}) {
  final name = TextEditingController(text: existing?.name);
  final phone = TextEditingController(text: existing?.phone);
  final location = TextEditingController(text: existing?.location);
  final pan = TextEditingController(text: existing?.pan);
  final limit = TextEditingController(
    text: existing?.creditLimit.toStringAsFixed(0),
  );
  final opening = TextEditingController(text: '0');
  // Sales staff (createCustomers only) add customers without credit terms.
  final setsTerms = auth.can(Permission.manageCustomers);
  String? error;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              existing == null ? 'Add Customer' : 'Edit Customer',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Shop / customer name',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: location,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            TextField(
              controller: pan,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PAN / VAT no. (optional, for tax invoices)'),
            ),
            const SizedBox(height: 8),
            if (!setsTerms)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Credit limit starts at 0 (cash only). The owner or cash staff set credit terms.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            if (setsTerms)
              TextField(
                controller: limit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Credit limit (NPR)',
                ),
              ),
            if (existing == null && setsTerms) ...[
              const SizedBox(height: 8),
              TextField(
                controller: opening,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Old udharo (before app, NPR)',
                  helperText:
                      'What they already owe from before. Fixed once saved.',
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  final openingBalance =
                      double.tryParse(opening.text.trim()) ?? 0;
                  final creditLimit = setsTerms
                      ? double.tryParse(limit.text.trim())
                      : 0.0;
                  if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
                    setSheetState(() => error = 'Name and phone are required.');
                    return;
                  }
                  if (creditLimit == null || creditLimit < 0) {
                    setSheetState(
                      () => error = 'Enter a credit limit of 0 or more.',
                    );
                    return;
                  }
                  final userName = auth.currentUser?.name ?? '';
                  if (existing == null) {
                    controller.createCustomer(
                      name: name.text.trim(),
                      phone: phone.text.trim(),
                      location: location.text.trim(),
                      creditLimit: creditLimit,
                      pan: pan.text,
                      openingBalance: openingBalance,
                      by: auth.currentUser!,
                    );
                  } else {
                    controller.updateCustomer(
                      existing,
                      name: name.text.trim(),
                      phone: phone.text.trim(),
                      location: location.text.trim(),
                      creditLimit: creditLimit,
                      pan: pan.text,
                      userName: userName,
                    );
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
