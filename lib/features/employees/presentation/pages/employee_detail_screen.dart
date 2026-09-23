import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/employees/presentation/controllers/employees_controller.dart';

String _permissionLabel(Permission p) {
  final s = p.name;
  final buffer = StringBuffer();
  for (final ch in s.split('')) {
    if (ch == ch.toUpperCase() && ch != ch.toLowerCase()) buffer.write(' ');
    buffer.write(ch);
  }
  final label = buffer.toString();
  return label[0].toUpperCase() + label.substring(1);
}

class EmployeeDetailScreen extends StatefulWidget {
  const EmployeeDetailScreen({super.key, required this.controller, required this.auth, required this.user});

  final EmployeesController controller;
  final AuthController auth;
  final AppUser user;

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  final Set<Permission> _permissions = {};

  @override
  void initState() {
    super.initState();
    _permissions.addAll(widget.user.permissions);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      appBar: AppBar(title: Text(user.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Phone'), subtitle: Text(user.phone)),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Role'), subtitle: Text(user.role.name)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            value: user.active,
            onChanged: (v) {
              widget.controller.setActive(user, v, userName: widget.auth.currentUser?.name ?? '');
              setState(() {});
            },
          ),
          const Divider(height: 32),
          Text('Permissions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...Permission.values.map((p) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(_permissionLabel(p)),
                value: _permissions.contains(p),
                onChanged: (checked) => setState(() {
                  if (checked ?? false) {
                    _permissions.add(p);
                  } else {
                    _permissions.remove(p);
                  }
                }),
              )),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              widget.controller.updatePermissions(user, _permissions, userName: widget.auth.currentUser?.name ?? '');
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissions updated')));
            },
            child: const Text('Save Permissions'),
          ),
        ],
      ),
    );
  }
}
