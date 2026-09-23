import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/audit/domain/entities/audit_log_entry.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';

class AuditRepositoryImpl implements AuditRepository {
  final _entries = SyncedCollection<AuditLogEntry>(
    'auditLog',
    idOf: (e) => e.id,
    toJson: (e) => {
      'date': toMillis(e.date),
      'userName': e.userName,
      'action': e.action,
      'entity': e.entity,
      'entityId': e.entityId,
      'oldValue': e.oldValue,
      'newValue': e.newValue,
    },
    fromJson: (j) => AuditLogEntry(
      id: j['id'],
      date: fromMillis(j['date']),
      userName: j['userName'] ?? '',
      action: j['action'] ?? '',
      entity: j['entity'] ?? '',
      entityId: j['entityId'] ?? '',
      oldValue: j['oldValue'] ?? '',
      newValue: j['newValue'] ?? '',
    ),
  );

  List<SyncedCollection<Object?>> get collections => [_entries];

  @override
  void record(String userName, String action, String entity, {String entityId = '', String oldValue = '', String newValue = ''}) {
    _entries.add(AuditLogEntry(
      id: nextId('AU'),
      date: DateTime.now(),
      userName: userName,
      action: action,
      entity: entity,
      entityId: entityId,
      oldValue: oldValue,
      newValue: newValue,
    ));
  }

  @override
  List<AuditLogEntry> get entries => _entries.items.reversed.toList();
}
