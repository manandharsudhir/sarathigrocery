import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
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
  });

  final UserRepository _userRepository;
  final AuthRepository _auth;
  final SetUpBusiness _setUpBusiness;

  /// Loads (and starts syncing) whatever data [AppUser.role] may see.
  final Future<void> Function(AppUser user) _connect;
  final void Function() _disconnect;

  AppUser? currentUser;
  String? loginError;
  bool busy = false;

  UserRepository get userRepository => _userRepository;

  /// Resumes a session persisted by the auth backend from a previous launch.
  Future<void> restoreSession() async {
    final id = _auth.currentAccountId;
    if (id == null) return;
    await _run(() => _enter(id));
  }

  Future<bool> isBusinessSetUp() => _userRepository.isBusinessSetUp();

  Future<bool> login(String phone, String password) async {
    await _run(() async {
      final id = await _auth.signIn(phone, password);
      if (id == null) {
        loginError = 'Invalid phone number or password.';
        return;
      }
      await _enter(id);
    });
    return currentUser != null;
  }

  Future<bool> setUpBusiness({
    required String businessName,
    required String ownerName,
    required String phone,
    required String password,
    required bool includeSampleData,
  }) async {
    await _run(() async {
      final String id;
      try {
        id = await _setUpBusiness(businessName: businessName, ownerName: ownerName, phone: phone, password: password, includeSampleData: includeSampleData);
      } catch (_) {
        await _auth.signOut();
        rethrow;
      }
      await _enter(id);
    });
    return currentUser != null;
  }

  Future<void> logout() async {
    currentUser = null;
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

  bool get phoneVerified => _auth.phoneVerified;

  Future<String> startPhoneVerification() => _auth.startPhoneVerification(currentUser!.phone);

  Future<void> completePhoneVerification(String verificationId, String code) async {
    await _auth.completePhoneVerification(verificationId, code);
    notifyListeners();
  }

  Future<String> startPasswordReset(String phone) => _auth.startPasswordReset(phone);

  Future<void> completePasswordReset(String verificationId, String code, String newPassword) {
    final problem = passwordProblem(newPassword);
    if (problem != null) throw AuthException(problem);
    return _auth.completePasswordReset(verificationId, code, newPassword);
  }

  Future<void> _enter(String accountId) async {
    final profile = await _userRepository.fetch(accountId);
    if (profile == null || !profile.active) {
      await _auth.signOut();
      loginError = profile == null ? 'This login has no profile in the business.' : 'This account has been deactivated.';
      return;
    }
    await _connect(profile);
    currentUser = _userRepository.byId(accountId) ?? profile;
  }

  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    loginError = null;
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
