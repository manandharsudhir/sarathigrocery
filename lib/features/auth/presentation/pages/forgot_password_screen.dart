import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';

/// OTP password reset: phone → SMS code → new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _verificationId;
  bool _done = false;
  bool _busy = false;
  String? _error;

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
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

  Future<void> _sendCode() => _guard(() async {
        if (_phone.text.trim().isEmpty) throw AuthException('Enter your phone number.');
        _verificationId = await widget.auth.startPasswordReset(_phone.text.trim());
      });

  Future<void> _reset() => _guard(() async {
        if (_password.text != _confirm.text) throw AuthException('Passwords do not match.');
        await widget.auth.completePasswordReset(_verificationId!, _code.text.trim(), _password.text);
        _done = true;
      });

  @override
  Widget build(BuildContext context) {
    final sent = _verificationId != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: _done
            ? [
                const Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
                const SizedBox(height: 16),
                const Text('Your password has been changed. Log in with the new password.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back to Log In')),
              ]
            : [
                const Text('We will send a one-time code by SMS to your registered phone number. This works if you verified your phone under Account.'),
                const SizedBox(height: 16),
                TextField(
                  controller: _phone,
                  enabled: !sent,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone)),
                ),
                if (sent) ...[
                  const SizedBox(height: 12),
                  TextField(controller: _code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6-digit code', prefixIcon: Icon(Icons.sms_outlined))),
                  const SizedBox(height: 12),
                  TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'New password (min 8 characters)', prefixIcon: Icon(Icons.lock_outline))),
                  const SizedBox(height: 12),
                  TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_outline))),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : (sent ? _reset : _sendCode),
                  child: Text(sent ? 'Reset Password' : 'Send Code'),
                ),
                if (sent)
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _verificationId = null),
                    child: const Text('Use a different number / resend'),
                  ),
              ],
      ),
    );
  }
}
