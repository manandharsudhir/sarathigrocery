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
  EmployeesController(this._users, AuthRepository auth, this._audit)
      : _createAccount = CreateEmployeeAccount(_users, auth, _audit),
        _setActive = SetEmployeeActive(_users, _audit),
        _updatePermissions = UpdateEmployeePermissions(_users, _audit);

  final AuditRepository _audit;

  final UserRepository _users;
  final CreateEmployeeAccount _createAccount;
  final SetEmployeeActive _setActive;
  final UpdateEmployeePermissions _updatePermissions;

  List<AppUser> get employees => _users.users;

  /// Returns an error message, or null on success. [existingLogin]: the
  /// email already had a login, which was added to this shop as is.
  Future<({String? error, bool existingLogin})> createEmployeeAccount({required String name, required String email, required String phone, required String password, required UserRole role, required String userName, bool byFounder = false}) async {
    try {
      final result = await _createAccount(name: name, email: email, phone: phone, password: password, role: role, userName: userName, byFounder: byFounder);
      if (result.error != null) return result;
      notifyListeners();
      AppSignal.instance.ping();
      return result;
    } on AuthException catch (e) {
      return (error: e.message, existingLogin: false);
    }
  }

  void setActive(AppUser user, bool active, {required String userName}) {
    _setActive(user, active, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// Founder only: hands the founding owner role to an active co-owner
  /// (e.g. before the founder deletes their account).
  void handOverFounding(AppUser coOwner, {required AppUser by}) {
    if (coOwner.role != UserRole.owner || !coOwner.active || coOwner.id == by.id) throw StateError('Only an active co-owner can become founding owner.');
    _users.setFounder(coOwner.id);
    _audit.record(by.name, 'Founding owner handed over', 'User', entityId: coOwner.id, newValue: coOwner.name);
    notifyListeners();
    AppSignal.instance.ping();
  }

  void updatePermissions(AppUser user, Set<Permission> permissions, {required String userName}) {
    _updatePermissions(user, permissions, userName: userName);
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// "Can handle cash & accounts": adds or removes [cashPermissions] through
  /// the same per-user override as [updatePermissions].
  void setCashAccess(AppUser user, bool on, {required String userName}) => updatePermissions(
        user,
        on ? {...user.permissions, ...cashPermissions} : user.permissions.difference(cashPermissions),
        userName: userName,
      );
}
