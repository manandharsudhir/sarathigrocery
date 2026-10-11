import 'package:flutter/material.dart';

import 'package:sarathigrocery/features/customers/presentation/pdf/payment_documents.dart';
import 'package:sarathigrocery/features/sales/domain/entities/credit_note.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/presentation/pdf/invoice_pdf.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

/// A sale's bill (tax invoice in VAT shops), or its credit note; shareable as PDF.
class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({super.key, required this.sale, required this.seller, this.creditNote});

  final Sale sale;
  final BusinessSettings seller;
  final CreditNote? creditNote;

  @override
  Widget build(BuildContext context) {
    final c = billContent(sale, seller, creditNote: creditNote);
    return Scaffold(
      appBar: AppBar(
        title: Text(c.title),
        actions: [
          IconButton(
            tooltip: 'Share PDF',
            icon: const Icon(Icons.share),
            onPressed: () async => sharePdf(await billPdf(sale, seller, creditNote: creditNote), '${(creditNote?.number ?? sale.invoiceNumber ?? sale.id).replaceAll('/', '-')}.pdf'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(c.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final (k, v) in c.head) Text('$k: $v'),
          Text('Status: ${sale.status.name}${sale.flaggedForApproval ? ' (over credit limit)' : ''}'),
          const Divider(height: 32),
          for (final (name, qty, total) in c.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(flex: 3, child: Text(name)),
                Expanded(flex: 3, child: Text(qty, textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text(total, textAlign: TextAlign.right)),
              ]),
            ),
          const Divider(height: 32),
          for (final (k, v) in c.totals)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(k, style: TextStyle(fontWeight: k == 'Total' ? FontWeight.bold : null)),
                Text(v, style: TextStyle(fontWeight: k == 'Total' ? FontWeight.bold : null)),
              ]),
            ),
        ],
      ),
    );
  }
}
