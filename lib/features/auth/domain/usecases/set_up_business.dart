import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/user_repository.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/domain/repositories/settings_repository.dart';

/// Sets up a brand-new shop for the signed-in login (sign-up verified its
/// email first): the shop, its owner profile, settings and (optionally) a
/// sample catalogue. The backend only lets a login with a verified email
/// create shops, and only own a shop id that didn't exist yet, so no
/// existing shop can be taken over.
class SetUpBusiness {
  SetUpBusiness(this._users, this._auth, this._settings, {required this._commit, required this._writeSampleData, required this._useShop});

  final UserRepository _users;
  final AuthRepository _auth;
  final SettingsRepository _settings;

  /// Waits until queued writes are accepted — later writes are authorized
  /// by the owner profile, so it must exist on the server first.
  final Future<void> Function() _commit;
  final void Function() _writeSampleData;

  /// Scopes the store to a shop id.
  final void Function(String shopId) _useShop;

  /// Returns the owner's account id and the new shop's id, or throws [AuthException].
  Future<({String accountId, String shopId})> call({
    required String businessName,
    required String ownerName,
    required String phone,
    required bool includeSampleData,
  }) async {
    if (businessName.trim().isEmpty || ownerName.trim().isEmpty || phone.trim().isEmpty) throw AuthException('Fill in every field.');
    final id = _auth.currentAccountId;
    if (id == null || !_auth.emailVerified) throw AuthException('Verify your email first.');

    final shopId = nextId('S');
    _useShop(shopId);
    // One commit: shop, owner profile, account entry, settings.
    _users.createShop(AppUser(id: id, name: ownerName.trim(), phone: phone.trim(), email: _auth.currentEmail!, role: UserRole.owner));
    _settings.update(BusinessSettings(businessName: businessName.trim(), businessAddress: '', businessPhone: phone.trim(), defaultLowStockThreshold: 10, taxPercent: 0, owners: [OwnerShare(ownerName.trim(), 100)]));
    await _commit();

    if (includeSampleData) {
      _writeSampleData();
      await _commit();
    }
    return (accountId: id, shopId: shopId);
  }
}
