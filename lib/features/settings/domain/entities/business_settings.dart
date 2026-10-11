/// Optional parts of the app, switched on per shop in Settings → More
/// features. Off only hides them; their data is never deleted.
enum Feature {
  suppliers('Suppliers & purchases', 'Buying stock from suppliers and what you owe them'),
  categories('Categories', 'Group products into categories'),
  auditLog('Audit log', 'A record of who changed what'),
  expiry('Expiry tracking', 'Warn about products that expire soon');

  const Feature(this.label, this.hint);

  final String label;
  final String hint;
}

/// Checks a shop can switch on once staff handle money (Settings →
/// Safeguards). All off by default; `firestore.rules` enforces those that
/// are on (except [onlineOnly], which only the app can enforce).
enum Safeguard {
  signature('Signature at the door', 'The customer signs on the phone when an order is delivered and paid'),
  phoneConfirm('Phone check of unsigned payments', 'Payments without a signature wait until you call the customer to confirm'),
  handover('Cash handover', 'Staff hand collected cash to you, you count it in, and any missing cash is tracked'),
  onlineOnly('Deliveries need internet', 'Deliver & collect is saved only with a connection, never queued offline');

  const Safeguard(this.label, this.hint);

  final String label;
  final String hint;
}

/// A person who owns part of the business (capital, drawings, dividends).
class OwnerShare {
  const OwnerShare(this.name, this.percent);

  final String name;
  final double percent;
}

class BusinessSettings {
  BusinessSettings({
    required this.businessName,
    required this.businessAddress,
    required this.businessPhone,
    required this.defaultLowStockThreshold,
    required this.taxPercent,
    this.currency = 'NPR',
    this.countryCode = '+977',
    Set<Feature>? features,
    Set<Safeguard>? safeguards,
    this.owners = const [],
    this.moneyAccounts = const [],
    this.expenseCategories = const [],
    this.closedThrough,
    this.vatRegistered = false,
    this.panNumber = '',
    this.pricesIncludeVat = true,
    this.marginPercent = 0,
  })  : features = features ?? {},
        safeguards = safeguards ?? {};

  String businessName;
  String businessAddress;
  String businessPhone;
  int defaultLowStockThreshold;
  double taxPercent;

  /// Label [formatNpr] puts before amounts.
  String currency;

  /// Dialling code for this shop's phone numbers.
  String countryCode;

  /// Switched-on [Feature]s; everything else is off (the default).
  Set<Feature> features;

  bool has(Feature feature) => features.contains(feature);

  /// Switched-on [Safeguard]s (doc field `safeguards`; missing = off).
  Set<Safeguard> safeguards;

  bool guards(Safeguard safeguard) => safeguards.contains(safeguard);

  /// Who owns the business and in what share (owner only edits).
  List<OwnerShare> owners;

  /// Named banks/wallets beyond the built-in Cash, Bank and Wallet
  /// (`bank:NIC Asia`, `wallet:eSewa`).
  List<String> moneyAccounts;

  /// Expense categories added beyond `kExpenseCategories`.
  List<String> expenseCategories;

  /// Year-end close: nothing may be posted on or before this (owner only).
  DateTime? closedThrough;

  /// VAT-registered shops issue tax invoices; [taxPercent] is the VAT rate.
  bool vatRegistered;

  /// PAN (or VAT) number printed on bills.
  String panNumber;

  /// Whether prices typed in sales already contain VAT.
  bool pricesIncludeVat;

  /// Margin a purchase suggests minimum prices at (cost + this %); 0 = none.
  double marginPercent;

  /// A copy with some fields changed; everything else carried over (so a
  /// save never drops fields it didn't mean to touch).
  BusinessSettings copyWith({
    String? businessName,
    String? businessAddress,
    String? businessPhone,
    int? defaultLowStockThreshold,
    double? taxPercent,
    String? currency,
    String? countryCode,
    Set<Feature>? features,
    Set<Safeguard>? safeguards,
    bool? vatRegistered,
    String? panNumber,
    bool? pricesIncludeVat,
    double? marginPercent,
  }) =>
      BusinessSettings(
        businessName: businessName ?? this.businessName,
        businessAddress: businessAddress ?? this.businessAddress,
        businessPhone: businessPhone ?? this.businessPhone,
        defaultLowStockThreshold: defaultLowStockThreshold ?? this.defaultLowStockThreshold,
        taxPercent: taxPercent ?? this.taxPercent,
        currency: currency ?? this.currency,
        countryCode: countryCode ?? this.countryCode,
        features: features ?? {...this.features},
        safeguards: safeguards ?? {...this.safeguards},
        owners: [...owners],
        moneyAccounts: [...moneyAccounts],
        expenseCategories: [...expenseCategories],
        closedThrough: closedThrough,
        vatRegistered: vatRegistered ?? this.vatRegistered,
        panNumber: panNumber ?? this.panNumber,
        pricesIncludeVat: pricesIncludeVat ?? this.pricesIncludeVat,
        marginPercent: marginPercent ?? this.marginPercent,
      );
}
