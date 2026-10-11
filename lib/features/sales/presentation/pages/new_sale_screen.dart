import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
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

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key, required this.sales, required this.inventory, required this.customers, required this.auth});

  final SalesController sales;
  final InventoryController inventory;
  final CustomersController customers;
  final AuthController auth;

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  Customer? _customer;
  bool _isCredit = false;
  final List<CartLine> _lines = [];
  String _account = 'cash';
  String? _error;

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
      appBar: AppBar(title: const Text('New Sale')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownMenu<Customer?>(
            initialSelection: _customer,
            label: const Text('Customer (optional)'),
            expandedInsets: EdgeInsets.zero,
            enableFilter: true,
            requestFocusOnTap: true,
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: null, label: 'Walk-in / Cash customer'),
              for (final c in widget.customers.customers) DropdownMenuEntry(value: c, label: c.name),
            ],
            onSelected: (c) => setState(() {
              _customer = c;
              if (c == null) _isCredit = false;
            }),
          ),
          if (_customer != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Udharo (Credit)'),
              value: _isCredit,
              onChanged: (v) => setState(() => _isCredit = v),
            ),
          if (_isCredit && _customer != null && _customer!.outstandingBalance + _bill.total > _customer!.creditLimit)
            Text(
              'Over ${_customer!.name}\'s credit limit by ${formatNpr(_customer!.outstandingBalance + _bill.total - _customer!.creditLimit)}. You can still sell; the owner is told.',
              style: const TextStyle(color: Colors.orange),
            ),
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
            child: const Text('Complete Sale'),
          ),
        ),
      ),
    );
  }

  bool _saving = false;

  Future<void> _submit() async {
    final problem = cartProblem(_lines, checkMinimum: true, allowBelowMinimum: _allowBelowMinimum, checkStock: true);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final items = [
      for (final l in _lines) SaleItem(product: l.product, qty: l.qtyValue, unitPrice: l.priceValue, unit: l.unit.label, size: l.unit.size),
    ];

    final Sale sale;
    setState(() => _saving = true);
    try {
      sale = await widget.sales.sell(
        items: items,
        isCredit: _isCredit,
        customer: _customer,
        userName: widget.auth.currentUser?.name ?? '',
        userId: widget.auth.currentUser?.id,
        allowBelowMinimum: _allowBelowMinimum,
        account: _account,
      );
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
          '${_isCredit ? 'Recorded as Udharo (Credit)' : 'Paid into ${accountName(_account)}'}'
          '${needsApproval ? '\n\nThis takes the customer over their credit limit. Recorded, and the owner is told.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context)
              ..pop()
              ..pushReplacement(MaterialPageRoute(builder: (_) => InvoiceScreen(sale: sale, seller: widget.sales.seller))),
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
