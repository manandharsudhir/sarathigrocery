class AuditLogEntry {
  AuditLogEntry({
    required this.id,
    required this.date,
    required this.userName,
    required this.action,
    required this.entity,
    this.entityId = '',
    this.oldValue = '',
    this.newValue = '',
  });

  final String id;
  final DateTime date;
  final String userName;
  final String action;
  final String entity;
  final String entityId;
  final String oldValue;
  final String newValue;
}
