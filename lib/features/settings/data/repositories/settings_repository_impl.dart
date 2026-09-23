import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/domain/repositories/settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final _settings = SyncedCollection<BusinessSettings>(
    'settings',
    idOf: (_) => 'business',
    toJson: (s) => {
      'businessName': s.businessName,
      'businessAddress': s.businessAddress,
      'businessPhone': s.businessPhone,
      'defaultLowStockThreshold': s.defaultLowStockThreshold,
      'taxPercent': s.taxPercent,
    },
    fromJson: (j) => BusinessSettings(
      businessName: j['businessName'] ?? '',
      businessAddress: j['businessAddress'] ?? '',
      businessPhone: j['businessPhone'] ?? '',
      defaultLowStockThreshold: toInt(j['defaultLowStockThreshold']),
      taxPercent: toDouble(j['taxPercent']),
    ),
    merge: (s, j) => s
      ..businessName = j['businessName'] ?? ''
      ..businessAddress = j['businessAddress'] ?? ''
      ..businessPhone = j['businessPhone'] ?? ''
      ..defaultLowStockThreshold = toInt(j['defaultLowStockThreshold'])
      ..taxPercent = toDouble(j['taxPercent']),
  );

  List<SyncedCollection<Object?>> get collections => [_settings];

  // Shown until the backend has a settings document (first run).
  final _defaults = BusinessSettings(
    businessName: 'Sarathi Grocery',
    businessAddress: 'Koteshwor, Kathmandu',
    businessPhone: '9800000001',
    defaultLowStockThreshold: 10,
    taxPercent: 0,
  );

  @override
  BusinessSettings get current => _settings.items.isEmpty ? _defaults : _settings.items.first;

  @override
  void update(BusinessSettings settings) {
    if (_settings.items.isEmpty) {
      _settings.add(settings);
    } else {
      final existing = _settings.items.first
        ..businessName = settings.businessName
        ..businessAddress = settings.businessAddress
        ..businessPhone = settings.businessPhone
        ..defaultLowStockThreshold = settings.defaultLowStockThreshold
        ..taxPercent = settings.taxPercent;
      _settings.save(existing);
    }
  }
}
