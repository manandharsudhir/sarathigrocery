import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/accounting_screen.dart';
import 'package:sarathigrocery/features/accounting/presentation/pages/vat_books_screen.dart';

String _cell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp('[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String _d(DateTime d) => '${d.toIso8601String().substring(0, 10)} (${formatBs(d)})';

/// Everything an accountant needs for [period], as one multi-section CSV:
/// Profit & Loss, Balance Sheet and Trial Balance (at the period's end),
/// the journal, and the VAT Sales/Purchase Books.
String accountantCsv(AppScope scope, Period period) {
  final st = scope.accounting.statements;
  final pl = st.profitAndLoss(period.from, period.to);
  final bs = st.balanceSheet(period.to);
  final tb = st.balances(to: period.to);
  final s = scope.settings.current;
  final rows = <List<Object?>>[
    ['Shop', s.businessName],
    if (s.panNumber.isNotEmpty) ['PAN/VAT', s.panNumber],
    ['Period', period.label, _d(period.from), _d(period.to)],
    ['Exported', DateTime.now().toIso8601String()],
    [],
    ['PROFIT AND LOSS'],
    ['Account', 'Amount'],
    for (final e in pl.income.entries) [accountName(e.key), e.value],
    ['Total income', pl.totalIncome],
    for (final e in pl.costs.entries) [accountName(e.key), -e.value],
    ['Total costs', -pl.totalCosts],
    ['Net profit', pl.profit],
    [],
    ['BALANCE SHEET', _d(period.to)],
    ['Section', 'Account', 'Amount'],
    for (final e in bs.assets.entries) ['Assets', accountName(e.key), e.value],
    for (final e in bs.liabilities.entries) ['Liabilities', accountName(e.key), e.value],
    for (final e in bs.equity.entries) ['Owners\' money', accountName(e.key), e.value],
    ['Owners\' money', 'Profit not yet closed', bs.profitNotClosed],
    ['Totals', 'Assets', bs.totalAssets],
    ['Totals', 'Liabilities + owners\' money', bs.totalLiabilities + bs.totalEquity],
    [],
    ['TRIAL BALANCE', _d(period.to)],
    ['Account id', 'Account', 'Type', 'Debit', 'Credit'],
    for (final a in scope.accounting.accounts)
      if ((tb[a] ?? 0).abs() >= 0.005) [a, accountName(a), accountType(a).name, tb[a]! > 0 ? tb[a] : '', tb[a]! < 0 ? -tb[a]! : ''],
    [],
    ['JOURNAL'],
    ['Entry', 'Date', 'BS date', 'Kind', 'Memo', 'Reference', 'By', 'Account', 'Debit', 'Credit'],
    for (final e in scope.accounting.journal)
      if (!e.date.isBefore(period.from) && !e.date.isAfter(period.to))
        for (final l in e.lines.entries)
          [e.id, e.date.toIso8601String(), formatBs(e.date), e.kind, e.memo, e.reference, e.byName, accountName(l.key), l.value > 0 ? l.value : '', l.value < 0 ? -l.value : ''],
    if (s.vatRegistered) ...[
      [],
      ['SALES BOOK'],
      ['Date', 'BS date', 'Invoice / credit note', 'Buyer', 'Buyer PAN', 'Total', 'Exempt', 'Taxable', 'VAT'],
      for (final r in salesBook(scope.sales, period.from, period.to)) [r.date.toIso8601String(), formatBs(r.date), r.number, r.buyer, r.pan, r.total, r.exempt, r.taxable, r.vat],
      [],
      ['PURCHASE BOOK'],
      ['Bill date', 'BS date', 'Supplier bill no.', 'Supplier', 'Supplier PAN', 'Total', 'Taxable', 'VAT'],
      for (final r in purchaseBook(scope.purchasing, period.from, period.to)) [r.date.toIso8601String(), formatBs(r.date), r.billNo, r.supplier, r.pan, r.total, r.taxable, r.vat],
    ],
  ];
  return rows.map((r) => r.map(_cell).join(',')).join('\r\n');
}

/// Profit & Loss, Balance Sheet and Trial Balance as a printable PDF.
Future<Uint8List> accountantPdf(AppScope scope, Period period) {
  final st = scope.accounting.statements;
  final pl = st.profitAndLoss(period.from, period.to);
  final bs = st.balanceSheet(period.to);
  final tb = st.balances(to: period.to);
  final s = scope.settings.current;
  pw.Widget line(String k, double v, {bool bold = false}) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(k, style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
        pw.Text(formatNpr(v), style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
      ]);
  pw.Widget title(String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 14, bottom: 4), child: pw.Text(t, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)));
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    build: (_) => [
      pw.Text(s.businessName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      if (s.panNumber.isNotEmpty) pw.Text('PAN/VAT: ${s.panNumber}'),
      pw.Text('${period.label}: ${_d(period.from)} – ${_d(period.to)}'),
      title('Profit and Loss'),
      for (final e in pl.income.entries) line(accountName(e.key), e.value),
      line('Total income', pl.totalIncome, bold: true),
      for (final e in pl.costs.entries) line(accountName(e.key), e.value),
      line('Total costs', pl.totalCosts, bold: true),
      line(pl.profit >= 0 ? 'Net profit' : 'Net loss', pl.profit, bold: true),
      title('Balance Sheet at ${_d(period.to)}'),
      for (final e in bs.assets.entries) line(accountName(e.key), e.value),
      line('Total assets', bs.totalAssets, bold: true),
      for (final e in bs.liabilities.entries) line(accountName(e.key), e.value),
      line('Total liabilities', bs.totalLiabilities, bold: true),
      for (final e in bs.equity.entries) line(accountName(e.key), e.value),
      line('Profit not yet closed', bs.profitNotClosed),
      line('Total owners\' money', bs.totalEquity, bold: true),
      title('Trial Balance at ${_d(period.to)}'),
      for (final a in scope.accounting.accounts)
        if ((tb[a] ?? 0).abs() >= 0.005) line('${tb[a]! > 0 ? 'Dr' : 'Cr'}  ${accountName(a)}', tb[a]!.abs()),
    ],
  ));
  return doc.save();
}

/// Shares the CSV and PDF for [period] (to email/WhatsApp the accountant).
Future<void> shareAccountantExport(AppScope scope, Period period) async {
  final fy = (() {
    try {
      return BsDate.fiscalYearLabel(BsDate.fromAd(period.to).fiscalYear).replaceAll('/', '-');
    } on RangeError {
      return '';
    }
  })();
  final base = 'accounts-$fy-${period.to.toIso8601String().substring(0, 10)}';
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile.fromData(utf8.encode(accountantCsv(scope, period)), mimeType: 'text/csv', name: '$base.csv'),
      XFile.fromData(await accountantPdf(scope, period), mimeType: 'application/pdf', name: '$base.pdf'),
    ],
    fileNameOverrides: ['$base.csv', '$base.pdf'],
  ));
}
