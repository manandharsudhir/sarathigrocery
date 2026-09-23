import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';

Future<void> showChangePasswordDialog(BuildContext context, AuthController auth) {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  return showDialog(
    context: context,
    builder: (context) => _AsyncFormDialog(
      title: 'Change Password',
      actionLabel: 'Change',
      fields: [
        TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
        TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password (min 8 characters)')),
        TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
      ],
      onSubmit: () async {
        if (next.text != confirm.text) throw AuthException('Passwords do not match.');
        await auth.changePassword(current.text, next.text);
        return 'Password changed.';
      },
    ),
  );
}

/// Sends an OTP to the user's own number and links it to their login,
/// which is what makes OTP password reset possible later.
Future<void> showVerifyPhoneDialog(BuildContext context, AuthController auth) {
  final code = TextEditingController();
  String? verificationId;
  return showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => _AsyncFormDialog(
        title: 'Verify ${auth.currentUser!.phone}',
        actionLabel: verificationId == null ? 'Send Code' : 'Verify',
        fields: [
          if (verificationId == null)
            const Text('We will text a one-time code to this number. Once verified, you can reset a forgotten password by SMS.')
          else
            TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6-digit code')),
        ],
        onSubmit: () async {
          if (verificationId == null) {
            final id = await auth.startPhoneVerification();
            setState(() => verificationId = id);
            return null;
          }
          await auth.completePhoneVerification(verificationId!, code.text.trim());
          return 'Phone verified.';
        },
      ),
    ),
  );
}

/// Dialog whose action is async: shows progress, inline errors, and closes
/// with a confirmation snackbar when [onSubmit] returns a message (null =
/// stay open for the next step).
class _AsyncFormDialog extends StatefulWidget {
  const _AsyncFormDialog({required this.title, required this.actionLabel, required this.fields, required this.onSubmit});

  final String title;
  final String actionLabel;
  final List<Widget> fields;
  final Future<String?> Function() onSubmit;

  @override
  State<_AsyncFormDialog> createState() => _AsyncFormDialogState();
}

class _AsyncFormDialogState extends State<_AsyncFormDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await widget.onSubmit();
      if (done != null && mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(SnackBar(content: Text(done)));
        return;
      }
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Something went wrong: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...widget.fields,
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}
