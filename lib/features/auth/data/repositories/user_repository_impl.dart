import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';

AppUser _userFromJson(Json j) {
  final u = AppUser(id: j['id'], name: '', phone: '', role: UserRole.values.byName(j['role']));
  _mergeUser(u, j);
  return u;
}

void _mergeUser(AppUser u, Json j) {
  final custom = j['customPermissions'] as List?;
  u
    ..name = j['name'] ?? ''
    ..phone = j['phone'] ?? ''
    ..role = UserRole.values.byName(j['role'])
    ..active = j['active'] ?? true
    ..linkedCustomerId = j['linkedCustomerId']
    ..customPermissions = custom == null ? null : {for (final p in custom) Permission.values.byName(p)};
}

/// Profiles only — credentials live in the [AuthRepository], never here.
class UserRepositoryImpl implements UserRepository {
  final _users = SyncedCollection<AppUser>(
    'users',
    idOf: (u) => u.id,
    toJson: (u) => {
      'name': u.name,
      'phone': u.phone,
      'role': u.role.name,
      'active': u.active,
      'linkedCustomerId': u.linkedCustomerId,
      'customPermissions': u.customPermissions?.map((p) => p.name).toList(),
    },
    fromJson: _userFromJson,
    merge: _mergeUser,
  );

  /// `meta/setup` — `{ownerId}` once first-run setup is done. Never mirrored.
  final _meta = SyncedCollection<({String id, String ownerId})>(
    'meta',
    idOf: (m) => m.id,
    toJson: (m) => {'ownerId': m.ownerId},
    fromJson: (j) => (id: j['id'] as String, ownerId: j['ownerId'] as String),
  );

  List<SyncedCollection<Object?>> get collections => [_users, _meta];

  @override
  List<AppUser> get users => _users.items;

  @override
  AppUser? byId(String id) => _users.byId(id);

  @override
  Future<AppUser?> fetch(String id) async {
    final json = await _users.fetch(id);
    return json == null ? null : _userFromJson(json);
  }

  @override
  Future<bool> isBusinessSetUp() async => await _meta.fetch('setup') != null;

  @override
  void addFirstOwner(AppUser owner) {
    _users.add(owner);
    _meta.add((id: 'setup', ownerId: owner.id));
  }

  @override
  AppUser? findByPhone(String phone) {
    for (final u in users) {
      if (u.phone == phone) return u;
    }
    return null;
  }

  @override
  AppUser? userForCustomer(String customerId) {
    for (final u in users) {
      if (u.linkedCustomerId == customerId) return u;
    }
    return null;
  }

  @override
  void add(AppUser user) => _users.add(user);

  @override
  void update(AppUser user) => _users.save(user);
}
