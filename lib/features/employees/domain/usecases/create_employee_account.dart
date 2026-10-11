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

  /// Adds [email] to this shop: a new login with [password], or — if the
  /// email already has a login (e.g. staff at another shop) — that login,
  /// which keeps its own password ([password] is then unused).
  /// [existingLogin] tells which happened.
  Future<({String? error, bool existingLogin})> call({required String name, required String email, required String phone, required String password, required UserRole role, required String userName, bool byFounder = false}) async {
    ({String? error, bool existingLogin}) fail(String error) => (error: error, existingLogin: false);
    if (role == UserRole.owner && !byFounder) return fail('Only the founding owner adds co-owners.');
    email = normalizeEmail(email);
    final badEmail = emailProblem(email);
    if (badEmail != null) return fail(badEmail);
    if (_users.findByEmail(email) != null) return fail('$email is already in this shop.');
    var id = await _users.accountIdForEmail(email);
    final existingLogin = id != null;
    if (id == null) {
      final problem = passwordProblem(password);
      if (problem != null) return fail(problem);
      id = await _auth.createAccount(email, password);
      // A login that never signed in hasn't registered its email yet.
      if (id == null) return fail('$email already has a login. Ask them to sign in once, then add them again.');
    }
    _users.add(AppUser(id: id, name: name, phone: phone, email: email, role: role));
    _audit.record(userName, role == UserRole.owner ? 'Co-owner added' : 'Employee added', 'User', entityId: id, newValue: name);
    return (error: null, existingLogin: existingLogin);
  }
}
