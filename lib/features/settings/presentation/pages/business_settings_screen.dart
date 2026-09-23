import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/settings/presentation/controllers/settings_controller.dart';

class BusinessSettingsScreen extends StatefulWidget {
  const BusinessSettingsScreen({super.key, required this.controller});

  final SettingsController controller;

  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  late final _name = TextEditingController(text: widget.controller.current.businessName);
  late final _address = TextEditingController(text: widget.controller.current.businessAddress);
  late final _phone = TextEditingController(text: widget.controller.current.businessPhone);
  late final _threshold = TextEditingController(text: widget.controller.current.defaultLowStockThreshold.toString());
  late final _tax = TextEditingController(text: widget.controller.current.taxPercent.toStringAsFixed(0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Business name')),
          const SizedBox(height: 12),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
          const SizedBox(height: 12),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 12),
          const ListTile(contentPadding: EdgeInsets.zero, title: Text('Currency'), trailing: Text('Rs. / NPR')),
          const SizedBox(height: 12),
          TextField(controller: _threshold, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Default low-stock threshold')),
          const SizedBox(height: 12),
          TextField(controller: _tax, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tax % (0 if not applicable)')),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              widget.controller.update(
                businessName: _name.text.trim(),
                businessAddress: _address.text.trim(),
                businessPhone: _phone.text.trim(),
                defaultLowStockThreshold: int.tryParse(_threshold.text) ?? widget.controller.current.defaultLowStockThreshold,
                taxPercent: double.tryParse(_tax.text) ?? 0,
              );
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
            },
            child: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }
}
