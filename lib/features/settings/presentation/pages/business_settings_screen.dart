import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/settings/presentation/controllers/settings_controller.dart';

class BusinessSettingsScreen extends StatefulWidget {
  const BusinessSettingsScreen({super.key, required this.controller, required this.auth});

  final SettingsController controller;
  final AuthController auth;

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
          if (widget.auth.currentUser?.role == UserRole.owner) ...[
            const SizedBox(height: 40),
            const Divider(),
            Text('Danger zone', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            const Text('Erase every record in the backend and start again as a new business.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Reset all business data'),
              onPressed: () => showDialog(context: context, builder: (_) => _ResetDialog(controller: widget.controller, auth: widget.auth)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResetDialog extends StatefulWidget {
  const _ResetDialog({required this.controller, required this.auth});

  final SettingsController controller;
  final AuthController auth;

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.resetBusiness(owner: widget.auth.currentUser!, typedName: _name.text, password: _password.text);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      await widget.auth.logout();
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessName = widget.controller.current.businessName;
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: error),
      title: const Text('Reset all business data?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes, for everyone: products, stock, customers and their balances, orders, sales, '
              'payments, cash/bank ledgers, suppliers, purchases, expenses, notifications, the audit log, and all staff '
              'and customer profiles. It cannot be undone and there is no backup.\n\n'
              'Afterwards you are signed out and can set up the business again with your phone number. '
              'Other people\'s logins stay registered in Firebase Authentication; delete them in the Firebase console '
              'if you want to reuse their phone numbers.',
            ),
            const SizedBox(height: 16),
            Text('Type "$businessName" to confirm:'),
            TextField(controller: _name, enabled: !_busy),
            const SizedBox(height: 8),
            TextField(controller: _password, enabled: !_busy, obscureText: true, decoration: const InputDecoration(labelText: 'Your password')),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: error)),
            ],
            if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: error),
          onPressed: _busy ? null : _reset,
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}
