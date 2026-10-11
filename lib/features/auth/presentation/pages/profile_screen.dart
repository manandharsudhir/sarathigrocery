import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/account_security_dialogs.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/setup_screen.dart';

String roleLabel(UserRole role) {
  switch (role) {
    case UserRole.owner:
      return 'Owner / Admin';
    case UserRole.employee:
      return 'Staff';
    case UserRole.delivery:
      return 'Delivery';
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
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: Text(user.email),
          ),
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('Phone'),
            subtitle: Text(user.phone),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('Change Password'),
            onTap: () => showChangePasswordDialog(context, auth),
          ),
          if (user.role == UserRole.owner)
            ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: const Text('Set up another shop'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SetupScreen(auth: auth))),
            ),
          if (auth.shops.length > 1)
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Switch shop'),
              onTap: () {
                auth.switchShop();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          if (user.role == UserRole.owner && !auth.isFounder)
            ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: const Text('Leave this shop'),
              subtitle: const Text('Your co-owner login is switched off here. Your capital stays in the books until it is paid out.'),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Leave this shop?'),
                    content: const Text('Only the founding owner can let you back in.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
                    ],
                  ),
                );
                if (ok != true || !context.mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
                await auth.leaveShop();
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_remove_outlined),
            title: const Text('Delete my account'),
            subtitle: auth.isFounder ? const Text('Deletes the shops you founded. To export first, use Settings → Danger zone') : null,
            onTap: () => showDeleteAccountDialog(context, auth),
          ),
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
