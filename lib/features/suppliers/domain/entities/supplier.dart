class Supplier {
  Supplier({
    required this.id,
    required this.name,
    required this.businessName,
    required this.phone,
    required this.address,
    this.productsSupplied = '',
    this.amountPayable = 0,
    this.pan = '',
  });

  final String id;
  String name;
  String businessName;
  String phone;
  String address;
  String productsSupplied;
  double amountPayable;

  /// PAN/VAT number, for the Purchase Book.
  String pan;
}
