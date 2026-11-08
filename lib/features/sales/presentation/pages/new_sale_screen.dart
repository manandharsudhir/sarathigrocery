import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/widgets/correction_dialogs.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/pages/customer_form_sheet.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_item.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/invoice_screen.dart';
import 'package:sarathigrocery/features/sales/presentation/widgets/cart_editor.dart';

/// For customer screens: opens New Sale with that customer picked.
void Function(BuildContext context, Customer customer) startSaleFor(SalesController sales, InventoryController inventory, CustomersController customers, AuthController auth) =>
    (context, customer) => Navigator.push(context, MaterialPageRoute(builder: (_) => NewSaleScreen(sales: sales, inventory: inventory, customers: customers, auth: auth, customer: customer)));

/// How a sale is paid, chosen at checkout.
enum _Pay { full, udharo, part }

/// New Sale, items first: tap products to add them (tap again for more),
/// adjust quantities with − / +, tap a line for its unit and price. The
/// customer chip (walk-in by default) can be set any time; "Charge" opens
/// checkout: paid in full, udharo, or part paid.
class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key, required this.sales, required this.inventory, required this.customers, required this.auth, this.corrects, this.customer});

  final SalesController sales;
  final InventoryController inventory;
  final CustomersController customers;
  final AuthController auth;

  /// Correcting this sale: the screen starts as it was, and saving cancels
  /// it and records this one in its place.
  final Sale? corrects;

  /// Start with this customer picked (New sale from the customer's screen).
  final Customer? customer;

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  Customer? _customer;
  final List<CartLine> _lines = [];
  final _search = TextEditingController();
  String _query = '';
  String? _error;
  bool _saving = false;

  // Checkout choices, kept if the sheet is closed and opened again.
  _Pay _pay = _Pay.full;
  String _account = 'cash';
  PaymentMethod _method = PaymentMethod.cash;
  final _paidAmount = TextEditingController();
  final _reference = TextEditingController();

  bool get _allowBelowMinimum => widget.auth.can(Permission.sellBelowMinimum);

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    final old = widget.corrects;
    if (old == null) return;
    _customer = old.customer;
    _account = old.account;
    // Payments already made on the old bill move to the new one.
    _pay = old.isCredit ? _Pay.udharo : _Pay.full;
    for (final i in old.items) {
      _lines.add(CartLine(i.product, i.product.sellUnit(i.unit), i.unitPrice)..qty.text = formatQty(i.qty));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _paidAmount.dispose();
    _reference.dispose();
    super.dispose();
  }

  /// Stock the corrected sale gives back in the same save.
  Map<Product, double> get _returning => {
        for (final i in widget.corrects?.items ?? const <SaleItem>[]) i.product: i.baseQty,
      };

  double _available(Product p) => p.availableStock + (_returning[p] ?? 0);

  /// VAT on the cart (VAT shops), and what the customer pays.
  ({double vat, double total}) get _bill {
    final terms = widget.sales.vatTerms;
    final lines = _lines.fold(0.0, (sum, l) => sum + l.total);
    final vat = vatOn(_lines.where((l) => !l.product.vatExempt).fold(0.0, (sum, l) => sum + l.total), terms);
    return (vat: vat, total: lines + (terms != null && !terms.included ? vat : 0));
  }

  CartLine? _lineOf(Product p) => _lines.where((l) => l.product.id == p.id).firstOrNull;

  void _changed() => setState(() => _error = null);

  void _add(Product p) {
    final line = _lineOf(p);
    if (line != null) {
      line.qty.text = formatQty(line.qtyValue + 1);
    } else {
      final unit = p.sellUnit(p.saleUnit);
      _lines.add(CartLine(p, unit, p.floorFor(unit.label) ?? 0));
    }
    _changed();
  }

  void _step(CartLine line, double by) {
    final next = line.qtyValue + by;
    if (next <= 0) {
      _lines.remove(line);
    } else {
      line.qty.text = formatQty(next);
    }
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.inventory.products.where((p) => p.isActive).toList();
    final inCart = {for (final l in _lines) l.product.id};
    final others = _query.isEmpty
        ? widget.sales.suggestedProducts(_customer).where((p) => p.isActive && !inCart.contains(p.id)).toList()
        : products.where((p) => p.matches(_query) && !inCart.contains(p.id)).take(30).toList();
    // Nothing sold yet: show the catalogue.
    if (_query.isEmpty && others.isEmpty) others.addAll(products.where((p) => !inCart.contains(p.id)).take(40));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.corrects == null ? 'New Sale' : 'Correct sale ${widget.corrects!.invoiceNumber ?? widget.corrects!.id}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _CustomerChip(customer: _customer, adding: _bill.total, onTap: _pickCustomer),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search products (name or SKU)',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                if (_lines.isNotEmpty) _header(context, 'In this sale'),
                for (final line in _lines) _cartRow(line),
                _header(context, _query.isNotEmpty ? 'Results' : (_customer != null ? '${_customer!.name} usually buys' : 'Best sellers')),
                if (others.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No products found.')),
                for (final p in others) _productRow(p),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_error != null)
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('${_lines.length} item${_lines.length == 1 ? '' : 's'}${widget.sales.issuesTaxInvoices ? ' · VAT ${formatNpr(_bill.vat)}' : ''}', style: theme.textTheme.bodySmall),
                    Text(formatNpr(_bill.total), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ]),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(140, 52)),
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: const Text('Charge'),
                  onPressed: _lines.isEmpty || _saving ? null : _charge,
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  Widget _productRow(Product p) {
    final available = _available(p);
    final price = p.floorFor(p.sellUnit(p.saleUnit).label);
    final out = available <= 1e-9;
    return ListTile(
      enabled: !out,
      title: Text(p.name),
      subtitle: Text(out ? 'Out of stock' : '${p.describeQty(available)} available'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(price == null ? 'no price' : '${formatNpr(price)}/${p.sellUnit(p.saleUnit).label}'),
        const SizedBox(width: 8),
        Icon(Icons.add_circle, color: out ? null : Theme.of(context).colorScheme.primary),
      ]),
      onTap: out ? null : () => _add(p),
    );
  }

  Widget _cartRow(CartLine line) {
    final theme = Theme.of(context);
    final below = line.belowMinimum;
    final over = line.baseQty > _available(line.product) + 1e-9;
    final note = [
      '${formatNpr(line.priceValue)}/${line.unit.label}',
      if (below) 'below minimum',
      if (over) 'only ${line.product.describeQty(_available(line.product))} available',
    ].join(' · ');
    // Name, price and line total on the left; a big − qty + on the right.
    return InkWell(
      onTap: () => _editLine(line),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.product.name, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(note, style: theme.textTheme.bodySmall?.copyWith(color: below || over ? (below && _allowBelowMinimum && !over ? Colors.orange : theme.colorScheme.error) : null)),
              Text(formatNpr(line.total), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
          IconButton.filledTonal(
            tooltip: line.qtyValue <= 1 ? 'Remove' : 'One less',
            icon: Icon(line.qtyValue <= 1 ? Icons.delete_outline : Icons.remove),
            onPressed: () => _step(line, -1),
          ),
          InkWell(
            onTap: () => _editLine(line),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(formatQty(line.qtyValue), style: theme.textTheme.titleMedium),
                Text(line.unit.label, style: theme.textTheme.bodySmall),
              ]),
            ),
          ),
          IconButton.filledTonal(tooltip: 'One more', icon: const Icon(Icons.add), onPressed: () => _step(line, 1)),
        ]),
      ),
    );
  }

  /// Unit, quantity and price of one line (and remove).
  Future<void> _editLine(CartLine line) async {
    final last = _customer == null ? null : widget.sales.lastPrice(_customer!, line.product, line.unit.label);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, setSheet) {
        final minimum = line.product.floorFor(line.unit.label) ?? 0;
        final lastNow = _customer == null ? null : widget.sales.lastPrice(_customer!, line.product, line.unit.label);
        void update() {
          setSheet(() {});
          _changed();
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sheet).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(line.product.name, style: Theme.of(sheet).textTheme.titleMedium),
            if (line.product.sellUnits.length > 1) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                for (final ProductPack u in line.product.sellUnits)
                  ChoiceChip(
                    label: Text(u.size == 1 ? u.label : '${u.label} (${formatQty(u.size)} ${line.product.unitLabel})'),
                    selected: line.unit.label == u.label,
                    onSelected: (_) {
                      line.unit = u;
                      line.price.text = formatQty(line.product.floorFor(u.label) ?? 0);
                      update();
                    },
                  ),
              ]),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: line.qty,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Quantity', suffixText: line.unit.label),
                  onChanged: (_) => update(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: line.price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Price / ${line.unit.label}', helperText: 'Minimum ${formatNpr(minimum)}'),
                  onChanged: (_) => update(),
                ),
              ),
            ]),
            if ((lastNow ?? last) != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('${_customer!.name} paid ${formatNpr((lastNow ?? last)!)}/${line.unit.label} last time')),
            if (line.belowMinimum)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_allowBelowMinimum ? 'Below the minimum: allowed, and the owner is told.' : 'Below the minimum price: you can\'t sell at this price.',
                    style: TextStyle(color: _allowBelowMinimum ? Colors.orange : Theme.of(sheet).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
                onPressed: () {
                  _lines.remove(line);
                  _changed();
                  Navigator.pop(sheet);
                },
              ),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(sheet), child: Text('Done · ${formatNpr(line.total)}')),
            ]),
          ]),
        );
      }),
    );
    // A cleared or zero quantity removes the line.
    if (_lines.contains(line) && line.qtyValue <= 0) _lines.remove(line);
    _changed();
  }

  /// Customer search: recent first, walk-in, or add a new one.
  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<({Customer? customer})>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => _CustomerSearch(
        customers: widget.customers.customers,
        recent: widget.sales.recentCustomers,
        canAdd: widget.auth.can(Permission.createCustomers) || widget.auth.can(Permission.manageCustomers),
        onAdd: () async {
          final created = await showCustomerFormSheet(sheet, widget.customers, widget.auth);
          if (created != null && sheet.mounted) Navigator.pop(sheet, (customer: created));
        },
      ),
    );
    if (picked == null) return;
    setState(() {
      _customer = picked.customer;
      if (_customer == null) _pay = _Pay.full;
      _error = null;
    });
  }

  /// Checks the cart, then opens checkout.
  Future<void> _charge() async {
    final problem = cartProblem(_lines, checkMinimum: true, allowBelowMinimum: _allowBelowMinimum, checkStock: true, returning: _returning);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, setSheet) => _checkout(sheet, setSheet)),
    );
    if (done == true) await _complete();
  }

  Widget _checkout(BuildContext sheet, StateSetter setSheet) {
    final theme = Theme.of(sheet);
    final total = _bill.total;
    final c = _customer;
    final paidPart = double.tryParse(_paidAmount.text.trim());
    final onCredit = c == null ? 0.0 : (_pay == _Pay.udharo ? total : _pay == _Pay.part ? (total - (paidPart ?? 0)).clamp(0.0, total) : 0.0);
    final overLimit = c != null && onCredit > 0 && c.outstandingBalance + onCredit > c.creditLimit;
    void set(VoidCallback f) {
      setSheet(f);
      setState(() {});
    }

    String? problem() {
      if (_pay != _Pay.part) return null;
      if (paidPart == null || paidPart <= 0) return 'Enter what they pay now.';
      if (paidPart >= total - 0.005) return 'That\'s the whole bill: choose Paid in full.';
      if (_method != PaymentMethod.cash && _reference.text.trim().isEmpty) return 'Enter the ${paymentMethodLabel(_method)} reference.';
      return null;
    }

    final error = problem();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sheet).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${c?.name ?? 'Walk-in customer'} · ${formatNpr(total)}', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (c != null)
            SegmentedButton<_Pay>(
              segments: const [
                ButtonSegment(value: _Pay.full, label: Text('Paid in full'), icon: Icon(Icons.payments_outlined)),
                ButtonSegment(value: _Pay.udharo, label: Text('Udharo'), icon: Icon(Icons.menu_book_outlined)),
                ButtonSegment(value: _Pay.part, label: Text('Part paid'), icon: Icon(Icons.call_split)),
              ],
              selected: {_pay},
              onSelectionChanged: (v) => set(() => _pay = v.first),
            ),
          if (_pay == _Pay.full || c == null) ...[
            const SizedBox(height: 12),
            Text('Paid into', style: theme.textTheme.labelLarge),
            Wrap(spacing: 6, children: [
              for (final a in widget.sales.moneyAccounts) ChoiceChip(label: Text(accountName(a)), selected: _account == a, onSelected: (_) => set(() => _account = a)),
            ]),
          ],
          if (_pay == _Pay.part && c != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _paidAmount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Paid now', helperText: 'The rest goes on udharo: ${formatNpr(onCredit)}'),
              onChanged: (_) => set(() {}),
            ),
            Wrap(spacing: 6, children: [
              for (final m in PaymentMethod.values) ChoiceChip(label: Text(paymentMethodLabel(m)), selected: _method == m, onSelected: (_) => set(() => _method = m)),
            ]),
            if (_method != PaymentMethod.cash)
              TextField(
                controller: _reference,
                decoration: InputDecoration(labelText: _method == PaymentMethod.cheque ? 'Cheque number' : 'Transaction / reference id'),
                onChanged: (_) => set(() {}),
              ),
          ],
          if (c != null && _pay == _Pay.udharo) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${formatNpr(total)} goes on ${c.name}\'s udharo.')),
          if (overLimit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Over ${c.name}\'s credit limit by ${formatNpr(c.outstandingBalance + onCredit - c.creditLimit)}. You can still sell; the owner is told.',
                  style: const TextStyle(color: Colors.orange)),
            ),
          if (error != null && _pay == _Pay.part && _paidAmount.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error, style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: error == null ? () => Navigator.pop(sheet, true) : null,
            child: Text(widget.corrects == null ? 'Complete sale' : 'Save correction'),
          ),
        ]),
      ),
    );
  }

  Future<void> _complete() async {
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
    final c = _customer;
    final pay = c == null ? _Pay.full : _pay;
    final user = widget.auth.currentUser!;
    final paidPart = double.tryParse(_paidAmount.text.trim()) ?? 0;
    final items = [for (final l in _lines) SaleItem(product: l.product, qty: l.qtyValue, unitPrice: l.priceValue, unit: l.unit.label, size: l.unit.size)];

    final Sale sale;
    setState(() => _saving = true);
    try {
      sale = await widget.sales.sell(
        items: items,
        isCredit: pay != _Pay.full,
        customer: c,
        userName: user.name,
        userId: user.id,
        allowBelowMinimum: _allowBelowMinimum,
        account: _account,
        paidNow: pay == _Pay.part ? (amount: paidPart, method: _method, reference: _reference.text, collector: user) : null,
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
          '${c?.name ?? 'Walk-in customer'}\n'
          'Total: ${formatNpr(sale.total)}\n'
          '${switch (pay) {
            _Pay.part => 'Paid ${formatNpr(paidPart)} · ${formatNpr(sale.total - paidPart)} on udharo',
            _Pay.udharo => 'Recorded as Udharo (Credit)',
            _Pay.full => 'Paid into ${accountName(_account)}',
          }}'
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

/// "Walk-in", or the customer with what they owe and their limit (orange
/// when [adding] would take them over it).
class _CustomerChip extends StatelessWidget {
  const _CustomerChip({required this.customer, required this.adding, required this.onTap});

  final Customer? customer;
  final double adding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final over = c != null && c.outstandingBalance + adding > c.creditLimit;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: Icon(c == null ? Icons.directions_walk : Icons.person),
        title: Text(c?.name ?? 'Walk-in customer', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: c == null
            ? const Text('Tap to pick a customer')
            : Text('Owes ${formatNpr(c.outstandingBalance)} · limit ${formatNpr(c.creditLimit)}', style: TextStyle(color: over ? Colors.orange : null)),
        trailing: const Icon(Icons.swap_horiz),
        onTap: onTap,
      ),
    );
  }
}

/// Pops `(customer: c)`; `(customer: null)` is walk-in.
class _CustomerSearch extends StatefulWidget {
  const _CustomerSearch({required this.customers, required this.recent, required this.canAdd, required this.onAdd});

  final List<Customer> customers;
  final List<Customer> recent;
  final bool canAdd;
  final VoidCallback onAdd;

  @override
  State<_CustomerSearch> createState() => _CustomerSearchState();
}

class _CustomerSearchState extends State<_CustomerSearch> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list = q.isEmpty
        ? [...widget.recent, ...widget.customers.where((c) => !widget.recent.contains(c))]
        : widget.customers.where((c) => c.name.toLowerCase().contains(q) || c.phone.contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Name or phone', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: ListView(children: [
              ListTile(leading: const Icon(Icons.directions_walk), title: const Text('Walk-in customer'), onTap: () => Navigator.pop(context, (customer: null))),
              if (widget.canAdd) ListTile(leading: const Icon(Icons.person_add_alt), title: const Text('New customer'), onTap: widget.onAdd),
              const Divider(),
              for (final c in list)
                ListTile(
                  leading: Icon(widget.recent.contains(c) && q.isEmpty ? Icons.history : Icons.person_outline),
                  title: Text(c.name),
                  subtitle: Text([if (c.phone.isNotEmpty) c.phone, 'owes ${formatNpr(c.outstandingBalance)}'].join(' · ')),
                  onTap: () => Navigator.pop(context, (customer: c)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
