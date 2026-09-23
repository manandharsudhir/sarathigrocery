import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/profile_screen.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';
import 'package:sarathigrocery/features/notifications/presentation/pages/notifications_screen.dart';

List<Widget> dashboardActions(BuildContext context, AuthController auth, NotificationRepository notifications) {
  final user = auth.currentUser;
  final unread = user == null ? 0 : notifications.unreadCountFor(user);
  return [
    IconButton(
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: user == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(currentUser: user, repository: notifications))),
    ),
    IconButton(
      icon: const Icon(Icons.account_circle_outlined),
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(auth: auth))),
    ),
  ];
}
