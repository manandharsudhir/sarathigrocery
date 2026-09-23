import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';
import 'package:sarathigrocery/features/suppliers/presentation/pages/supplier_detail_screen.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key, required this.controller, required this.purchasing, required this.cash, required this.auth});

  final SuppliersController controller;
  final PurchasingController purchasing;
  final CashController cash;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Suppliers')),
        body: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: controller.suppliers.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final supplier = controller.suppliers[index];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
              child: ListTile(
                title: Text(supplier.businessName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(supplier.address),
                trailing: Text(formatNpr(supplier.amountPayable), style: TextStyle(color: supplier.amountPayable > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.w600)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupplierDetailScreen(supplier: supplier, controller: controller, purchasing: purchasing, cash: cash, auth: auth))),
              ),
            );
          },
        ),
        floatingActionButton: auth.can(Permission.manageSuppliers)
            ? FloatingActionButton.extended(heroTag: null, 
                icon: const Icon(Icons.add),
                label: const Text('Add Supplier'),
                onPressed: () => _showAddSupplierSheet(context, controller),
              )
            : null,
      ),
    );
  }

  void _showAddSupplierSheet(BuildContext context, SuppliersController controller) {
    final name = TextEditingController();
    final businessName = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    final products = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add Supplier', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(controller: businessName, decoration: const InputDecoration(labelText: 'Business name')),
            const SizedBox(height: 8),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Contact name')),
            const SizedBox(height: 8),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            const SizedBox(height: 8),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: 8),
            TextField(controller: products, decoration: const InputDecoration(labelText: 'Products supplied (optional)')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (businessName.text.trim().isEmpty) return;
                  controller.createSupplier(
                    name: name.text.trim(),
                    businessName: businessName.text.trim(),
                    phone: phone.text.trim(),
                    address: address.text.trim(),
                    productsSupplied: products.text.trim(),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Save Supplier'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
