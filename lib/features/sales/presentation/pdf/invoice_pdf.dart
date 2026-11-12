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
/// A tax invoice is dated when issued (an edit's new invoice: the edit day);
/// any other bill keeps the day the goods were sold.
DateTime billDate(Sale sale, CreditNote? creditNote) => creditNote?.date ?? (sale.invoiceNumber != null ? sale.date : sale.soldDate);

/// What an edited bill says about its edit: the bill it replaces ([replaces]:
/// its number) and the other of sold / edited dates.
List<(String, String)> editRows(Sale sale, String? replaces) => [
      if (sale.corrects != null) ...[
        if (sale.invoiceNumber != null) ('Goods sold on', '${formatBs(sale.soldDate)} (${formatDate(sale.soldDate)})')
        else ('Edited', '${formatDate(sale.date)}${sale.createdByName.isEmpty ? '' : ' by ${sale.createdByName}'}'),
        ('Replaces ${sale.invoiceNumber != null ? 'invoice' : 'bill'}', replaces ?? sale.corrects!),
      ],
    ];

({String title, List<(String, String)> head, List<(String, String, String)> lines, List<(String, String)> totals}) billContent(
  Sale sale,
  BusinessSettings seller, {
  CreditNote? creditNote,
  double? paid,
  double returned = 0,
  String? replaces,
}) {
  final showPaid = paid != null && sale.isCredit && creditNote == null;
  final net = sale.total - returned;
  final tax = sale.invoiceNumber != null;
  final date = billDate(sale, creditNote);
  return (
    title: creditNote != null ? 'Credit Note' : (tax ? 'Tax Invoice' : 'Invoice'),
    head: [
      ('Seller', seller.businessName),
      if (seller.businessAddress.isNotEmpty) ('Address', seller.businessAddress),
      if (seller.panNumber.isNotEmpty) ('PAN/VAT No.', seller.panNumber),
      if (creditNote != null) ...[('Credit note no.', creditNote.number), ('Against invoice', sale.invoiceNumber ?? sale.id), ('Reason', creditNote.reason)]
      else ('${tax ? 'Invoice' : 'Bill'} no.', sale.invoiceNumber ?? sale.id),
      ('Date', '${formatBs(date)} (${formatDate(date)})'),
      for (final (k, v) in editRows(sale, replaces)) (k, v),
      ('Buyer', sale.customer?.name ?? 'Walk-in customer'),
      if (sale.buyerPan.isNotEmpty) ('Buyer PAN', sale.buyerPan),
      ('Payment', billPayment(sale, paid: paid, returned: returned)),
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
      if (returned > 0.005 && creditNote == null) ...[(sale.orderId != null ? 'Refused at delivery' : 'Returned', '−${formatNpr(returned)}'), ('Net', formatNpr(net))],
      if (showPaid) ...[('Paid', formatNpr(paid)), ('Balance due', formatNpr(net - paid))],
    ],
  );
}

/// Printed bill, laid out like a typical Nepali tax invoice: shop header,
/// customer block left / invoice block right, ruled item table, amount in
/// words, totals, and signature lines.
/// [copies]: one page per label (printing: customer + shop copy).
Future<Uint8List> billPdf(Sale sale, BusinessSettings seller, {CreditNote? creditNote, double? paid, double returned = 0, String? replaces, List<String> copies = const ['']}) {
  final tax = sale.invoiceNumber != null;
  final date = billDate(sale, creditNote);
  final c = billContent(sale, seller, creditNote: creditNote, paid: paid, returned: returned, replaces: replaces);
  final customer = sale.customer;
  return billLayoutPdf(
    copies: copies,
    seller: seller,
    title: c.title,
    vat: tax,
    left: [
      ('Customer Name', customer?.name ?? 'Walk-in customer'),
      if (customer != null && customer.location.isNotEmpty) ('Customer Address', customer.location),
      if (sale.buyerPan.isNotEmpty) ('Customer ${tax ? 'VAT' : 'PAN'} No', sale.buyerPan),
      ('Mode of payment', billPayment(sale, paid: paid, returned: returned)),
    ],
    right: [
      ('Invoice Date', billDmy(date)),
      ('Invoice Miti', billBsDmy(date)),
      if (creditNote != null) ...[('Credit Note No', creditNote.number), ('Against Invoice', sale.invoiceNumber ?? sale.id)]
      else ('Invoice No', sale.invoiceNumber ?? sale.id),
      if (creditNote == null) ...editRows(sale, replaces),
    ],
    items: [
      for (final i in sale.items) (name: '${i.product.name}${tax && i.product.vatExempt ? ' (VAT exempt)' : ''}', qty: i.qty, unit: i.unit, rate: i.unitPrice, amount: i.lineTotal),
    ],
    totals: [
      for (final (k, v) in c.totals)
        switch (k) {
          'Total' => ('Total Amount', billMoney(sale.total)),
          'VAT' => ('${formatQty(seller.taxPercent)} % VAT', billMoney(sale.vatAmount)),
          'Exempt sales' => (k, billMoney(sale.exemptAmount)),
          'Taxable amount' => (k, billMoney(sale.taxableAmount)),
          'Paid' => (k, billMoney(paid ?? 0)),
          'Refused at delivery' || 'Returned' => (k, '-${billMoney(returned)}'),
          'Net' => (k, billMoney(sale.total - returned)),
          'Balance due' => (k, billMoney(sale.total - returned - (paid ?? 0))),
          _ => (k, v),
        },
    ],
    total: sale.total,
    remarks: creditNote?.reason ?? '',
    preparedBy: sale.createdByName,
  );
}

/// The printed bill's page, shared by bills and order slips: shop header
/// with [title], [left]/[right] info blocks, item table, amount in words,
/// [totals] (already formatted; "Total Amount" in bold), remarks and
/// signature lines. [vat] picks the "VAT No." vs "PAN No." label. One page
/// per [copies] label ("Customer copy", "Shop copy"); '' = unlabelled.
Future<Uint8List> billLayoutPdf({
  List<String> copies = const [''],
  required BusinessSettings seller,
  required String title,
  required bool vat,
  required List<(String, String)> left,
  required List<(String, String)> right,
  required List<({String name, double qty, String unit, double rate, double amount})> items,
  required List<(String, String)> totals,
  required double total,
  String remarks = '',
  String preparedBy = '',
}) {
  final now = DateTime.now();
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

  final cell = const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3);
  pw.Widget td(String text, {pw.TextAlign align = pw.TextAlign.left, pw.TextStyle? style}) =>
      pw.Padding(padding: cell, child: pw.Text(text, textAlign: align, style: style));
  const r = pw.TextAlign.right;
  const ctr = pw.TextAlign.center;

  final doc = pw.Document();
  for (final copy in copies) {
    doc.addPage(pw.Page(
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.DefaultTextStyle(
        style: const pw.TextStyle(fontSize: 10),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          if (copy.isNotEmpty) pw.Text(copy.toUpperCase(), textAlign: r, style: small),
          pw.Text(seller.businessName.toUpperCase(), textAlign: ctr, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          if (seller.businessAddress.isNotEmpty) pw.Text(seller.businessAddress.toUpperCase(), textAlign: ctr, style: bold),
          if (seller.businessPhone.isNotEmpty) pw.Text('Tel : ${seller.businessPhone}', textAlign: ctr, style: bold),
          pw.SizedBox(height: 8),
          pw.Stack(alignment: pw.Alignment.center, children: [
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: seller.panNumber.isEmpty ? pw.SizedBox() : pw.Text('${vat ? 'VAT' : 'PAN'} No.  ${seller.panNumber}', style: bold),
            ),
            pw.Text(title.toUpperCase(), style: bold),
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
              for (final (n, i) in items.indexed)
                pw.TableRow(children: [
                  td('${n + 1}', align: ctr),
                  td(i.name),
                  td(formatQty(i.qty), align: r),
                  td(i.unit),
                  td(billMoney(i.rate), align: r),
                  td(billMoney(i.amount), align: r),
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
                    pw.TextSpan(text: amountInWords(total)),
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
            child: pw.Text('Remarks : $remarks'),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Printed Date: ${billDmy(now)}, Time: ${_time(now)}', style: small),
          pw.SizedBox(height: 40),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            _signature(preparedBy, 'Prepared By'),
            _signature('', 'Received By'),
            _signature('', 'Authorized signature\nFor: ${seller.businessName}'),
          ]),
        ]),
      ),
    ));
  }
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
/// [paid]: how much of a credit bill is paid off so far, when known.
String billPayment(Sale sale, {double? paid, double returned = 0}) {
  if (!sale.isCredit) return accountName(sale.account);
  if (paid == null || paid < 0.005) return 'Credit';
  return paid >= sale.total - returned - 0.005 ? 'Paid' : 'Part paid';
}

String _two(int n) => n.toString().padLeft(2, '0');
/// dd/mm/yyyy dates on printed bills: AD, and BS ([billBsDmy]).
String billDmy(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
String _time(DateTime d) => '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${_two(d.minute)}:${_two(d.second)} ${d.hour < 12 ? 'am' : 'pm'}';
String billBsDmy(DateTime d) {
  try {
    final b = BsDate.fromAd(d);
    return '${_two(b.day)}/${_two(b.month)}/${b.year}';
  } on RangeError {
    return '';
  }
}

/// 1,38,053.30: Nepali grouping with paisa, no currency label.
String billMoney(double amount) {
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
