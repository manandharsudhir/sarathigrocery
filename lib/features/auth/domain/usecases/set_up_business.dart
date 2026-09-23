import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/domain/repositories/settings_repository.dart';

/// First-run setup of a brand-new business: creates the owner login and
/// profile, business settings and (optionally) a sample catalogue. The
/// backend accepts the owner write only while no business exists, so this
/// can't be used to take over an existing one. Leaves the owner signed in.
class SetUpBusiness {
  SetUpBusiness(this._users, this._auth, this._settings, {required this._commit, required this._writeSampleData});

  final UserRepository _users;
  final AuthRepository _auth;
  final SettingsRepository _settings;

  /// Waits until queued writes are accepted — later writes are authorized
  /// by the owner profile, so it must exist on the server first.
  final Future<void> Function() _commit;
  final void Function() _writeSampleData;

  /// Returns the owner's account id, or throws [AuthException].
  Future<String> call({
    required String businessName,
    required String ownerName,
    required String phone,
    required String password,
    required bool includeSampleData,
  }) async {
    if (businessName.trim().isEmpty || ownerName.trim().isEmpty || phone.trim().isEmpty) throw AuthException('Fill in every field.');
    final problem = passwordProblem(password);
    if (problem != null) throw AuthException(problem);
    if (await _users.isBusinessSetUp()) throw AuthException('This business is already set up. Log in instead.');

    final id = await _auth.createAccount(phone, password) ?? (throw AuthException('Phone number $phone is already registered. Log in instead.'));
    if (await _auth.signIn(phone, password) == null) throw AuthException('Could not sign in to the new account.');

    _users.addFirstOwner(AppUser(id: id, name: ownerName.trim(), phone: phone, role: UserRole.owner));
    await _commit();

    _settings.update(BusinessSettings(businessName: businessName.trim(), businessAddress: '', businessPhone: phone, defaultLowStockThreshold: 10, taxPercent: 0));
    if (includeSampleData) _writeSampleData();
    await _commit();
    return id;
  }
}
