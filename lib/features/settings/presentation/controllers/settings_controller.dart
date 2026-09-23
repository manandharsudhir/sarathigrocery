import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/domain/repositories/settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository);

  final SettingsRepository _repository;

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
}
