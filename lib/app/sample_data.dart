import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/data/write_queue.dart';

/// Optional starter catalogue offered during first-run setup: categories,
/// products, customers, suppliers. Written as raw documents (fixed ids, so
/// re-running overwrites instead of duplicating). No accounts, no money.
void writeSampleData(WriteQueue writes) {
  final now = DateTime.now();
  int daysAgo(int d) => toMillis(now.subtract(Duration(days: d)));
  int inDays(int d) => toMillis(now.add(Duration(days: d)));

  final docs = <String, Map<String, Json>>{
    'categories': {
      for (final c in ['Rice', 'Oil', 'Sugar', 'Spices', 'Beverages', 'Pulses', 'Noodles', 'Biscuits']) c: {'name': c},
    },
    'products': {
      'P0001': {'name': 'Basmati Rice 25kg', 'category': 'Rice', 'unitPrice': 3200, 'purchasePrice': 2800, 'stockQty': 18, 'reservedQty': 0, 'reorderLevel': 10, 'unit': 'sack', 'sku': 'RIC-25', 'brand': 'Annapurna', 'isActive': true},
      'P0002': {'name': 'Mustard Oil 15L', 'category': 'Oil', 'unitPrice': 4500, 'purchasePrice': 3900, 'stockQty': 4, 'reservedQty': 0, 'reorderLevel': 6, 'unit': 'bottle', 'sku': 'OIL-15', 'isActive': true},
      'P0003': {'name': 'Sugar 50kg', 'category': 'Sugar', 'unitPrice': 5800, 'purchasePrice': 5200, 'stockQty': 12, 'reservedQty': 0, 'reorderLevel': 8, 'unit': 'sack', 'sku': 'SUG-50', 'isActive': true},
      'P0004': {'name': 'Turmeric Powder 1kg', 'category': 'Spices', 'unitPrice': 320, 'purchasePrice': 250, 'stockQty': 40, 'reservedQty': 0, 'reorderLevel': 15, 'unit': 'packet', 'sku': 'SPI-TUR1', 'expiryDate': inDays(20), 'isActive': true},
      'P0005': {'name': 'Coke 2L (Case of 9)', 'category': 'Beverages', 'unitPrice': 1350, 'purchasePrice': 1100, 'stockQty': 25, 'reservedQty': 0, 'reorderLevel': 10, 'unit': 'carton', 'sku': 'BEV-COKE2', 'isActive': true},
      'P0006': {'name': 'Chiya Patti 1kg', 'category': 'Beverages', 'unitPrice': 280, 'purchasePrice': 220, 'stockQty': 5, 'reservedQty': 0, 'reorderLevel': 10, 'unit': 'packet', 'sku': 'BEV-TEA1', 'expiryDate': inDays(10), 'isActive': true},
    },
    'customers': {
      'C0001': {'name': 'Shrestha Kirana Pasal', 'phone': '98410XXXXX', 'location': 'Baneshwor', 'creditLimit': 50000, 'outstandingBalance': 32000, 'lastPaymentDate': daysAgo(5), 'defaultDiscountPercent': 0},
      'C0002': {'name': 'Gurung General Store', 'phone': '98510XXXXX', 'location': 'Koteshwor', 'creditLimit': 30000, 'outstandingBalance': 31500, 'lastPaymentDate': daysAgo(40), 'defaultDiscountPercent': 0},
      'C0003': {'name': 'Thapa Trading', 'phone': '98010XXXXX', 'location': 'Balkumari', 'creditLimit': 20000, 'outstandingBalance': 4000, 'lastPaymentDate': daysAgo(45), 'defaultDiscountPercent': 0},
    },
    'suppliers': {
      'SU0001': {'name': 'Ramesh Traders', 'businessName': 'Ramesh Wholesale Traders', 'phone': '98110XXXXX', 'address': 'Kalanki', 'productsSupplied': 'Rice, Sugar', 'amountPayable': 45000},
      'SU0002': {'name': 'Himal Distributors', 'businessName': 'Himal FMCG Distributors', 'phone': '98220XXXXX', 'address': 'Balaju', 'productsSupplied': 'Oil, Beverages', 'amountPayable': 0},
    },
  };

  // Every field the app's own toJson writes, so a later save() of these
  // docs changes only what was edited (the rules compare changed keys).
  const productDefaults = {'sku': '', 'brand': '', 'retailPrice': null, 'customUnitLabel': '', 'description': '', 'expiryDate': null, 'isActive': true, 'reservedQty': 0};
  docs['products'] = {for (final e in docs['products']!.entries) e.key: {...productDefaults, ...e.value}};

  docs.forEach((collection, byId) => byId.forEach((id, data) => writes.enqueue(PutOp(collection, id, data))));
}
