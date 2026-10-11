import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';

/// After login, for a login that works at 2+ shops.
class ShopPickerScreen extends StatelessWidget {
  const ShopPickerScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a shop'),
        actions: [TextButton(onPressed: auth.logout, child: const Text('Log out'))],
      ),
      body: ListView(
        children: [
          if (auth.loginError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(auth.loginError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (auth.busy) const LinearProgressIndicator(),
          for (final shop in auth.shops)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(shop.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: auth.busy ? null : () => auth.pickShop(shop.id),
            ),
        ],
      ),
    );
  }
}
