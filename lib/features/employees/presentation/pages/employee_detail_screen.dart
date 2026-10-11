import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
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
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Email'), subtitle: Text(user.email)),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Phone'), subtitle: Text(user.phone)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Role'),
            subtitle: Text(user.role != UserRole.owner ? user.role.name : (user.id == widget.auth.founderId ? 'Founding owner' : 'Co-owner')),
          ),
          if (user.role != UserRole.owner || (widget.auth.isFounder && user.id != widget.auth.founderId))
            SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            value: user.active,
            onChanged: (v) {
              widget.controller.setActive(user, v, userName: widget.auth.currentUser?.name ?? '');
              setState(() {});
            },
          ),
          if (user.role == UserRole.owner && widget.auth.isFounder && user.id != widget.auth.founderId && user.active)
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Make founding owner'),
              onPressed: () => _handOver(user),
            ),
          if (user.role == UserRole.employee)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Can handle cash & accounts'),
              subtitle: const Text('Count cash in, expenses, purchases, suppliers, reports and credit terms'),
              value: user.can(Permission.reconcileCash),
              onChanged: (v) {
                widget.controller.setCashAccess(user, v, userName: widget.auth.currentUser?.name ?? '');
                setState(() => _permissions
                  ..clear()
                  ..addAll(user.permissions));
              },
            ),
          if (user.role == UserRole.employee)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Can sell below minimum price'),
              subtitle: const Text('Clearance and damaged stock. Every such sale is logged and you are notified.'),
              value: user.can(Permission.sellBelowMinimum),
              onChanged: (v) {
                final current = user.permissions;
                widget.controller.updatePermissions(
                  user,
                  v ? {...current, Permission.sellBelowMinimum} : ({...current}..remove(Permission.sellBelowMinimum)),
                  userName: widget.auth.currentUser?.name ?? '',
                );
                setState(() => _permissions
                  ..clear()
                  ..addAll(user.permissions));
              },
            ),
          if (user.role != UserRole.owner) ...[
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
        ],
      ),
    );
  }

  Future<void> _handOver(AppUser coOwner) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Make ${coOwner.name} the founding owner?'),
        content: const Text('They alone will be able to erase the shop, add or remove co-owners and hand the role on. You stay a co-owner.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hand over')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.controller.handOverFounding(coOwner, by: widget.auth.currentUser!);
    widget.auth.founderId = coOwner.id;
    setState(() {});
  }
}
