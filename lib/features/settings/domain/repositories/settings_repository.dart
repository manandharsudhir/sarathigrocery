import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

abstract class SettingsRepository {
  BusinessSettings get current;

  void update(BusinessSettings settings);
}
