import 'package:flutter/material.dart';

/// Asks why an entry is being reversed or corrected. Returns the reason, or
/// null if cancelled. [message] says what will happen.
Future<String?> askReason(BuildContext context, {required String title, required String message, String action = 'Reverse'}) {
  final reason = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'What was wrong? (required)'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
          FilledButton(
            onPressed: reason.text.trim().isEmpty ? null : () => Navigator.pop(context, reason.text.trim()),
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}

/// "Looks like a duplicate" before saving. [blocked]: a sure duplicate
/// (same supplier bill number) that only [canOverride] (the owner) may save.
/// Returns true to save anyway.
Future<bool> confirmNotDuplicate(BuildContext context, String message, {bool blocked = false, bool canOverride = true}) async {
  final saveAllowed = !blocked || canOverride;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(blocked ? 'Already entered' : 'Possible double entry'),
      content: Text(blocked && !canOverride ? '$message\n\nOnly the owner can save it again.' : message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Don\'t save')),
        if (saveAllowed) TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save anyway')),
      ],
    ),
  );
  return ok ?? false;
}

/// A faded "Reversed" line under an entry that was undone.
class ReversedNote extends StatelessWidget {
  const ReversedNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12));
}
