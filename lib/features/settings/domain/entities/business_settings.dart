class BusinessSettings {
  BusinessSettings({
    required this.businessName,
    required this.businessAddress,
    required this.businessPhone,
    required this.defaultLowStockThreshold,
    required this.taxPercent,
  });

  String businessName;
  String businessAddress;
  String businessPhone;
  int defaultLowStockThreshold;
  double taxPercent;
}
