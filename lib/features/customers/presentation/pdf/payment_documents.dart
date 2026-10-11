import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/signature_pad.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_statement.dart';

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

Future<Uint8List> statementPdf(Customer customer, CustomerStatement statement, {required String businessName}) {
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    build: (_) => [
      _header(businessName, 'Statement · ${customer.name} · ${formatDate(DateTime.now())}'),
      _row('Current balance', formatNpr(customer.outstandingBalance)),
      _row('Credit limit', formatNpr(customer.creditLimit)),
      if (!statement.balanced) pw.Text("Note: balance doesn't add up, check records (difference ${formatNpr(statement.unexplainedDifference)}).", style: const pw.TextStyle(color: PdfColors.red)),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: ['Date', 'Entry', 'Change', 'Balance'],
        cellAlignments: {2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
        data: [
          ['', 'Old udharo (before app)', '', formatNpr(statement.opening)],
          for (final l in statement.lines)
            [
              formatDate(l.date),
              l.payment == null ? l.title : '${l.title} · ${_verification(l.payment!)}',
              l.change == 0 ? '-' : '${l.change > 0 ? '+' : '-'}${formatNpr(l.change.abs())}',
              formatNpr(l.balance),
            ],
        ],
      ),
    ],
  ));
  return doc.save();
}

Future<void> sharePdf(Uint8List bytes, String fileName, {String? text}) =>
    SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)], fileNameOverrides: [fileName], text: text));
