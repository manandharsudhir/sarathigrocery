import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/domain/repositories/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository, this._auth, this._wipeBackend);

  final SettingsRepository _repository;
  final AuthRepository _auth;

  /// Deletes every business document on the backend (owner's own profile
  /// and the setup marker last). Provided by the composition root, which
  /// knows all collections.
  final Future<void> Function(AppUser owner) _wipeBackend;

  BusinessSettings get current => _repository.current;

  void update({
    required String businessName,
    required String businessAddress,
    required String businessPhone,
    required int defaultLowStockThreshold,
    required double taxPercent,
  }) {
    _repository.update(BusinessSettings(
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      defaultLowStockThreshold: defaultLowStockThreshold,
      taxPercent: taxPercent,
    ));
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// Irreversibly erases ALL business data — products, customers, sales,
  /// payments, ledgers, audit log, staff profiles — so the business can be
  /// set up from scratch. Owner only; [typedName] must equal the business
  /// name and [password] must be the owner's. Needs a connection. Throws
  /// [AuthException] with a displayable message. The caller signs out after.
  ///
  /// Logins (Firebase Auth accounts) are not deleted — the client can't
  /// delete other people's accounts. The owner's own login is reused by the
  /// next setup.
  Future<void> resetBusiness({required AppUser owner, required String typedName, required String password}) async {
    if (owner.role != UserRole.owner) throw AuthException('Only the owner can reset the business.');
    if (typedName.trim() != current.businessName.trim()) throw AuthException('Type the business name exactly as shown to confirm.');
    if (!await _auth.verifyPassword(password)) throw AuthException('Password is incorrect.');
    try {
      await _wipeBackend(owner);
    } on OfflineException {
      throw AuthException('No internet connection. Nothing was deleted — connect and try again.');
    } catch (e) {
      throw AuthException('Reset did not finish: $e. Run it again to delete what is left.');
    }
  }
}
