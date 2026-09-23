import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.date,
    required this.title,
    required this.body,
    this.read = false,
    this.targetRole,
    this.targetUserId,
  });

  final String id;
  final DateTime date;
  final String title;
  final String body;
  bool read;

  /// If set, only users with this role see the notification.
  final UserRole? targetRole;

  /// If set, only this specific user sees the notification (overrides [targetRole] scoping).
  final String? targetUserId;
}
