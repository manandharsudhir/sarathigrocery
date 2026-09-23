import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/employees/presentation/controllers/employees_controller.dart';
import 'package:sarathigrocery/features/employees/presentation/pages/employee_detail_screen.dart';

class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key, required this.controller, required this.auth});

  final EmployeesController controller;
  final AuthController auth;

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
                  subtitle: Text('${user.role.name} · ${user.phone}'),
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
    final name = TextEditingController();
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
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 8),
              TextField(controller: password, decoration: const InputDecoration(labelText: 'Temporary password (min 8 characters)')),
              const SizedBox(height: 8),
              DropdownButtonFormField<UserRole>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: UserRole.employee, child: Text('Shop Employee')),
                  DropdownMenuItem(value: UserRole.accountant, child: Text('Accountant')),
                ],
                onChanged: (v) => setSheetState(() => role = v ?? role),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (name.text.trim().isEmpty || phone.text.trim().isEmpty || password.text.isEmpty) return;
                    final error = await controller.createEmployeeAccount(
                      name: name.text.trim(),
                      phone: phone.text.trim(),
                      password: password.text,
                      role: role,
                      userName: auth.currentUser?.name ?? '',
                    );
                    if (!context.mounted) return;
                    if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                    } else {
                      Navigator.pop(context);
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
}
