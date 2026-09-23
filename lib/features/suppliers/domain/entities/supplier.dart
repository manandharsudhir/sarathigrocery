class Supplier {
  Supplier({
    required this.id,
    required this.name,
    required this.businessName,
    required this.phone,
    required this.address,
    this.productsSupplied = '',
    this.amountPayable = 0,
  });

  final String id;
  String name;
  String businessName;
  String phone;
  String address;
  String productsSupplied;
  double amountPayable;
}
