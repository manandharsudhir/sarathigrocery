import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';

abstract class UserRepository {
  List<AppUser> get users;

  AppUser? byId(String id);

  AppUser? findByPhone(String phone);

  AppUser? userForCustomer(String customerId);

  /// One-shot profile read (before the mirror is loaded, e.g. at login to
  /// learn the role and so what this account may load).
  Future<AppUser?> fetch(String id);

  /// Whether first-run setup has happened (readable while signed out).
  Future<bool> isBusinessSetUp();

  /// Creates the first owner and marks the business as set up, atomically.
  /// The backend accepts this exactly once.
  void addFirstOwner(AppUser owner);

  void add(AppUser user);

  /// Persists changes made to an existing [user] (active flag, permissions, ...).
  void update(AppUser user);
}
