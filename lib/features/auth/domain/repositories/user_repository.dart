import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';

abstract class UserRepository {
  List<AppUser> get users;

  AppUser? byId(String id);

  AppUser? findByEmail(String email);

  /// One-shot profile read (before the mirror is loaded, e.g. at login to
  /// learn the role and so what this account may load).
  Future<AppUser?> fetch(String id);

  /// Shops [accountId] belongs to (its own `accounts` doc; empty if none).
  Future<List<String>> shopIdsOf(String accountId);

  /// Creates the current shop with [owner] as its owner and appends it to
  /// the owner's account. Atomic with whatever else is queued in the same
  /// turn (the settings doc).
  void createShop(AppUser owner);

  /// Overwrites the account's shop list (the owner leaving a reset shop).
  void setShopIds(String accountId, List<String> shopIds);

  /// Adds a staff profile to the current shop, and the shop to its account
  /// (appended, so an existing login keeps its other shops).
  void add(AppUser user);

  /// Records that [email] belongs to the signed-in [accountId], so other
  /// shops can add this login as staff. Only the account itself may write it.
  void registerEmail(String email, String accountId);

  /// The account that registered [email] (on login), if any.
  Future<String?> accountIdForEmail(String email);

  /// The founding owner of [shopId] (`shops/{id}.ownerId`): only they can
  /// erase the shop, add or remove co-owners, or hand the role over.
  Future<String?> founderOf(String shopId);

  /// Hands the founding owner role of the current shop to [accountId].
  void setFounder(String accountId);

  /// Persists changes made to an existing [user] (active flag, permissions, ...).
  void update(AppUser user);
}
