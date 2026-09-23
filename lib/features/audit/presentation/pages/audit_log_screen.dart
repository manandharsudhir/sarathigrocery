import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';

class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key, required this.repository});

  final AuditRepository repository;

  @override
  Widget build(BuildContext context) {
    final entries = repository.entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Log')),
      body: entries.isEmpty
          ? const Center(child: Text('No activity recorded yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final e = entries[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${e.action} · ${e.entity}'),
                  subtitle: Text(
                    '${e.userName} · ${formatDate(e.date)}'
                    '${e.oldValue.isNotEmpty ? '\n${e.oldValue} → ${e.newValue}' : (e.newValue.isNotEmpty ? '\n${e.newValue}' : '')}',
                  ),
                  isThreeLine: e.oldValue.isNotEmpty || e.newValue.isNotEmpty,
                );
              },
            ),
    );
  }
}
