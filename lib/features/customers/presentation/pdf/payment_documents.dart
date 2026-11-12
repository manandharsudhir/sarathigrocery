import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/signature_pad.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_statement.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';

/// Printable receipts/statements for customers — shared as
/// PDF to WhatsApp/Viber/email, or printed from the share sheet.

pw.Widget _signature(String? encoded, String name) {
  final signature = Signature.decode(encoded);
  if (signature == null) return pw.SizedBox();
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.SizedBox(height: 12),
    pw.Container(
      height: 60,
      width: 200,
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
      child: pw.CustomPaint(
        size: const PdfPoint(200, 60),
        painter: (canvas, size) {
          canvas
            ..setStrokeColor(PdfColors.black)
            ..setLineWidth(1.2);
          for (final stroke in signature.strokes) {
            if (stroke.length < 2) continue;
            // PDF's origin is bottom-left; the pad's is top-left.
            canvas.moveTo(stroke.first.dx / 1000 * size.x, size.y - stroke.first.dy / 1000 * size.y);
            for (final p in stroke.skip(1)) {
              canvas.lineTo(p.dx / 1000 * size.x, size.y - p.dy / 1000 * size.y);
            }
            canvas.strokePath();
          }
        },
      ),
    ),
    pw.Text('Signed by $name', style: const pw.TextStyle(fontSize: 9)),
  ]);
}

pw.Widget _header(String businessName, String title) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(businessName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text(title, style: const pw.TextStyle(fontSize: 13)),
      pw.Divider(),
    ]);

pw.Widget _row(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text(k), pw.Text(v, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
    );

String _verification(CustomerPayment p) {
  if (p.isReversed) return 'Undone by ${p.reversedByName}: ${p.reversalReason}';
  if (p.isDisputed) return 'Disputed: "${p.disputeNote}"';
  if (p.confirmedBySignature) return 'Signed by customer';
  if (p.phoneConfirmedAt != null) return 'Confirmed by phone with ${p.phoneConfirmedByName}';
  if (p.autoConfirmed) return 'Recorded by ${p.collectedByName}';
  return 'Not yet confirmed by customer';
}

Future<Uint8List> paymentReceiptPdf(CustomerPayment p, {required String businessName}) {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      _header(businessName, 'Payment receipt ${p.id}'),
      _row('Customer', p.customer.name),
      _row('Date', formatDate(p.date)),
      _row('Received', formatNpr(p.amount)),
      _row('Method', '${paymentMethodLabel(p.method)}${p.reference.isEmpty ? '' : ' · ${p.reference}'}'),
      if (p.orderId != null) _row('For order ${p.orderId}', formatNpr(p.appliedToOrder)),
      if (p.appliedToPreviousBalance > 0) _row('Toward earlier balance', formatNpr(p.appliedToPreviousBalance)),
      _row('Balance after', formatNpr(p.balanceAfter)),
      _row('Collected by', p.collectedByName),
      pw.SizedBox(height: 8),
      pw.Text(_verification(p), style: const pw.TextStyle(fontSize: 10)),
      _signature(p.signature, p.signedName),
    ]),
  ));
  return doc.save();
}

const _notTaxInvoice = 'Statement of account, not a tax invoice.';

String _change(double c) => c == 0 ? '-' : '${c > 0 ? '+' : '-'}${formatNpr(c.abs())}';

/// Item lines of [sale] as indented table rows: product, qty × price, total.
List<List<String>> _itemRows(Sale sale, {String prefix = ''}) => [
      for (final i in sale.items) ['', '    $prefix${i.product.name}', '${formatQty(i.qty)} ${i.unit} x ${formatNpr(i.unitPrice)}', formatNpr(i.lineTotal), ''],
    ];

/// Every bill (with items) and payment in [period], running balance.
Future<Uint8List> fullStatementPdf(Customer customer, FullStatement statement, {required String businessName, required String period}) {
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    build: (_) => [
      _header(businessName, 'Statement · ${customer.name} · $period'),
      pw.Text(_notTaxInvoice, style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9)),
      pw.SizedBox(height: 8),
      _row('Brought forward', formatNpr(statement.broughtForward)),
      _row('Bought', formatNpr(statement.bought)),
      if (statement.returned > 0) _row('Returned', formatNpr(statement.returned)),
      _row('Paid', formatNpr(statement.paid)),
      _row('Closing balance', formatNpr(statement.closing)),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: ['Date', 'Entry', 'Qty x price', 'Amount', 'Balance'],
        cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        data: [
          ['', 'Brought forward', '', '', formatNpr(statement.broughtForward)],
          for (final l in statement.lines) ...[
            [
              formatDate(l.date),
              l.payment == null ? l.title : '${l.title} · ${_verification(l.payment!)}',
              '',
              l.sale != null ? formatNpr(l.sale!.total) : _change(l.change),
              formatNpr(l.balance),
            ],
            if (l.sale != null) ..._itemRows(l.sale!),
            for (final r in l.returns) ...[
              ['', '    Returned ${formatDate(r.date)}${r.invoiceNumber == null ? '' : ' · credit note ${r.invoiceNumber}'}', '', formatNpr(r.total), ''],
              ..._itemRows(r, prefix: '  '),
            ],
          ],
        ],
      ),
    ],
  ));
  return doc.save();
}

/// What the customer still owes now: old udharo left, then each unpaid bill
/// with its items, paid so far and due.
Future<Uint8List> amountDuePdf(Customer customer, CustomerStatement statement, {required String businessName}) {
  final due = amountDue(statement);
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    build: (_) => [
      _header(businessName, 'Amount due · ${customer.name} · ${formatDate(DateTime.now())}'),
      pw.Text(_notTaxInvoice, style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9)),
      pw.SizedBox(height: 8),
      _row('Total due', formatNpr(due.total)),
      if ((customer.outstandingBalance - due.total).abs() > 0.5) _row('Current balance', formatNpr(customer.outstandingBalance)),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: ['Date', 'Bill / item', 'Qty x price', 'Amount', 'Due'],
        cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
        data: [
          if (due.openingDue > 0) ['', 'Old udharo (before app)', '', '', formatNpr(due.openingDue)],
          for (final b in due.bills) ...[
            [
              formatDate(b.sale.date),
              '${b.sale.orderId != null ? 'Order ${b.sale.orderId} invoice' : 'Bill ${b.sale.invoiceNumber ?? b.sale.id}'}'
                  '${b.paid > 0 ? ' · paid ${formatNpr(b.paid)}' : ''}${b.returned > 0 ? ' · returned ${formatNpr(b.returned)}' : ''}',
              '',
              formatNpr(b.sale.total),
              formatNpr(b.due),
            ],
            ..._itemRows(b.sale),
          ],
          ['', 'Total due', '', '', formatNpr(due.total)],
        ],
      ),
    ],
  ));
  return doc.save();
}

/// Opens the system print dialog for [bytes].
Future<void> printPdf(Uint8List bytes, String name) => Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

Future<void> sharePdf(Uint8List bytes, String fileName, {String? text}) =>
    SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)], fileNameOverrides: [fileName], text: text));
