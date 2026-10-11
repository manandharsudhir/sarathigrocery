import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
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
      'currency': s.currency,
      'countryCode': s.countryCode,
      'features': [for (final f in Feature.values) if (s.has(f)) f.name],
      'safeguards': [for (final g in Safeguard.values) if (s.guards(g)) g.name],
      'owners': [for (final o in s.owners) {'name': o.name, 'percent': o.percent}],
      'moneyAccounts': s.moneyAccounts,
      'expenseCategories': s.expenseCategories,
      'closedThrough': s.closedThrough == null ? null : toMillis(s.closedThrough!),
      'vatRegistered': s.vatRegistered,
      'panNumber': s.panNumber,
      'pricesIncludeVat': s.pricesIncludeVat,
      'marginPercent': s.marginPercent,
    },
    fromJson: (j) => BusinessSettings(
      businessName: j['businessName'] ?? '',
      businessAddress: j['businessAddress'] ?? '',
      businessPhone: j['businessPhone'] ?? '',
      defaultLowStockThreshold: toInt(j['defaultLowStockThreshold']),
      taxPercent: toDouble(j['taxPercent']),
      currency: _currency(j),
      countryCode: j['countryCode'] ?? '+977',
      features: _features(j),
      safeguards: _safeguards(j),
      owners: _owners(j),
      moneyAccounts: _strings(j['moneyAccounts']),
      expenseCategories: _strings(j['expenseCategories']),
      closedThrough: fromMillisOrNull(j['closedThrough']),
      vatRegistered: j['vatRegistered'] ?? false,
      panNumber: j['panNumber'] ?? '',
      pricesIncludeVat: j['pricesIncludeVat'] ?? true,
      marginPercent: toDouble(j['marginPercent']),
    ),
    merge: (s, j) => s
      ..businessName = j['businessName'] ?? ''
      ..businessAddress = j['businessAddress'] ?? ''
      ..businessPhone = j['businessPhone'] ?? ''
      ..defaultLowStockThreshold = toInt(j['defaultLowStockThreshold'])
      ..taxPercent = toDouble(j['taxPercent'])
      ..currency = _currency(j)
      ..countryCode = j['countryCode'] ?? '+977'
      ..features = _features(j)
      ..safeguards = _safeguards(j)
      ..owners = _owners(j)
      ..moneyAccounts = _strings(j['moneyAccounts'])
      ..expenseCategories = _strings(j['expenseCategories'])
      ..closedThrough = fromMillisOrNull(j['closedThrough'])
      ..vatRegistered = j['vatRegistered'] ?? false
      ..panNumber = j['panNumber'] ?? ''
      ..pricesIncludeVat = j['pricesIncludeVat'] ?? true
      ..marginPercent = toDouble(j['marginPercent']),
  );

  List<SyncedCollection<Object?>> get collections => [_settings];

  // Shown until the backend has a settings document (first run).
  final _defaults = BusinessSettings(
    businessName: '',
    businessAddress: '',
    businessPhone: '',
    defaultLowStockThreshold: 10,
    taxPercent: 0,
  );

  @override
  BusinessSettings get current => _settings.items.isEmpty ? _defaults : _settings.items.first;

  @override
  void update(BusinessSettings settings) {
    currencyLabel = settings.currency;
    if (_settings.items.isEmpty) {
      _settings.add(settings);
    } else {
      final existing = _settings.items.first
        ..businessName = settings.businessName
        ..businessAddress = settings.businessAddress
        ..businessPhone = settings.businessPhone
        ..defaultLowStockThreshold = settings.defaultLowStockThreshold
        ..taxPercent = settings.taxPercent
        ..currency = settings.currency
        ..countryCode = settings.countryCode
        ..features = {...settings.features}
        ..safeguards = {...settings.safeguards}
        ..owners = [...settings.owners]
        ..moneyAccounts = [...settings.moneyAccounts]
        ..expenseCategories = [...settings.expenseCategories]
        ..closedThrough = settings.closedThrough
        ..vatRegistered = settings.vatRegistered
        ..panNumber = settings.panNumber
        ..pricesIncludeVat = settings.pricesIncludeVat
        ..marginPercent = settings.marginPercent;
      _settings.save(existing);
    }
  }
}

/// Missing or unknown names count as off.
Set<Feature> _features(Json j) => {
      for (final name in (j['features'] as List?) ?? const [])
        for (final f in Feature.values)
          if (f.name == name) f,
    };

Set<Safeguard> _safeguards(Json j) => {
      for (final name in (j['safeguards'] as List?) ?? const [])
        for (final g in Safeguard.values)
          if (g.name == name) g,
    };

List<OwnerShare> _owners(Json j) => [for (final o in (j['owners'] as List?) ?? const []) OwnerShare(o['name'] ?? '', toDouble(o['percent']))];

List<String> _strings(Object? list) => [for (final s in (list as List?) ?? const []) s as String];

/// Missing = NPR. Also points [formatNpr] at the loaded shop's currency.
String _currency(Json j) => currencyLabel = j['currency'] ?? 'NPR';
