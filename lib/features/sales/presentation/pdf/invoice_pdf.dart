import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
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
      ('Payment', sale.isCredit ? 'Credit (udharo)' : 'Paid'),
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

Future<Uint8List> billPdf(Sale sale, BusinessSettings seller, {CreditNote? creditNote}) {
  final c = billContent(sale, seller, creditNote: creditNote);
  final doc = pw.Document();
  doc.addPage(pw.Page(
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(c.title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      for (final (k, v) in c.head) pw.Text('$k: $v'),
      pw.Divider(),
      for (final (name, qty, total) in c.lines)
        pw.Row(children: [pw.Expanded(flex: 3, child: pw.Text(name)), pw.Expanded(flex: 3, child: pw.Text(qty)), pw.Expanded(flex: 2, child: pw.Text(total, textAlign: pw.TextAlign.right))]),
      pw.Divider(),
      for (final (k, v) in c.totals) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(k), pw.Text(v)]),
    ]),
  ));
  return doc.save();
}
