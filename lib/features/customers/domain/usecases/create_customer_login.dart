import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';

/// Gives a business customer their own app login (to browse and order),
/// linked to their [Customer] record. Returns an error message, or null.
class CreateCustomerLogin {
  CreateCustomerLogin(this._users, this._auth, this._audit);

  final UserRepository _users;
  final AuthRepository _auth;
  final AuditRepository _audit;

  Future<String?> call(Customer customer, {required String phone, required String password, required String userName}) async {
    if (_users.userForCustomer(customer.id) != null) return '${customer.name} already has a login.';
    final problem = passwordProblem(password);
    if (problem != null) return problem;
    if (_users.findByPhone(phone) != null) return 'Phone number $phone is already registered.';
    final id = await _auth.createAccount(phone, password);
    if (id == null) return 'Phone number $phone is already registered.';
    _users.add(AppUser(id: id, name: customer.name, phone: phone, role: UserRole.customer, linkedCustomerId: customer.id));
    _audit.record(userName, 'Customer login created', 'Customer', entityId: customer.id, newValue: phone);
    return null;
  }
}
