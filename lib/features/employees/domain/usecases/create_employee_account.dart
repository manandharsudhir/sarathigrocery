import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';

class CreateEmployeeAccount {
  CreateEmployeeAccount(this._users, this._auth, this._audit);

  final UserRepository _users;
  final AuthRepository _auth;
  final AuditRepository _audit;

  /// Returns an error message, or null on success.
  Future<String?> call({required String name, required String phone, required String password, required UserRole role, required String userName}) async {
    if (role == UserRole.owner || role == UserRole.customer) return 'Employees can only be accountants, shop employees or delivery staff.';
    final problem = passwordProblem(password);
    if (problem != null) return problem;
    if (_users.findByPhone(phone) != null) return 'Phone number $phone is already registered.';
    final id = await _auth.createAccount(phone, password);
    if (id == null) return 'Phone number $phone is already registered.';
    _users.add(AppUser(id: id, name: name, phone: phone, role: role));
    _audit.record(userName, 'Employee added', 'User', entityId: id, newValue: name);
    return null;
  }
}
