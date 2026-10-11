import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/data/write_queue.dart';

/// Optional starter catalogue offered during first-run setup: categories,
/// products, customers, suppliers. Written as raw documents (fixed ids, so
/// re-running overwrites instead of duplicating). No money: its stock,
/// customers' udharo and supplier dues are booked as opening capital
/// ([capital] splits an amount across the owners, credit side).
void writeSampleData(WriteQueue writes, {required Map<String, double> Function(double amount) capital}) {
  final now = DateTime.now();
  int daysAgo(int d) => toMillis(now.subtract(Duration(days: d)));
  int inDays(int d) => toMillis(now.add(Duration(days: d)));

  final docs = <String, Map<String, Json>>{
    'categories': {
      for (final c in ['Rice', 'Oil', 'Sugar', 'Spices', 'Beverages', 'Pulses', 'Noodles', 'Biscuits']) c: {'name': c},
    },
    'products': {
      'P0001': {'name': 'Basmati Rice 25kg', 'category': 'Rice', 'unitPrice': 3200, 'stockQty': 18, 'reservedQty': 0, 'reorderLevel': 10, 'unit': 'sack', 'sku': 'RIC-25', 'brand': 'Annapurna', 'isActive': true},
      'P0002': {'name': 'Mustard Oil 15L', 'category': 'Oil', 'unitPrice': 4500, 'stockQty': 4, 'reservedQty': 0, 'reorderLevel': 6, 'unit': 'bottle', 'sku': 'OIL-15', 'isActive': true},
      'P0003': {'name': 'Sugar 50kg', 'category': 'Sugar', 'unitPrice': 5800, 'stockQty': 12, 'reservedQty': 0, 'reorderLevel': 8, 'unit': 'sack', 'sku': 'SUG-50', 'isActive': true},
      'P0004': {'name': 'Turmeric Powder 1kg', 'category': 'Spices', 'unitPrice': 320, 'stockQty': 40, 'reservedQty': 0, 'reorderLevel': 15, 'unit': 'packet', 'sku': 'SPI-TUR1', 'expiryDate': inDays(20), 'isActive': true},
      'P0005': {'name': 'Coke 2L (Case of 9)', 'category': 'Beverages', 'unitPrice': 1350, 'stockQty': 25, 'reservedQty': 0, 'reorderLevel': 10, 'unit': 'carton', 'sku': 'BEV-COKE2', 'isActive': true},
      'P0006': {'name': 'Chiya Patti 1kg', 'category': 'Beverages', 'unitPrice': 280, 'stockQty': 5, 'reservedQty': 0, 'reorderLevel': 10, 'unit': 'packet', 'sku': 'BEV-TEA1', 'expiryDate': inDays(10), 'isActive': true},
    },
    'productCosts': {
      'P0001': {'purchasePrice': 2800},
      'P0002': {'purchasePrice': 3900},
      'P0003': {'purchasePrice': 5200},
      'P0004': {'purchasePrice': 250},
      'P0005': {'purchasePrice': 1100},
      'P0006': {'purchasePrice': 220},
    },
    'customers': {
      'C0001': {'name': 'Shrestha Kirana Pasal', 'phone': '98410XXXXX', 'location': 'Baneshwor', 'creditLimit': 50000, 'outstandingBalance': 32000, 'openingBalance': 32000, 'lastPaymentDate': daysAgo(5)},
      'C0002': {'name': 'Gurung General Store', 'phone': '98510XXXXX', 'location': 'Koteshwor', 'creditLimit': 30000, 'outstandingBalance': 31500, 'openingBalance': 31500, 'lastPaymentDate': daysAgo(40)},
      'C0003': {'name': 'Thapa Trading', 'phone': '98010XXXXX', 'location': 'Balkumari', 'creditLimit': 20000, 'outstandingBalance': 4000, 'openingBalance': 4000, 'lastPaymentDate': daysAgo(45)},
    },
    'suppliers': {
      'SU0001': {'name': 'Ramesh Traders', 'businessName': 'Ramesh Wholesale Traders', 'phone': '98110XXXXX', 'address': 'Kalanki', 'productsSupplied': 'Rice, Sugar', 'amountPayable': 45000},
      'SU0002': {'name': 'Himal Distributors', 'businessName': 'Himal FMCG Distributors', 'phone': '98220XXXXX', 'address': 'Balaju', 'productsSupplied': 'Oil, Beverages', 'amountPayable': 0},
    },
  };

  // Every field the app's own toJson writes, so a later save() of these
  // docs changes only what was edited (the rules compare changed keys).
  const productDefaults = {'sku': '', 'brand': '', 'packs': <Json>[], 'vatExempt': false, 'primaryUnit': '', 'saleUnit': '', 'customUnitLabel': '', 'description': '', 'expiryDate': null, 'isActive': true, 'reservedQty': 0};
  docs['products'] = {for (final e in docs['products']!.entries) e.key: {...productDefaults, ...e.value}};
  docs['customers'] = {for (final e in docs['customers']!.entries) e.key: {'pan': '', ...e.value}};
  docs['suppliers'] = {for (final e in docs['suppliers']!.entries) e.key: {'pan': '', ...e.value}};

  // Opening entry so the books match the sample records.
  double sum(String collection, num Function(Json d, String id) f) => docs[collection]!.entries.fold(0.0, (t, e) => t + f(e.value, e.key));
  final stock = sum('products', (d, id) => (d['stockQty'] as num) * (docs['productCosts']![id]!['purchasePrice'] as num));
  final owed = sum('customers', (d, _) => d['outstandingBalance'] as num);
  final owing = sum('suppliers', (d, _) => d['amountPayable'] as num);
  docs['journal'] = {
    'open-sample': {
      'date': toMillis(now),
      'kind': 'opening',
      'memo': 'Opening balances (sample data)',
      'reference': '',
      'byName': '',
      'lines': [
        for (final l in {'stock': stock, 'receivables': owed, 'payables': -owing, ...capital(stock + owed - owing)}.entries) {'account': l.key, 'amount': l.value},
      ],
    },
  };

  docs.forEach((collection, byId) => byId.forEach((id, data) => writes.enqueue(PutOp(collection, id, data))));
}
