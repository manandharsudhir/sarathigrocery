import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/customers/presentation/pdf/payment_documents.dart';
import 'package:sarathigrocery/features/sales/domain/entities/credit_note.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/presentation/pdf/invoice_pdf.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/widgets/collect_on_bill.dart';

/// A sale's bill (tax invoice in VAT shops), or its credit note; shareable as
/// PDF. An udharo bill shows what's paid and due, and (with [auth] allowed to
/// record payments) collects against it.
class InvoiceScreen extends StatelessWidget {
  const InvoiceScreen({super.key, required this.sale, required this.sales, this.auth, this.creditNote});

  final Sale sale;
  final SalesController sales;
  final AuthController? auth;
  final CreditNote? creditNote;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: sales, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final seller = sales.seller;
    final paid = creditNote == null ? sales.paidOn(sale) : null;
    final canCollect = paid != null && sale.total - paid > 0.005 && (auth?.can(Permission.recordPayments) ?? false);
    final c = billContent(sale, seller, creditNote: creditNote, paid: paid);
    return Scaffold(
      floatingActionButton: canCollect
          ? FloatingActionButton.extended(heroTag: null, icon: const Icon(Icons.payments_outlined), label: const Text('Collect'), onPressed: () => collectOnBill(context, sale, sales, auth!))
          : null,
      appBar: AppBar(
        title: Text(c.title),
        actions: [
          IconButton(
            tooltip: 'Share PDF',
            icon: const Icon(Icons.share),
            onPressed: () async => sharePdf(await billPdf(sale, seller, creditNote: creditNote, paid: paid), billFileName(sale, creditNote)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
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
                Text(k, style: TextStyle(fontWeight: k == 'Total' || k == 'Balance due' ? FontWeight.bold : null)),
                Text(v, style: TextStyle(fontWeight: k == 'Total' || k == 'Balance due' ? FontWeight.bold : null)),
              ]),
            ),
        ],
      ),
    );
  }
}

/// "Ram Stores 2082-07-17 Cash 2082-83-15.pdf": customer, BS date, how it was
/// paid, then the bill number so same-day bills don't clash.
String billFileName(Sale sale, CreditNote? creditNote) {
  final date = creditNote?.date ?? sale.date;
  String day;
  try {
    day = BsDate.fromAd(date).toString();
  } on RangeError {
    day = date.toIso8601String().substring(0, 10); // outside the BS table
  }
  final payment = creditNote != null ? 'Credit note' : sale.isCredit ? 'Credit' : accountName(sale.account);
  final number = creditNote?.number ?? sale.invoiceNumber ?? sale.id;
  final customer = sale.customer?.name.trim() ?? '';
  final name = [customer.isEmpty ? 'Walk-in' : customer, day, payment, number].where((s) => s.isNotEmpty).join(' ');
  return '${name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')}.pdf';
}
