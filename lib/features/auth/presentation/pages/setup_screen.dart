import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';

/// First-run: creates the business and its owner account.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _business = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _sampleData = false;
  String? _error;

  Future<void> _submit() async {
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() => _error = null);
    final ok = await widget.auth.setUpBusiness(
      businessName: _business.text,
      ownerName: _owner.text,
      phone: _phone.text.trim(),
      password: _password.text,
      includeSampleData: _sampleData,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() => _error = widget.auth.loginError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Set Up Your Business')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('This creates your business and your owner account. You can add staff and customers afterwards.'),
            const SizedBox(height: 16),
            TextField(controller: _business, decoration: const InputDecoration(labelText: 'Business name', prefixIcon: Icon(Icons.storefront))),
            const SizedBox(height: 12),
            TextField(controller: _owner, decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Your phone number', prefixIcon: Icon(Icons.phone))),
            const SizedBox(height: 12),
            TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min 8 characters)', prefixIcon: Icon(Icons.lock_outline))),
            const SizedBox(height: 12),
            TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline))),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _sampleData,
              onChanged: (v) => setState(() => _sampleData = v ?? false),
              title: const Text('Start with sample products, customers and suppliers'),
              subtitle: const Text('Handy for trying the app; edit or ignore them later.'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: widget.auth.busy ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: widget.auth.busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Business'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
