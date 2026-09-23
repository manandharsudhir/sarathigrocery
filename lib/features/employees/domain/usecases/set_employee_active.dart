import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';

class SetEmployeeActive {
  SetEmployeeActive(this._users, this._audit);

  final UserRepository _users;
  final AuditRepository _audit;

  void call(AppUser user, bool active, {required String userName}) {
    user.active = active;
    _users.update(user);
    _audit.record(userName, active ? 'Employee activated' : 'Employee deactivated', 'User', entityId: user.id);
  }
}
