import 'package:flutter/material.dart';

class MoreMenuItem {
  const MoreMenuItem({required this.icon, required this.label, required this.builder});

  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

class MoreMenuScreen extends StatelessWidget {
  const MoreMenuScreen({super.key, required this.items});

  final List<MoreMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            leading: Icon(item.icon),
            title: Text(item.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: item.builder)),
          );
        },
      ),
    );
  }
}
