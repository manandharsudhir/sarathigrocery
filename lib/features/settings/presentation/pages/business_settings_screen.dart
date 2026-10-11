import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';

import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/account_security_dialogs.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/profile_screen.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/presentation/controllers/settings_controller.dart';

class BusinessSettingsScreen extends StatefulWidget {
  const BusinessSettingsScreen({super.key, required this.controller, required this.auth, this.onExport});

  final SettingsController controller;
  final AuthController auth;

  /// Shares this shop's data (customers, sales, payments, ledger) as a file.
  final Future<void> Function()? onExport;

  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  late final _name = TextEditingController(text: widget.controller.current.businessName);
  late final _address = TextEditingController(text: widget.controller.current.businessAddress);
  late final _phone = TextEditingController(text: widget.controller.current.businessPhone);
  late final _threshold = TextEditingController(text: widget.controller.current.defaultLowStockThreshold.toString());
  late final _tax = TextEditingController(text: widget.controller.current.taxPercent > 0 ? formatQty(widget.controller.current.taxPercent) : '13');
  late final _pan = TextEditingController(text: widget.controller.current.panNumber);
  late final _margin = TextEditingController(text: formatQty(widget.controller.current.marginPercent));
  late bool _vatRegistered = widget.controller.current.vatRegistered;
  late bool _pricesIncludeVat = widget.controller.current.pricesIncludeVat;
  late final _currency = TextEditingController(text: widget.controller.current.currency);
  late final _countryCode = TextEditingController(text: widget.controller.current.countryCode);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text('My account'),
            subtitle: const Text('Email and password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(auth: widget.auth))),
          ),
          const Divider(),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Business name')),
          const SizedBox(height: 12),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
          const SizedBox(height: 12),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _currency, decoration: const InputDecoration(labelText: 'Currency', hintText: 'NPR'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _countryCode, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Country code', hintText: '+977'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _threshold, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Default low-stock threshold')),
          const SizedBox(height: 12),
          TextField(
            controller: _margin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Default margin %', helperText: 'Purchases suggest minimum selling prices at cost + this %'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              widget.controller.update(
                businessName: _name.text.trim(),
                businessAddress: _address.text.trim(),
                businessPhone: _phone.text.trim(),
                defaultLowStockThreshold: int.tryParse(_threshold.text) ?? widget.controller.current.defaultLowStockThreshold,
                taxPercent: widget.controller.current.taxPercent,
                currency: _currency.text.trim().isEmpty ? null : _currency.text.trim(),
                countryCode: _countryCode.text.trim().isEmpty ? null : _countryCode.text.trim(),
              );
              final margin = double.tryParse(_margin.text) ?? 0;
              if (margin != widget.controller.current.marginPercent) widget.controller.setMargin(margin);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
            },
            child: const Text('Save Settings'),
          ),
          if (widget.auth.currentUser?.role == UserRole.owner) ...[
            const SizedBox(height: 32),
            Text('VAT', style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('VAT registered'),
              subtitle: const Text('Every sale becomes a numbered tax invoice (needs internet), and purchases record the supplier\'s VAT.'),
              value: _vatRegistered,
              onChanged: (v) => setState(() => _vatRegistered = v),
            ),
            if (_vatRegistered) ...[
              TextField(controller: _pan, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PAN / VAT number')),
              TextField(controller: _tax, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'VAT rate %')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Prices include VAT'),
                subtitle: Text(_pricesIncludeVat ? 'The price you type is what the customer pays; the bill shows the VAT inside it.' : 'VAT is added on top of the prices you type.'),
                value: _pricesIncludeVat,
                onChanged: (v) => setState(() => _pricesIncludeVat = v),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  if (_vatRegistered && _pan.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your PAN / VAT number.')));
                    return;
                  }
                  widget.controller.setVat(registered: _vatRegistered, pan: _pan.text, rate: double.tryParse(_tax.text) ?? 13, pricesIncludeVat: _pricesIncludeVat);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('VAT settings saved')));
                },
                child: const Text('Save VAT settings'),
              ),
            ),
            const Text('Check the bill format and VAT treatment with your accountant before issuing real tax invoices.', style: TextStyle(color: Colors.grey)),
            const Divider(height: 32),
            Text('More features', style: Theme.of(context).textTheme.titleMedium),
            const Text('Turn on only what your shop uses. Turning one off hides it; nothing is deleted.'),
            for (final f in Feature.values)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(f.label),
                subtitle: Text(f.hint),
                value: widget.controller.has(f),
                onChanged: (on) => setState(() => widget.controller.setFeature(f, on)),
              ),
            const SizedBox(height: 32),
            Text('Safeguards', style: Theme.of(context).textTheme.titleMedium),
            const Text('Extra checks for when staff deliver and collect money. Off is simpler for a one-person shop.'),
            for (final g in Safeguard.values)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(g.label),
                subtitle: Text(g.hint),
                value: widget.controller.guards(g),
                onChanged: (on) => setState(() => widget.controller.setSafeguard(g, on)),
              ),
            if (widget.auth.isFounder) ...[
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
            const SizedBox(height: 8),
            if (widget.onExport != null)
              OutlinedButton.icon(icon: const Icon(Icons.download_outlined), label: const Text('Export shop data (CSV)'), onPressed: widget.onExport),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              icon: const Icon(Icons.person_remove_outlined),
              label: const Text('Delete shop and account'),
              onPressed: () => showDeleteAccountDialog(context, widget.auth, onExport: widget.onExport),
            ),
            ],
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
              'Afterwards you are signed out and can set up the business again with your email. '
              'Other people\'s logins stay registered in Firebase Authentication; delete them in the Firebase console '
              'if you want to reuse their emails.',
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
