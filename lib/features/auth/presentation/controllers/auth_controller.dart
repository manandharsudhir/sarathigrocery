import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/data/remote_store.dart';

import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/auth/domain/usecases/set_up_business.dart';

class AuthController extends ChangeNotifier {
  AuthController(
    this._userRepository,
    this._auth,
    this._setUpBusiness, {
    required this._connect,
    required this._disconnect,
    required this._useShop,
    required this._shopName,
    required this._ownedShopNames,
    required this._deleteAccountData,
    Future<void> Function()? flush,
  }) : _flush = flush ?? (() async {});

  /// Waits until queued writes reach the backend (before signing out).
  final Future<void> Function() _flush;

  final UserRepository _userRepository;
  final AuthRepository _auth;
  final SetUpBusiness _setUpBusiness;

  /// Loads (and starts syncing) whatever data [AppUser.role] may see.
  final Future<void> Function(AppUser user) _connect;
  final void Function() _disconnect;

  /// Scopes the store to a shop before its data is read.
  final void Function(String shopId) _useShop;

  /// The shop's name from its settings (shown in the shop picker).
  final Future<String> Function(String shopId) _shopName;

  /// Names of the shops an account owns (deleting it deletes them).
  final Future<List<String>> Function(String accountId) _ownedShopNames;

  /// Wipes owned shops, anonymises the profile elsewhere, drops the
  /// account's emails/accounts docs (see `AppScope`).
  final Future<void> Function(AppUser me) _deleteAccountData;

  AppUser? currentUser;

  /// Account id of the open shop's founding owner (see [isFounder]).
  String? founderId;

  /// The founding owner: the only one who can erase the shop, add or
  /// remove co-owners, or hand the role over. Co-owners otherwise have
  /// the same rights.
  bool get isFounder => currentUser != null && currentUser!.id == founderId;

  /// Shops this login can open (active profiles). With 2+, the app shows a
  /// picker until [pickShop]; empty when signed out.
  List<({String id, String name})> shops = const [];
  String? loginError;

  /// Non-error message for the login screen (e.g. after account deletion).
  String? loginNotice;

  /// Signed in, but the login belongs to no shop yet (sign-up left before
  /// verifying the email or naming the shop, or the owner's shop was reset):
  /// the app shows sign-up's remaining steps.
  bool needsSetup = false;
  bool busy = false;

  UserRepository get userRepository => _userRepository;

  /// Resumes a session persisted by the auth backend from a previous launch.
  Future<void> restoreSession() async {
    final id = _auth.currentAccountId;
    if (id == null) return;
    await _run(() => _enter(id));
  }

  Future<bool> login(String email, String password) async {
    await _run(() async {
      final id = await _auth.signIn(email, password);
      if (id == null) {
        loginError = 'Invalid email or password.';
        return;
      }
      await _enter(id);
    });
    return currentUser != null;
  }

  // Sign-up: email + password → verify email → shop. These throw
  // [AuthException] with a displayable message.

  bool get signedIn => _auth.currentAccountId != null;

  String? get email => _auth.currentEmail;

  Future<void> signUp(String email, String password) async {
    final badEmail = emailProblem(normalizeEmail(email));
    if (badEmail != null) throw AuthException(badEmail);
    final problem = passwordProblem(password);
    if (problem != null) throw AuthException(problem);
    await _auth.signUp(email, password);
  }

  bool get emailVerified => _auth.emailVerified;

  Future<void> resendVerificationEmail() => _auth.sendEmailVerification();

  /// Throws until the user has clicked the link.
  Future<void> confirmEmailVerified() async {
    if (!await _auth.reloadEmailVerified()) {
      throw AuthException('Not verified yet. Open the link in the email we sent (check spam), then try again.');
    }
  }

  Future<void> sendPasswordReset(String email) async {
    final badEmail = emailProblem(normalizeEmail(email));
    if (badEmail != null) throw AuthException(badEmail);
    await _auth.sendPasswordReset(email);
  }

  /// Creates a shop owned by the signed-in login (after sign-up, or from
  /// Account → Set up another shop) and opens it.
  Future<bool> setUpBusiness({
    required String businessName,
    required String ownerName,
    required String phone,
    required bool includeSampleData,
  }) async {
    if (currentUser != null) {
      currentUser = null;
      _disconnect();
    }
    await _run(() async {
      final ({String accountId, String shopId}) created;
      try {
        created = await _setUpBusiness(businessName: businessName, ownerName: ownerName, phone: phone, includeSampleData: includeSampleData);
      } catch (_) {
        // Still signed in: stay on the shop step so it can be retried.
        needsSetup = true;
        rethrow;
      }
      await _enter(created.accountId, open: created.shopId);
    });
    return currentUser != null;
  }

  /// Opens [shopId], one of [shops].
  Future<void> pickShop(String shopId) => _run(() => _open(_auth.currentAccountId!, shopId));

  /// Back to the shop picker (only offered with 2+ [shops]).
  void switchShop() {
    currentUser = null;
    _disconnect();
    notifyListeners();
  }

  /// A co-owner leaves the open shop: their profile is switched off (only
  /// the founding owner can bring them back), then they're signed out of it.
  Future<void> leaveShop() async {
    final me = currentUser!;
    if (me.role != UserRole.owner || isFounder) throw AuthException('Only a co-owner can leave; the founding owner hands the shop over first.');
    _userRepository.update(me..active = false);
    await _flush(); // saved while still signed in
    await logout();
  }

  Future<void> logout() async {
    currentUser = null;
    shops = const [];
    needsSetup = false;
    notifyListeners();
    _disconnect();
    await _auth.signOut();
  }

  bool can(Permission p) => currentUser?.can(p) ?? false;

  // Account security — these throw [AuthException] with a displayable message.

  Future<void> changePassword(String currentPassword, String newPassword) {
    final problem = passwordProblem(newPassword);
    if (problem != null) throw AuthException(problem);
    return _auth.changePassword(currentPassword, newPassword);
  }

  Future<List<String>> ownedShopNames() => _ownedShopNames(currentUser!.id);

  /// In-app account deletion (Play Store). Wipes every shop this login owns
  /// ([typedShopName] must match the first of [ownedShopNames], if any),
  /// anonymises its profile in shops where it's staff, deletes the login,
  /// and returns to the login screen. Online-only. Throws [AuthException].
  Future<void> deleteAccount({required String password, String typedShopName = ''}) async {
    final me = currentUser!;
    final owned = await ownedShopNames();
    if (owned.isNotEmpty && typedShopName.trim() != owned.first.trim()) {
      throw AuthException('Type the shop name exactly as shown to confirm.');
    }
    if (!await _auth.verifyPassword(password)) throw AuthException('Password is incorrect.');
    try {
      await _deleteAccountData(me);
    } on OfflineException {
      throw AuthException('No internet connection. Connect and try again.');
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Deletion did not finish: $e. Try again.');
    }
    await _auth.deleteAccount(password);
    await logout();
    loginNotice = 'Your account was deleted.';
    notifyListeners();
  }

  /// Finds the shops where the account has an active profile (a reset
  /// shop leaves a stale entry, skipped), then opens [open], or the only
  /// one; with several, [shops] drives the picker.
  Future<void> _enter(String accountId, {String? open}) async {
    shops = const [];
    needsSetup = false;
    final found = <String>[];
    AppUser? any;
    final shopIds = await _userRepository.shopIdsOf(accountId);
    if (shopIds.isEmpty) {
      needsSetup = true;
      return;
    }
    for (final shopId in shopIds) {
      _useShop(shopId);
      final profile = await _userRepository.fetch(accountId);
      any ??= profile;
      if (profile != null && profile.active) found.add(shopId);
    }
    if (found.isEmpty) {
      await _auth.signOut();
      loginError = any == null ? 'This login has no profile in the business.' : 'This account has been deactivated.';
      return;
    }
    // Lets other shops add this login as staff (see CreateEmployeeAccount).
    _userRepository.registerEmail(_auth.currentEmail!, accountId);
    shops = [for (final id in found) (id: id, name: found.length > 1 ? await _shopName(id) : '')];
    if (open != null || found.length == 1) await _open(accountId, open ?? found.single);
  }

  Future<void> _open(String accountId, String shopId) async {
    _useShop(shopId);
    final profile = await _userRepository.fetch(accountId);
    if (profile == null || !profile.active) {
      loginError = 'You no longer have access to this shop.';
      return;
    }
    founderId = await _userRepository.founderOf(shopId);
    await _connect(profile);
    currentUser = _userRepository.byId(accountId) ?? profile;
  }

  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    loginError = null;
    loginNotice = null;
    notifyListeners();
    try {
      await action();
    } on AuthException catch (e) {
      loginError = e.message;
    } catch (e) {
      loginError = 'Could not sign in: $e';
    }
    busy = false;
    notifyListeners();
  }
}
