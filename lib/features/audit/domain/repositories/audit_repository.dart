import 'package:sarathigrocery/features/audit/domain/entities/audit_log_entry.dart';

abstract class AuditRepository {
  void record(String userName, String action, String entity, {String entityId = '', String oldValue = '', String newValue = ''});

  /// Newest first.
  List<AuditLogEntry> get entries;
}
