import 'package:flutter/material.dart';

/// Centered "nothing here yet" message, with a button for the obvious next
/// step when there is one. Pass [onAction] as null when the user lacks the
/// permission, so the button is hidden.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
