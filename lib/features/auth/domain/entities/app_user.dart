import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.active = true,
    this.linkedCustomerId,
    this.customPermissions,
  });

  final String id;
  String name;
  String phone;
  UserRole role;
  bool active;

  /// For [UserRole.customer] accounts: the business Customer record this login maps to.
  String? linkedCustomerId;

  /// Null = use [defaultRolePermissions] for [role]. Set = explicit override.
  Set<Permission>? customPermissions;

  Set<Permission> get permissions => customPermissions ?? defaultRolePermissions[role] ?? {};

  bool can(Permission p) => permissions.contains(p);
}
