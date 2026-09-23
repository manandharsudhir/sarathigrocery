import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/employees/domain/usecases/create_employee_account.dart';
import 'package:sarathigrocery/features/employees/domain/usecases/set_employee_active.dart';
import 'package:sarathigrocery/features/employees/domain/usecases/update_employee_permissions.dart';

class EmployeesController extends ChangeNotifier {
  EmployeesController(this._users, AuthRepository auth, AuditRepository audit)
      : _createAccount = CreateEmployeeAccount(_users, auth, audit),
        _setActive = SetEmployeeActive(_users, audit),
        _updatePermissions = UpdateEmployeePermissions(_users, audit);

  final UserRepository _users;
  final CreateEmployeeAccount _createAccount;
  final SetEmployeeActive _setActive;
  final UpdateEmployeePermissions _updatePermissions;

  List<AppUser> get employees => _users.users.where((u) => u.role != UserRole.customer).toList();

  /// Returns an error message, or null on success.
  Future<String?> createEmployeeAccount({required String name, required String phone, required String password, required UserRole role, required String userName}) async {
    try {
      final error = await _createAccount(name: name, phone: phone, password: password, role: role, userName: userName);
      if (error != null) return error;
    } on AuthException catch (e) {
      return e.message;
    }
    notifyListeners();
    AppSignal.instance.ping();
    return null;
  }

  void setActive(AppUser user, bool active, {required String userName}) {
    _setActive(user, active, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }

  void updatePermissions(AppUser user, Set<Permission> permissions, {required String userName}) {
    _updatePermissions(user, permissions, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
