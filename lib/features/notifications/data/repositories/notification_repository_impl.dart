import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/notifications/domain/entities/app_notification.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final _notifications = SyncedCollection<AppNotification>(
    'notifications',
    idOf: (n) => n.id,
    toJson: (n) => {
      'date': toMillis(n.date),
      'title': n.title,
      'body': n.body,
      'read': n.read,
      'targetRole': n.targetRole?.name,
      'targetUserId': n.targetUserId,
    },
    fromJson: (j) => AppNotification(
      id: j['id'],
      date: fromMillis(j['date']),
      title: j['title'] ?? '',
      body: j['body'] ?? '',
      read: j['read'] ?? false,
      targetRole: j['targetRole'] == null ? null : UserRole.values.byName(j['targetRole']),
      targetUserId: j['targetUserId'],
    ),
    merge: (n, j) => n.read = j['read'] ?? false,
  );

  List<SyncedCollection<Object?>> get collections => [_notifications];

  @override
  void notify(String title, String body, {UserRole? role, String? userId}) {
    _notifications.add(AppNotification(
      id: nextId('N'),
      date: DateTime.now(),
      title: title,
      body: body,
      targetRole: role,
      targetUserId: userId,
    ));
  }

  @override
  List<AppNotification> notificationsFor(AppUser user) => _notifications.items.where((n) {
        if (n.targetUserId != null) return n.targetUserId == user.id;
        if (n.targetRole != null) return n.targetRole == user.role;
        return true;
      }).toList().reversed.toList();

  @override
  int unreadCountFor(AppUser user) => notificationsFor(user).where((n) => !n.read).length;

  @override
  void markAllRead(AppUser user) {
    for (final n in notificationsFor(user).where((n) => !n.read)) {
      n.read = true;
      _notifications.save(n);
    }
  }
}
