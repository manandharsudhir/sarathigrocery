import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/notifications/domain/repositories/notification_repository.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.currentUser, required this.repository});

  final AppUser currentUser;
  final NotificationRepository repository;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.repository.markAllRead(widget.currentUser);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.repository.notificationsFor(widget.currentUser);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: items.isEmpty
          ? const Center(child: Text('No notifications yet.'))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = items[index];
                return ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(n.title),
                  subtitle: Text(n.body),
                  trailing: Text(formatDate(n.date), style: const TextStyle(fontSize: 12)),
                );
              },
            ),
    );
  }
}
