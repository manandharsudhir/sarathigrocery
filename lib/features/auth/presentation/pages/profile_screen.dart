import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/account_security_dialogs.dart';

String roleLabel(UserRole role) {
  switch (role) {
    case UserRole.owner:
      return 'Owner / Admin';
    case UserRole.accountant:
      return 'Accountant';
    case UserRole.employee:
      return 'Shop Employee';
    case UserRole.delivery:
      return 'Delivery';
    case UserRole.customer:
      return 'Wholesale Customer';
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CircleAvatar(radius: 32, child: Text(user.name.isNotEmpty ? user.name[0] : '?')),
          const SizedBox(height: 12),
          Text(user.name, style: Theme.of(context).textTheme.titleLarge),
          Text(roleLabel(user.role)),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Phone'),
            subtitle: Text(user.phone),
            trailing: ListenableBuilder(
              listenable: auth,
              builder: (context, _) => auth.phoneVerified
                  ? const Chip(avatar: Icon(Icons.verified, size: 18, color: Colors.green), label: Text('Verified'))
                  : TextButton(onPressed: () => showVerifyPhoneDialog(context, auth), child: const Text('Verify')),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change Password'),
            onTap: () => showChangePasswordDialog(context, auth),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log Out', style: TextStyle(color: Colors.red)),
            onTap: () {
              auth.logout();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
    );
  }
}
