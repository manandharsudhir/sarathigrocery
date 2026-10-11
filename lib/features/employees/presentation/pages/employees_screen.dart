import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/accounting/presentation/controllers/accounting_controller.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/accounting_forms.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/pages/profile_screen.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/employees/presentation/controllers/employees_controller.dart';
import 'package:sarathigrocery/features/employees/presentation/pages/employee_detail_screen.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/presentation/controllers/settings_controller.dart';

class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key, required this.controller, required this.auth, required this.settings, required this.accounting});

  final EmployeesController controller;
  final AuthController auth;
  final SettingsController settings;
  final AccountingController accounting;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final employees = controller.employees;
        return Scaffold(
          appBar: AppBar(title: const Text('Employees')),
          body: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: employees.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = employees[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
                child: ListTile(
                  title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${user.role == UserRole.owner ? (user.id == auth.founderId ? 'Founding owner' : 'Co-owner') : roleLabel(user.role)}'
                      '${user.can(Permission.reconcileCash) && user.role != UserRole.owner ? ' · cash & accounts' : ''} · ${user.phone}'),
                  trailing: user.active ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.pause_circle_outline, color: Colors.grey),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeeDetailScreen(controller: controller, auth: auth, user: user))),
                ),
              );
            },
          ),
          floatingActionButton: FloatingActionButton.extended(heroTag: null, 
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add Employee'),
            onPressed: () => _showAddSheet(context, controller, auth),
          ),
        );
      },
    );
  }

  void _showAddSheet(BuildContext context, EmployeesController controller, AuthController auth) {
    final screen = context;
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    var role = UserRole.employee;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Employee', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email (used to log in)')),
              const SizedBox(height: 8),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 8),
              TextField(controller: password, decoration: const InputDecoration(labelText: 'Temporary password (min 8 characters)', helperText: 'Not used if this email already has a login')),
              const SizedBox(height: 8),
              DropdownButtonFormField<UserRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  const DropdownMenuItem(value: UserRole.employee, child: Text('Staff')),
                  const DropdownMenuItem(value: UserRole.delivery, child: Text('Delivery')),
                  // Co-owners have every owner right except erasing the shop.
                  if (auth.isFounder) const DropdownMenuItem(value: UserRole.owner, child: Text('Co-owner (partner)')),
                ],
                onChanged: (v) => setSheetState(() => role = v ?? role),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (name.text.trim().isEmpty || email.text.trim().isEmpty || phone.text.trim().isEmpty) return;
                    final result = await controller.createEmployeeAccount(
                      name: name.text.trim(),
                      email: email.text,
                      phone: phone.text.trim(),
                      password: password.text,
                      role: role,
                      userName: auth.currentUser?.name ?? '',
                      byFounder: auth.isFounder,
                    );
                    if (!context.mounted) return;
                    final messenger = ScaffoldMessenger.of(context);
                    if (result.error != null) {
                      messenger.showSnackBar(SnackBar(content: Text(result.error!)));
                    } else {
                      Navigator.pop(context);
                      if (result.existingLogin) {
                        messenger.showSnackBar(const SnackBar(content: Text('Added — they sign in with their existing password.')));
                      }
                      if (role == UserRole.owner && screen.mounted) {
                        // A partner also needs a share of the business.
                        Navigator.push(screen, MaterialPageRoute(builder: (_) => AccountsSetupScreen(controller: accounting, auth: auth, addOwner: name.text.trim())));
                      } else if (screen.mounted) {
                        _offerSafeguards(screen);
                      }
                    }
                  },
                  child: const Text('Add Employee'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// After the owner adds the first staff account, while every safeguard
  /// is off: one tap turns them all on.
  void _offerSafeguards(BuildContext context) {
    final firstStaff = controller.employees.where((u) => u.role != UserRole.owner).length == 1;
    if (auth.currentUser?.role != UserRole.owner || !firstStaff || Safeguard.values.any(settings.guards)) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn on safeguards for staff?'),
        content: Text('${[for (final g in Safeguard.values) '• ${g.label}'].join('\n')}\n\nYou can change these any time in Settings → Safeguards.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
          FilledButton(
            onPressed: () {
              settings.enableAllSafeguards();
              Navigator.pop(context);
            },
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
  }
}
