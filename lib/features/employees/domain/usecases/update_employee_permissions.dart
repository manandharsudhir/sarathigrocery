import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';

class UpdateEmployeePermissions {
  UpdateEmployeePermissions(this._users, this._audit);

  final UserRepository _users;
  final AuditRepository _audit;

  void call(AppUser user, Set<Permission> permissions, {required String userName}) {
    user.customPermissions = permissions;
    _users.update(user);
    _audit.record(userName, 'Employee permission changed', 'User', entityId: user.id, newValue: permissions.map((p) => p.name).join(', '));
  }
}
