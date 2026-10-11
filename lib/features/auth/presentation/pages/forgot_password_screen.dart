import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';

/// Password reset: emails a reset link; the new password is set on the
/// page that link opens.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.sendPasswordReset(_email.text);
      _sent = true;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Something went wrong: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_sent)
            Text('If ${normalizeEmail(_email.text)} has a login, a reset link is on its way. Open it (check spam too), choose a new password, then log in.')
          else ...[
            const Text('We will email you a link to choose a new password.'),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              onSubmitted: (_) => _send(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : (_sent ? () => Navigator.pop(context) : _send),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_sent ? 'Back to Log In' : 'Send Reset Link'),
            ),
          ),
        ],
      ),
    );
  }
}
