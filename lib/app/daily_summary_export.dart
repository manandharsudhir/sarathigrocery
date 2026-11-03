import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:sarathigrocery/app/injection.dart';
import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/reports/domain/daily_summary.dart';

DailySummary dailySummaryFor(AppScope scope, DateTime from, DateTime to) => dailySummary(
      from: from,
      to: to,
      accounts: scope.cash.moneyAccounts,
      ledger: scope.cash.ledger,
      sales: scope.sales.sales,
      payments: scope.payments.payments,
      expenses: scope.cash.expenses,
      purchases: scope.purchasing.purchases,
      journal: scope.accounting.journal,
    );

String _cell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp('[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

const _footer = 'Internal summary, not a tax invoice or IRD report.';

/// One row per day; every money account gets its own closing column.
String dailySummaryCsv(AppScope scope, DailySummary summary) {
  final accounts = scope.cash.moneyAccounts;
  final rows = <List<Object?>>[
    ['Date', 'BS date', for (final a in accounts) accountName(a), 'Sales', 'Cash sales', 'Udharo sales', 'Orders delivered', 'Collections', 'Expenses', 'Purchases', 'Supplier payments', 'Customers owe', 'Owed to suppliers', 'Profit'],
    for (final d in summary.days)
      [_iso(d.day), formatBs(d.day), for (final a in accounts) d.balances[a] ?? 0, d.sales, d.cashSales, d.creditSales, d.ordersDelivered, d.collections, d.expenses, d.purchases, d.supplierPayments, d.receivables, d.payables, d.profit],
  ];
  return rows.map((r) => r.map(_cell).join(',')).join('\r\n');
}

/// Landscape: range totals, then one table line per day.
Future<Uint8List> dailySummaryPdf(AppScope scope, DailySummary summary) {
  final s = scope.settings.current;
  final first = summary.days.first.day, last = summary.closing.day;
  String n(double v) => formatNpr(v).replaceFirst('$currencyLabel ', '');
  pw.Widget line(String k, String v) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(k), pw.Text(v)]);
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    footer: (_) => pw.Text(_footer, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    build: (_) => [
      pw.Text(s.businessName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text('Daily summary: ${_iso(first)} (${formatBs(first)}) – ${_iso(last)} (${formatBs(last)}) · amounts in $currencyLabel'),
      pw.SizedBox(height: 8),
      pw.SizedBox(
        width: 300,
        child: pw.Column(children: [
          line('Cash in hand', '${n(summary.opening.cash)} → ${n(summary.closing.cash)}'),
          line('Bank', '${n(summary.opening.bank)} → ${n(summary.closing.bank)}'),
          line('Wallet', '${n(summary.opening.wallet)} → ${n(summary.closing.wallet)}'),
          line('Sales', n(summary.total((d) => d.sales))),
          line('Collections', n(summary.total((d) => d.collections))),
          line('Expenses', n(summary.total((d) => d.expenses))),
          line('Purchases', n(summary.total((d) => d.purchases))),
          line('Supplier payments', n(summary.total((d) => d.supplierPayments))),
          line('Profit', n(summary.total((d) => d.profit))),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headerStyle: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 7),
        cellAlignment: pw.Alignment.centerRight,
        headers: ['Date', 'BS date', 'Cash', 'Bank', 'Wallet', 'Sales', 'Cash sales', 'Udharo', 'Orders', 'Collected', 'Expenses', 'Purchases', 'Supplier paid', 'Customers owe', 'Owed to suppliers', 'Profit'],
        data: [
          for (final d in summary.days)
            [_iso(d.day), formatBs(d.day).replaceFirst(' BS', ''), n(d.cash), n(d.bank), n(d.wallet), n(d.sales), n(d.cashSales), n(d.creditSales), '${d.ordersDelivered}', n(d.collections), n(d.expenses), n(d.purchases), n(d.supplierPayments), n(d.receivables), n(d.payables), n(d.profit)],
        ],
      ),
    ],
  ));
  return doc.save();
}

/// Shares the daily summary for [from]..[to] as CSV + PDF.
Future<void> shareDailySummary(AppScope scope, DateTime from, DateTime to) async {
  final summary = dailySummaryFor(scope, from, to);
  final base = 'daily-summary-${_iso(from)}-to-${_iso(to)}';
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile.fromData(utf8.encode(dailySummaryCsv(scope, summary)), mimeType: 'text/csv', name: '$base.csv'),
      XFile.fromData(await dailySummaryPdf(scope, summary), mimeType: 'application/pdf', name: '$base.pdf'),
    ],
    fileNameOverrides: ['$base.csv', '$base.pdf'],
  ));
}
