import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import 'package:sarathigrocery/app/injection.dart';

/// One multi-section CSV of the open shop: customers (balances), sales,
/// customer payments and the money ledger. Offered before deleting a shop.
String shopExportCsv(AppScope scope) {
  final rows = <List<Object?>>[
    ['Shop', scope.settings.current.businessName],
    ['Exported', DateTime.now().toIso8601String()],
    [],
    ['CUSTOMERS'],
    ['Name', 'Phone', 'Location', 'Credit limit', 'Udharo balance', 'Old udharo (before app)'],
    for (final c in scope.customers.customers) [c.name, c.phone, c.location, c.creditLimit, c.outstandingBalance, c.openingBalance ?? 0],
    [],
    ['SALES'],
    ['Id', 'Date', 'Customer', 'Credit', 'Total', 'Status', 'By'],
    for (final s in scope.sales.sales) [s.id, s.date.toIso8601String(), s.customer?.name ?? '', s.isCredit, s.total, s.status.name, s.createdByName],
    [],
    ['PAYMENTS'],
    ['Id', 'Date', 'Customer', 'Amount', 'Method', 'Reference', 'Collected by', 'Counted in', 'Undone'],
    for (final p in scope.payments.payments)
      [p.id, p.date.toIso8601String(), p.customer.name, p.amount, p.method.name, p.reference, p.collectedByName, p.settledAmount ?? '', p.isReversed],
    [],
    ['MONEY IN & OUT'],
    ['Id', 'Date', 'Type', 'Account', 'Amount', 'Note', 'Reference'],
    for (final e in scope.cash.ledger) [e.id, e.date.toIso8601String(), e.type.name, e.account, e.signedAmount, e.note, e.reference],
  ];
  return rows.map((r) => r.map(_cell).join(',')).join('\r\n');
}

String _cell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp('[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

Future<void> shareShopExport(AppScope scope) {
  const name = 'shop-export.csv';
  return SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(utf8.encode(shopExportCsv(scope)), mimeType: 'text/csv', name: name)],
    fileNameOverrides: [name],
  ));
}
