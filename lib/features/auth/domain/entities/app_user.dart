import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';

/// Name left on a profile whose login was deleted (see account deletion).
const kFormerStaffName = 'Former staff';

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.email = '',
    this.active = true,
    this.customPermissions,
  });

  final String id;
  String name;
  String phone;

  /// Login email (normalised). The phone is only a contact number.
  String email;
  UserRole role;
  bool active;

  /// Null = use [defaultRolePermissions] for [role]. Set = explicit override.
  Set<Permission>? customPermissions;

  Set<Permission> get permissions => customPermissions ?? defaultRolePermissions[role] ?? {};

  bool can(Permission p) => permissions.contains(p);
}
