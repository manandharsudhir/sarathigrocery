import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/auth/domain/repositories/auth_repository.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/domain/repositories/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository, this._auth, this._wipeBackend, {bool Function()? isFounder}) : _isFounder = isFounder ?? (() => true);

  /// Only the founding owner may erase the shop.
  final bool Function() _isFounder;

  final SettingsRepository _repository;
  final AuthRepository _auth;

  /// Deletes every document of the current shop (owner's own profile and
  /// the shop doc last). Provided by the composition root, which knows all
  /// collections.
  final Future<void> Function(AppUser owner) _wipeBackend;

  BusinessSettings get current => _repository.current;

  void update({
    required String businessName,
    required String businessAddress,
    required String businessPhone,
    required int defaultLowStockThreshold,
    required double taxPercent,
    String? currency,
    String? countryCode,
  }) {
    _repository.update(current.copyWith(
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      defaultLowStockThreshold: defaultLowStockThreshold,
      taxPercent: taxPercent,
      currency: currency,
      countryCode: countryCode,
    ));
    notifyListeners();
    AppSignal.instance.ping();
  }

  bool has(Feature feature) => current.has(feature);

  /// Margin purchases suggest new minimum prices at (cost + %).
  void setMargin(double percent) {
    _repository.update(current.copyWith(marginPercent: percent < 0 ? 0 : percent));
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// VAT registration (owner only): rate %, PAN printed on bills, and
  /// whether typed prices already include VAT.
  void setVat({required bool registered, required String pan, required double rate, required bool pricesIncludeVat}) {
    _repository.update(current.copyWith(vatRegistered: registered, panNumber: pan.trim(), taxPercent: rate, pricesIncludeVat: pricesIncludeVat));
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// Settings → More features (owner only in the UI).
  void setFeature(Feature feature, bool on) =>
      _toggle(features: on ? {...current.features, feature} : ({...current.features}..remove(feature)));

  bool guards(Safeguard safeguard) => current.guards(safeguard);

  /// Settings → Safeguards (owner only in the UI).
  void setSafeguard(Safeguard safeguard, bool on) =>
      _toggle(safeguards: on ? {...current.safeguards, safeguard} : ({...current.safeguards}..remove(safeguard)));

  /// "Turn on safeguards for staff?" after the first staff account.
  void enableAllSafeguards() => _toggle(safeguards: Safeguard.values.toSet());

  void _toggle({Set<Feature>? features, Set<Safeguard>? safeguards}) {
    final c = current;
    _repository.update(c.copyWith(features: features, safeguards: safeguards));
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// Irreversibly erases ALL of this shop's data (other shops untouched) — products, customers, sales,
  /// payments, ledgers, audit log, staff profiles — so the business can be
  /// set up from scratch. Owner only; [typedName] must equal the business
  /// name and [password] must be the owner's. Needs a connection. Throws
  /// [AuthException] with a displayable message. The caller signs out after.
  ///
  /// Logins (Firebase Auth accounts) are not deleted — the client can't
  /// delete other people's accounts. The owner's own login is reused by the
  /// next setup.
  Future<void> resetBusiness({required AppUser owner, required String typedName, required String password}) async {
    if (owner.role != UserRole.owner || !_isFounder()) throw AuthException('Only the founding owner can reset the business.');
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
