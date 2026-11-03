import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/sales/domain/entities/credit_note.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

/// The bill as lines of (label, value): shared by the screen and the PDF so
/// both always show the same thing. A VAT sale is a "Tax Invoice".
/// The exact layout IRD requires should be confirmed by your accountant.
({String title, List<(String, String)> head, List<(String, String, String)> lines, List<(String, String)> totals}) billContent(
  Sale sale,
  BusinessSettings seller, {
  CreditNote? creditNote,
}) {
  final tax = sale.invoiceNumber != null;
  final date = creditNote?.date ?? sale.date;
  return (
    title: creditNote != null ? 'Credit Note' : (tax ? 'Tax Invoice' : 'Invoice'),
    head: [
      ('Seller', seller.businessName),
      if (seller.businessAddress.isNotEmpty) ('Address', seller.businessAddress),
      if (seller.panNumber.isNotEmpty) ('PAN/VAT No.', seller.panNumber),
      if (creditNote != null) ...[('Credit note no.', creditNote.number), ('Against invoice', sale.invoiceNumber ?? sale.id), ('Reason', creditNote.reason)]
      else ('${tax ? 'Invoice' : 'Bill'} no.', sale.invoiceNumber ?? sale.id),
      ('Date', '${formatBs(date)} (${formatDate(date)})'),
      ('Buyer', sale.customer?.name ?? 'Walk-in customer'),
      if (sale.buyerPan.isNotEmpty) ('Buyer PAN', sale.buyerPan),
      ('Payment', billPayment(sale)),
    ],
    lines: [
      for (final i in sale.items)
        ('${i.product.name}${tax && i.product.vatExempt ? ' (VAT exempt)' : ''}', '${formatQty(i.qty)} ${i.unit} × ${formatNpr(i.unitPrice)}', formatNpr(i.lineTotal)),
    ],
    totals: [
      if (tax) ...[
        if (sale.exemptAmount > 0) ('Exempt sales', formatNpr(sale.exemptAmount)),
        ('Taxable amount', formatNpr(sale.taxableAmount)),
        ('VAT', formatNpr(sale.vatAmount)),
      ],
      ('Total', formatNpr(sale.total)),
    ],
  );
}

/// Printed bill, laid out like a typical Nepali tax invoice: shop header,
/// customer block left / invoice block right, ruled item table, amount in
/// words, totals, and signature lines.
Future<Uint8List> billPdf(Sale sale, BusinessSettings seller, {CreditNote? creditNote}) {
  final tax = sale.invoiceNumber != null;
  final date = creditNote?.date ?? sale.date;
  final now = DateTime.now();
  final c = billContent(sale, seller, creditNote: creditNote);
  const small = pw.TextStyle(fontSize: 9);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  pw.Widget info(List<(String, String)> rows, double labelWidth) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final (k, v) in rows)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.SizedBox(width: labelWidth, child: pw.Text(k)),
                pw.Text(': '),
                pw.Expanded(child: pw.Text(v)),
              ]),
            ),
        ],
      );

  final customer = sale.customer;
  final left = [
    ('Customer Name', customer?.name ?? 'Walk-in customer'),
    if (customer != null && customer.location.isNotEmpty) ('Customer Address', customer.location),
    if (sale.buyerPan.isNotEmpty) ('Customer ${tax ? 'VAT' : 'PAN'} No', sale.buyerPan),
    ('Mode of payment', billPayment(sale)),
  ];
  final right = [
    ('Invoice Date', _dmy(date)),
    ('Invoice Miti', _bsDmy(date)),
    if (creditNote != null) ...[('Credit Note No', creditNote.number), ('Against Invoice', sale.invoiceNumber ?? sale.id)]
    else ('Invoice No', sale.invoiceNumber ?? sale.id),
  ];

  final cell = const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3);
  pw.Widget td(String text, {pw.TextAlign align = pw.TextAlign.left, pw.TextStyle? style}) =>
      pw.Padding(padding: cell, child: pw.Text(text, textAlign: align, style: style));
  const r = pw.TextAlign.right;
  const ctr = pw.TextAlign.center;

  final totals = [...c.totals];
  totals[totals.length - 1] = ('Total Amount', _money(sale.total));
  for (var i = 0; i < totals.length - 1; i++) {
    final (k, _) = totals[i];
    totals[i] = (k == 'VAT' ? '${formatQty(seller.taxPercent)} % VAT' : k, _money(switch (k) {
      'Exempt sales' => sale.exemptAmount,
      'Taxable amount' => sale.taxableAmount,
      'VAT' => sale.vatAmount,
      _ => 0,
    }));
  }

  final doc = pw.Document();
  doc.addPage(pw.Page(
    margin: const pw.EdgeInsets.all(28),
    build: (_) => pw.DefaultTextStyle(
      style: const pw.TextStyle(fontSize: 10),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(seller.businessName.toUpperCase(), textAlign: ctr, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        if (seller.businessAddress.isNotEmpty) pw.Text(seller.businessAddress.toUpperCase(), textAlign: ctr, style: bold),
        if (seller.businessPhone.isNotEmpty) pw.Text('Tel : ${seller.businessPhone}', textAlign: ctr, style: bold),
        pw.SizedBox(height: 8),
        pw.Stack(alignment: pw.Alignment.center, children: [
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: seller.panNumber.isEmpty ? pw.SizedBox() : pw.Text('${tax ? 'VAT' : 'PAN'} No.  ${seller.panNumber}', style: bold),
          ),
          pw.Text(c.title.toUpperCase(), style: bold),
        ]),
        pw.Divider(height: 8, thickness: 1),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(flex: 3, child: info(left, 100)),
          pw.SizedBox(width: 16),
          pw.Expanded(flex: 2, child: info(right, 80)),
        ]),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(width: 0.8),
          columnWidths: const {
            0: pw.FixedColumnWidth(30),
            1: pw.FlexColumnWidth(5),
            2: pw.FixedColumnWidth(50),
            3: pw.FixedColumnWidth(50),
            4: pw.FixedColumnWidth(70),
            5: pw.FixedColumnWidth(80),
          },
          children: [
            pw.TableRow(children: [
              td('S.N', align: ctr, style: bold),
              td('Particular', align: ctr, style: bold),
              td('QTY', align: ctr, style: bold),
              td('Unit', align: ctr, style: bold),
              td('Rate', align: ctr, style: bold),
              td('Amount', align: ctr, style: bold),
            ]),
            for (final (n, i) in sale.items.indexed)
              pw.TableRow(children: [
                td('${n + 1}', align: ctr),
                td('${i.product.name}${tax && i.product.vatExempt ? ' (VAT exempt)' : ''}'),
                td(formatQty(i.qty), align: r),
                td(i.unit),
                td(_money(i.unitPrice), align: r),
                td(_money(i.lineTotal), align: r),
              ]),
          ],
        ),
        pw.Container(
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.RichText(text: pw.TextSpan(children: [
                  pw.TextSpan(text: 'Amount In Words : ', style: bold),
                  pw.TextSpan(text: amountInWords(sale.total)),
                ])),
              ),
            ),
            pw.SizedBox(
              width: 200,
              child: pw.Table(
                border: const pw.TableBorder(left: pw.BorderSide(width: 0.8), horizontalInside: pw.BorderSide(width: 0.8), verticalInside: pw.BorderSide(width: 0.8)),
                children: [
                  for (final (k, v) in totals)
                    pw.TableRow(children: [td(k, style: bold), td(v, align: r, style: k == 'Total Amount' ? bold : null)]),
                ],
              ),
            ),
          ]),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          decoration: const pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(width: 0.8), right: pw.BorderSide(width: 0.8), bottom: pw.BorderSide(width: 0.8))),
          child: pw.Text('Remarks : ${creditNote?.reason ?? ''}'),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Printed Date: ${_dmy(now)}, Time: ${_time(now)}', style: small),
        pw.SizedBox(height: 40),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _signature(sale.createdByName, 'Prepared By'),
          _signature('', 'Received By'),
          _signature('', 'Authorized signature\nFor: ${seller.businessName}'),
        ]),
      ]),
    ),
  ));
  return doc.save();
}

pw.Widget _signature(String name, String label) => pw.SizedBox(
      width: 150,
      child: pw.Column(children: [
        pw.Text(name),
        pw.Divider(thickness: 0.8),
        pw.Text(label, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ]),
    );

/// "Credit" for udharo, else the money account it was paid into.
String billPayment(Sale sale) => sale.isCredit ? 'Credit' : accountName(sale.account);

String _two(int n) => n.toString().padLeft(2, '0');
String _dmy(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
String _time(DateTime d) => '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${_two(d.minute)}:${_two(d.second)} ${d.hour < 12 ? 'am' : 'pm'}';
String _bsDmy(DateTime d) {
  try {
    final b = BsDate.fromAd(d);
    return '${_two(b.day)}/${_two(b.month)}/${b.year}';
  } on RangeError {
    return '';
  }
}

/// 1,38,053.30: Nepali grouping with paisa, no currency label.
String _money(double amount) {
  final paisa = (amount * 100).round();
  final rupees = formatNpr((paisa ~/ 100).toDouble()).substring(currencyLabel.length + 1);
  return '$rupees.${_two(paisa % 100)}';
}

const _ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _below100(int n) => n < 20 ? _ones[n] : [_tens[n ~/ 10], if (n % 10 > 0) _ones[n % 10]].join('-');

String _words(int n) {
  final parts = <String>[];
  if (n >= 10000000) {
    parts.add('${_words(n ~/ 10000000)} Crore');
    n %= 10000000;
  }
  for (final (size, name) in [(100000, 'Lakh'), (1000, 'Thousand'), (100, 'Hundred')]) {
    if (n >= size) {
      parts.add('${_below100(n ~/ size)} $name');
      n %= size;
    }
  }
  if (n > 0) parts.add(_below100(n));
  return parts.join(' ');
}

/// "One Lakh Fifty-Six Thousand Rupees and Twenty-Three Paisa only"
/// (lakh/crore grouping).
String amountInWords(double amount) {
  final paisa = (amount * 100).round();
  final rupees = paisa < 100 ? 'Zero' : _words(paisa ~/ 100);
  final p = paisa % 100;
  return p == 0 ? '$rupees Rupees only' : '$rupees Rupees and ${_below100(p)} Paisa only';
}
