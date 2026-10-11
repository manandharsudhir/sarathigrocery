import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';

/// One row of the Sales Book (an invoice, or a credit note as negatives).
typedef SalesBookRow = ({DateTime date, String number, String buyer, String pan, double total, double exempt, double taxable, double vat});

/// One row of the Purchase Book.
typedef PurchaseBookRow = ({DateTime date, String billNo, String supplier, String pan, double total, double taxable, double vat});

/// Sales Book: tax invoices, and credit notes as negative rows, dated in [from]..[to].
List<SalesBookRow> salesBook(SalesController sales, DateTime from, DateTime to) {
  bool inside(DateTime d) => !d.isBefore(from) && !d.isAfter(to);
  return [
    for (final s in sales.sales)
      if (s.invoiceNumber != null && inside(s.date))
        (date: s.date, number: s.invoiceNumber!, buyer: s.customer?.name ?? 'Walk-in', pan: s.buyerPan, total: s.total, exempt: s.exemptAmount, taxable: s.taxableAmount, vat: s.vatAmount),
    for (final n in sales.creditNotes)
      if (inside(n.date))
        (date: n.date, number: n.number, buyer: n.sale.customer?.name ?? 'Walk-in', pan: n.sale.buyerPan, total: -n.total, exempt: -n.exemptAmount, taxable: -n.sale.taxableAmount, vat: -n.vatAmount),
  ]..sort((a, b) => a.date.compareTo(b.date));
}

/// Purchase Book: purchases with a VAT bill, by the supplier's bill date.
List<PurchaseBookRow> purchaseBook(PurchasingController purchasing, DateTime from, DateTime to) => [
      for (final p in purchasing.purchases)
        if (p.vatAmount > 0 || p.supplierBillNo.isNotEmpty)
          if (!(p.supplierBillDate ?? p.date).isBefore(from) && !(p.supplierBillDate ?? p.date).isAfter(to))
            (date: p.supplierBillDate ?? p.date, billNo: p.supplierBillNo, supplier: p.supplier.businessName, pan: p.supplier.pan, total: p.total, taxable: p.goodsTotal, vat: p.vatAmount),
    ]..sort((a, b) => a.date.compareTo(b.date));

/// Monthly VAT registers (BS month) and the VAT to pay.
class VatBooksScreen extends StatefulWidget {
  const VatBooksScreen({super.key, required this.sales, required this.purchasing, required this.cash, required this.userName});

  final SalesController sales;
  final PurchasingController purchasing;
  final CashController cash;
  final String userName;

  @override
  State<VatBooksScreen> createState() => _VatBooksScreenState();
}

class _VatBooksScreenState extends State<VatBooksScreen> {
  late BsDate _month = () {
    final now = BsDate.fromAd(DateTime.now());
    return BsDate(now.year, now.month, 1);
  }();

  (DateTime, DateTime) get _range {
    final start = _month.toAd();
    final last = BsDate(_month.year, _month.month, BsDate.daysInMonth(_month.year, _month.month)).toAd();
    return (start, DateTime(last.year, last.month, last.day, 23, 59, 59));
  }

  String get _label => '${BsDate.monthNames[_month.month - 1]} ${_month.year}';

  void _shift(int months) {
    var y = _month.year, m = _month.month + months;
    if (m < 1) (y, m) = (y - 1, 12);
    if (m > 12) (y, m) = (y + 1, 1);
    if (y < BsDate.firstYear || y > BsDate.lastYear) return;
    setState(() => _month = BsDate(y, m, 1));
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range;
    final sales = salesBook(widget.sales, from, to);
    final purchases = purchaseBook(widget.purchasing, from, to);
    final output = sales.fold(0.0, (s, r) => s + r.vat);
    final input = purchases.fold(0.0, (s, r) => s + r.vat);
    Widget cell(String t, {bool end = false}) => Expanded(child: Text(t, textAlign: end ? TextAlign.right : TextAlign.left, style: const TextStyle(fontSize: 12)));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('VAT books'),
          bottom: const TabBar(tabs: [Tab(text: 'Summary'), Tab(text: 'Sales Book'), Tab(text: 'Purchase Book')]),
        ),
        body: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
            Text(_label, style: Theme.of(context).textTheme.titleMedium),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
          ]),
          Expanded(
            child: TabBarView(children: [
              ListView(padding: const EdgeInsets.all(16), children: [
                ListTile(contentPadding: EdgeInsets.zero, title: const Text('VAT collected on sales'), trailing: Text(formatNpr(output))),
                ListTile(contentPadding: EdgeInsets.zero, title: const Text('VAT paid on purchases'), trailing: Text(formatNpr(input))),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(output >= input ? 'VAT to pay' : 'VAT credit carried forward', style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Text(formatNpr((output - input).abs()), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.account_balance),
                  label: const Text('Record VAT paid to IRD'),
                  onPressed: output <= 0 ? null : () => _pay(output, input),
                ),
                const SizedBox(height: 16),
                const Text('File the return from these figures with your accountant; the app does not submit to IRD.', style: TextStyle(color: Colors.grey)),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [cell('Date / No.'), cell('Buyer / PAN'), cell('Taxable', end: true), cell('VAT', end: true), cell('Total', end: true)]),
                const Divider(),
                for (final r in sales)
                  Row(children: [
                    cell('${formatBs(r.date)}\n${r.number}'),
                    cell('${r.buyer}\n${r.pan}'),
                    cell(formatNpr(r.taxable), end: true),
                    cell(formatNpr(r.vat), end: true),
                    cell('${formatNpr(r.total)}${r.exempt != 0 ? '\nexempt ${formatNpr(r.exempt)}' : ''}', end: true),
                  ]),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [cell('Date / Bill'), cell('Supplier / PAN'), cell('Taxable', end: true), cell('VAT', end: true), cell('Total', end: true)]),
                const Divider(),
                for (final r in purchases)
                  Row(children: [
                    cell('${formatBs(r.date)}\n${r.billNo}'),
                    cell('${r.supplier}\n${r.pan}'),
                    cell(formatNpr(r.taxable), end: true),
                    cell(formatNpr(r.vat), end: true),
                    cell(formatNpr(r.total), end: true),
                  ]),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _pay(double output, double input) async {
    var account = widget.cash.moneyAccounts.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('VAT for $_label'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Pay ${formatNpr(output > input ? output - input : 0)} (collected ${formatNpr(output)} less ${formatNpr(input)} paid on purchases).'),
            DropdownButtonFormField<String>(
              initialValue: account,
              decoration: const InputDecoration(labelText: 'Paid from'),
              items: [for (final a in widget.cash.moneyAccounts) DropdownMenuItem(value: a, child: Text(accountName(a)))],
              onChanged: (v) => setState(() => account = v ?? account),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      widget.cash.vatPaid(output, input, account, _label, userName: widget.userName);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('VAT payment recorded')));
    } on AccountingException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
