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
    ..email = j['email'] ?? ''
    ..role = UserRole.values.byName(j['role'])
    ..active = j['active'] ?? true
    ..customPermissions = custom == null ? null : {for (final p in custom) Permission.values.byName(p)};
}

/// Profiles only — credentials live in the [AuthRepository], never here.
/// A profile under a shop is that account's membership (role + overrides).
class UserRepositoryImpl implements UserRepository {
  UserRepositoryImpl(this._shopId);

  /// The shop the store is scoped to (see `ShopScopedStore`).
  final String? Function() _shopId;

  final _users = SyncedCollection<AppUser>(
    'users',
    idOf: (u) => u.id,
    toJson: (u) => {
      'name': u.name,
      'phone': u.phone,
      'email': u.email,
      'role': u.role.name,
      'active': u.active,
      'customPermissions': u.customPermissions?.map((p) => p.name).toList(),
    },
    fromJson: _userFromJson,
    merge: _mergeUser,
  );

  // Top-level and never mirrored: `accounts/{uid}` = `{shopIds}` (where
  // login looks), `emails/{email}` = `{uid}` (finds an existing login when
  // adding staff), `shops/{shopId}` = `{ownerId, createdAt}`.
  static SyncedCollection<Json> _raw(String name) => SyncedCollection<Json>(name, idOf: (j) => j['id'], toJson: (j) => j, fromJson: (j) => j);
  final _accounts = _raw('accounts');
  final _emails = _raw('emails');
  final _shops = _raw('shops');

  List<SyncedCollection<Object?>> get collections => [_users, _accounts, _emails, _shops];

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
  Future<List<String>> shopIdsOf(String accountId) async => [...?(await _accounts.fetch(accountId))?['shopIds'] as List?].cast<String>();

  @override
  void createShop(AppUser owner) {
    _shops.patch(_shopId()!, {'ownerId': owner.id, 'createdAt': toMillis(DateTime.now())});
    add(owner);
  }

  @override
  void setShopIds(String accountId, List<String> shopIds) => _accounts.patch(accountId, {'shopIds': shopIds});

  @override
  AppUser? findByEmail(String email) {
    for (final u in users) {
      if (u.email == email) return u;
    }
    return null;
  }

  @override
  void add(AppUser user) {
    _users.add(user);
    _accounts.union(user.id, {'shopIds': [_shopId()!]});
  }

  @override
  void registerEmail(String email, String accountId) => _emails.patch(email, {'uid': accountId});

  @override
  Future<String?> accountIdForEmail(String email) async => (await _emails.fetch(email))?['uid'] as String?;

  @override
  Future<String?> founderOf(String shopId) async => (await _shops.fetch(shopId))?['ownerId'] as String?;

  @override
  void setFounder(String accountId) => _shops.patch(_shopId()!, {'ownerId': accountId});

  @override
  void update(AppUser user) => _users.save(user);
}
