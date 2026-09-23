import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/notifications/domain/entities/app_notification.dart';

abstract class NotificationRepository {
  void notify(String title, String body, {UserRole? role, String? userId});

  /// Newest first.
  List<AppNotification> notificationsFor(AppUser user);

  int unreadCountFor(AppUser user);

  void markAllRead(AppUser user);
}
