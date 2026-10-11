import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';

enum _Step { account, verify, shop }

/// Sign-up: email + password → verify email → shop name. Opened while
/// signed in (Account → Set up another shop, or a login with no shop yet),
/// it starts at whichever step is left.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _business = TextEditingController();
  late final _owner = TextEditingController(text: widget.auth.currentUser?.name);
  late final _phone = TextEditingController(text: widget.auth.currentUser?.phone);
  late _Step _step = !widget.auth.signedIn
      ? _Step.account
      : widget.auth.emailVerified
          ? _Step.shop
          : _Step.verify;
  bool _sampleData = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Something went wrong: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _next() => _guard(() async {
        switch (_step) {
          case _Step.account:
            if (_password.text != _confirm.text) throw AuthException('Passwords do not match.');
            await widget.auth.signUp(_email.text, _password.text);
            _step = _Step.verify;
          case _Step.verify:
            await widget.auth.confirmEmailVerified();
            _step = _Step.shop;
          case _Step.shop:
            if (_business.text.trim().isEmpty || _owner.text.trim().isEmpty || _phone.text.trim().isEmpty) throw AuthException('Fill in every field.');
            final ok = await widget.auth.setUpBusiness(businessName: _business.text, ownerName: _owner.text, phone: _phone.text, includeSampleData: _sampleData);
            if (!ok) throw AuthException(widget.auth.loginError ?? 'Could not create the shop.');
            if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });

  Future<void> _resend() => _guard(() async {
        await widget.auth.resendVerificationEmail();
        _notice = 'Sent again.';
      });

  @override
  Widget build(BuildContext context) {
    final fields = switch (_step) {
      _Step.account => [
          const Text('You log in with this email and password. We send a link to check the email is yours.'),
          const SizedBox(height: 16),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min 8 characters)', prefixIcon: Icon(Icons.lock_outline))),
          const SizedBox(height: 12),
          TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline))),
        ],
      _Step.verify => [
          Text('We sent a link to ${widget.auth.email ?? 'your email'}. Open it (check spam too), then come back here.'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _busy ? null : _resend, child: const Text('Resend email')),
          ),
        ],
      _Step.shop => [
          const Text('You can add staff and customers afterwards.'),
          const SizedBox(height: 16),
          TextField(controller: _business, decoration: const InputDecoration(labelText: 'Shop name', prefixIcon: Icon(Icons.storefront))),
          const SizedBox(height: 12),
          TextField(controller: _owner, decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Your phone number', prefixIcon: Icon(Icons.phone))),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _sampleData,
            onChanged: (v) => setState(() => _sampleData = v ?? false),
            title: const Text('Start with sample products, customers and suppliers'),
            subtitle: const Text('Handy for trying the app; edit or ignore them later.'),
          ),
        ],
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up a New Shop'),
        actions: [
          // Shown as the home screen for a login with no shop yet.
          if (widget.auth.needsSetup) TextButton(onPressed: _busy ? null : widget.auth.logout, child: const Text('Log out')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ...fields,
          if (_notice != null) ...[
            const SizedBox(height: 8),
            Text(_notice!, style: const TextStyle(color: Colors.green)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _next,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(switch (_step) { _Step.account => 'Sign Up', _Step.verify => 'I\'ve verified', _Step.shop => 'Create Shop' }),
            ),
          ),
        ],
      ),
    );
  }
}
