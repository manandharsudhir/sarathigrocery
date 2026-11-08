import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/widgets/customer_picker.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/invoice_screen.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/sales/presentation/widgets/cart_editor.dart';
import 'package:sarathigrocery/core/widgets/correction_dialogs.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key, required this.sales, required this.inventory, required this.customers, required this.auth, this.corrects});

  final SalesController sales;
  final InventoryController inventory;
  final CustomersController customers;
  final AuthController auth;

  /// Correcting this sale: the form starts as it was, and saving cancels it
  /// and records this one in its place.
  final Sale? corrects;

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  Customer? _customer;
  final List<CartLine> _lines = [];
  String _account = 'cash';
  String? _error;

  /// Blank = paid in full; less than the total puts the rest on udharo
  /// (customers only).
  final _paid = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  final _reference = TextEditingController();

  /// What's paid now (null when the entry isn't a number).
  double? get _paidNow {
    final text = _paid.text.trim();
    return _customer == null || text.isEmpty ? _bill.total : double.tryParse(text);
  }

  double get _onCredit => (_bill.total - (_paidNow ?? 0)).clamp(0.0, double.infinity);
  bool get _isCredit => _onCredit > 0.005;
  bool get _partPaid => _isCredit && (_paidNow ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    final old = widget.corrects;
    if (old == null) return;
    _customer = old.customer;
    _account = old.account;
    // Payments already made on the old bill move to the new one.
    if (old.isCredit) _paid.text = '0';
    for (final i in old.items) {
      _lines.add(CartLine(i.product, i.product.sellUnit(i.unit), i.unitPrice)..qty.text = formatQty(i.qty));
    }
  }

  /// Stock the corrected sale gives back in the same save.
  Map<Product, double> get _returning => {
        for (final i in widget.corrects?.items ?? const <SaleItem>[]) i.product: i.baseQty,
      };

  @override
  void dispose() {
    _paid.dispose();
    _reference.dispose();
    super.dispose();
  }

  bool get _allowBelowMinimum => widget.auth.can(Permission.sellBelowMinimum);

  double get _lines$ => _lines.fold(0.0, (sum, l) => sum + l.total);

  /// VAT on the cart (VAT shops), and what the customer pays.
  ({double vat, double total}) get _bill {
    final terms = widget.sales.vatTerms;
    final taxable = _lines.where((l) => !l.product.vatExempt).fold(0.0, (sum, l) => sum + l.total);
    final vat = vatOn(taxable, terms);
    return (vat: vat, total: _lines$ + (terms != null && !terms.included ? vat : 0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.corrects == null ? 'New Sale' : 'Correct sale ${widget.corrects!.invoiceNumber ?? widget.corrects!.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CustomerPicker(
            customers: widget.customers.customers,
            selected: _customer,
            label: 'Customer (optional)',
            walkInLabel: 'Walk-in / Cash customer',
            onSelected: (c) => setState(() => _customer = c),
          ),
          if (_customer != null) ...[
            TextField(
              controller: _paid,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Paid now',
                hintText: formatNpr(_bill.total),
                helperText: 'Blank = paid in full · 0 = all on udharo',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_isCredit) Text('On credit (udharo): ${formatNpr(_onCredit)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (_isCredit && _customer!.outstandingBalance + _onCredit > _customer!.creditLimit)
            Text(
              'Over ${_customer!.name}\'s credit limit by ${formatNpr(_customer!.outstandingBalance + _onCredit - _customer!.creditLimit)}. You can still sell; the owner is told.',
              style: const TextStyle(color: Colors.orange),
            ),
          if (_partPaid) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(label: Text(paymentMethodLabel(m)), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
              ],
            ),
            if (_method != PaymentMethod.cash)
              TextField(controller: _reference, decoration: InputDecoration(labelText: _method == PaymentMethod.cheque ? 'Cheque number' : 'Transaction / reference id')),
          ],
          if (!_isCredit)
            DropdownButtonFormField<String>(
              initialValue: _account,
              decoration: const InputDecoration(labelText: 'Paid into'),
              items: [for (final a in widget.sales.moneyAccounts) DropdownMenuItem(value: a, child: Text(accountName(a)))],
              onChanged: (v) => setState(() => _account = v ?? _account),
            ),
          const SizedBox(height: 16),
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          CartEditor(
            products: widget.inventory.products.where((p) => p.isActive).toList(),
            lines: _lines,
            onChanged: () => setState(() => _error = null),
            priceFor: (p, unit) => p.floorFor(unit.label) ?? 0,
            allowBelowMinimum: _allowBelowMinimum,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          if (widget.sales.issuesTaxInvoices) Text('VAT ${widget.sales.vatTerms!.included ? '(included)' : ''}: ${formatNpr(_bill.vat)}'),
          Text('Total: ${formatNpr(_bill.total)}', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _lines.isEmpty || _saving ? null : _submit,
            child: Text(widget.corrects == null ? 'Complete Sale' : 'Save correction'),
          ),
        ),
      ),
    );
  }

  bool _saving = false;

  Future<void> _submit() async {
    final problem = cartProblem(_lines, checkMinimum: true, allowBelowMinimum: _allowBelowMinimum, checkStock: true, returning: _returning);
    final paidNow = _paidNow;
    final paidProblem = paidNow == null || paidNow < 0
        ? 'Enter the amount paid now.'
        : paidNow > _bill.total + 0.005
            ? 'Paid now can\'t be more than the bill (${formatNpr(_bill.total)}).'
            : null;
    if (problem != null || paidProblem != null) {
      setState(() => _error = problem ?? paidProblem);
      return;
    }
    final isCredit = _isCredit;
    final partPaid = _partPaid;
    final user = widget.auth.currentUser!;
    final items = [
      for (final l in _lines) SaleItem(product: l.product, qty: l.qtyValue, unitPrice: l.priceValue, unit: l.unit.label, size: l.unit.size),
    ];

    final old = widget.corrects;
    var reason = '';
    if (old != null) {
      final why = await askReason(context,
          title: 'Correct sale ${old.invoiceNumber ?? old.id}',
          message: 'The old sale is cancelled${old.invoiceNumber == null ? '' : ' with a credit note'} and this one saved in its place. Both stay on record.',
          action: 'Save correction');
      if (why == null || !mounted) return;
      reason = why;
    }

    final Sale sale;
    setState(() => _saving = true);
    try {
      sale = await widget.sales.sell(
        items: items,
        isCredit: isCredit,
        customer: _customer,
        userName: user.name,
        userId: user.id,
        allowBelowMinimum: _allowBelowMinimum,
        account: _account,
        paidNow: partPaid ? (amount: paidNow!, method: _method, reference: _reference.text, collector: user) : null,
        corrects: old,
        reason: reason,
      );
    } on PaymentException catch (e) {
      setState(() => _error = e.message);
      return;
    } on BelowMinimumPriceException catch (e) {
      setState(() => _error = e.message);
      return;
    } on UnpricedProductException catch (e) {
      setState(() => _error = e.message);
      return;
    } on AccountingException catch (e) {
      setState(() => _error = e.message);
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    final needsApproval = sale.flaggedForApproval;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(needsApproval ? 'Sale Recorded: over credit limit' : (sale.invoiceNumber == null ? 'Sale Complete' : 'Tax invoice ${sale.invoiceNumber}')),
        content: Text(
          '${_customer?.name ?? 'Walk-in customer'}\n'
          'Total: ${formatNpr(sale.total)}\n'
          '${partPaid ? 'Paid ${formatNpr(paidNow!)} · ${formatNpr(sale.total - paidNow)} on udharo' : isCredit ? 'Recorded as Udharo (Credit)' : 'Paid into ${accountName(_account)}'}'
          '${needsApproval ? '\n\nThis takes the customer over their credit limit. Recorded, and the owner is told.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context)
              ..pop()
              ..pushReplacement(MaterialPageRoute(builder: (_) => InvoiceScreen(sale: sale, sales: widget.sales, auth: widget.auth))),
            child: const Text('View bill'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
