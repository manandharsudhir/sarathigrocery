import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
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

/// Play Store account deletion. Shops this login owns are deleted with it
/// (listed, and the first one's name must be typed); [onExport] offers a
/// data export first. Ends signed out on the login screen.
Future<void> showDeleteAccountDialog(BuildContext context, AuthController auth, {Future<void> Function()? onExport}) async {
  final List<String> owned;
  try {
    owned = await auth.ownedShopNames();
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No internet connection. Connect and try again.')));
    return;
  }
  if (!context.mounted) return;
  final name = TextEditingController();
  final password = TextEditingController();
  final navigator = Navigator.of(context);
  return showDialog(
    context: context,
    builder: (context) => _AsyncFormDialog(
      title: owned.isEmpty ? 'Delete your account?' : 'Delete shop and account?',
      actionLabel: 'Delete for good',
      fields: [
        if (owned.isEmpty)
          const Text('Your login is deleted. In each shop you work for, your profile becomes "$kFormerStaffName" and is switched off. '
              'The shop keeps its records (sales, payments), which still show your name.')
        else ...[
          Text('This permanently deletes, for everyone, ${owned.length == 1 ? 'the shop' : 'these shops'}: ${owned.join(', ')} — '
              'customers and balances, sales, payments, ledgers, stock and staff profiles — and then your login. '
              'There is no backup and no undo.'),
          if (onExport != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(icon: const Icon(Icons.download_outlined), label: const Text('Export this shop first'), onPressed: onExport),
            ),
          const SizedBox(height: 8),
          Text('Type "${owned.first}" to confirm:'),
          TextField(controller: name),
        ],
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Your password')),
      ],
      onSubmit: () async {
        await auth.deleteAccount(password: password.text, typedShopName: name.text);
        navigator.popUntil((route) => route.isFirst);
        return null;
      },
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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...widget.fields,
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}
