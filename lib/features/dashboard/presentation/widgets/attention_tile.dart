import 'package:flutter/material.dart';

/// A single "something needs you" row: plain-language problem on the left,
/// the action that fixes it on the right.
class AttentionTile extends StatelessWidget {
  const AttentionTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Text(actionLabel, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                  Icon(Icons.chevron_right, size: 18, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
