import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/auth/domain/entities/permission.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product_pack.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_item.dart';
import 'package:sarathigrocery/core/widgets/correction_dialogs.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/widgets/cart_editor.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

class NewPurchaseScreen extends StatefulWidget {
  const NewPurchaseScreen({super.key, required this.purchasing, required this.suppliers, required this.inventory, required this.auth, this.corrects});

  final PurchasingController purchasing;
  final SuppliersController suppliers;
  final InventoryController inventory;
  final AuthController auth;

  /// Correcting this purchase: the form starts as it was, and saving takes
  /// it back out and records this one in its place.
  final Purchase? corrects;

  @override
  State<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends State<NewPurchaseScreen> {
  Supplier? _supplier;
  final List<CartLine> _lines = [];
  final _paidController = TextEditingController(text: '0');
  String _account = 'cash';
  final _billNo = TextEditingController();
  final _vat = TextEditingController();
  DateTime _billDate = DateTime.now();
  String? _error;

  /// Whoever manages products also sets new selling prices here.
  bool get _setsPrices => widget.auth.can(Permission.manageProducts);

  double get _total => _lines.fold(0.0, (sum, l) => sum + l.total) + (double.tryParse(_vat.text) ?? 0);

  @override
  void initState() {
    super.initState();
    final old = widget.corrects;
    if (old == null) return;
    _supplier = old.supplier;
    _paidController.text = formatQty(old.paidAmount);
    _account = old.account;
    _billNo.text = old.supplierBillNo;
    if (old.vatAmount > 0) _vat.text = formatQty(old.vatAmount);
    _billDate = old.supplierBillDate ?? old.date;
    for (final i in old.items) {
      _lines.add(CartLine(i.product, i.product.sellUnit(i.unit), i.unitCost)..qty.text = formatQty(i.qty));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.corrects == null ? 'New Purchase' : 'Correct purchase ${widget.corrects!.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownMenu<Supplier>(
            initialSelection: _supplier,
            label: const Text('Supplier'),
            expandedInsets: EdgeInsets.zero,
            enableFilter: true,
            requestFocusOnTap: true,
            dropdownMenuEntries: [for (final s in widget.suppliers.suppliers) DropdownMenuEntry(value: s, label: s.businessName)],
            onSelected: (s) => setState(() => _supplier = s),
          ),
          const SizedBox(height: 16),
          Text('Items', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          CartEditor(
            products: widget.inventory.products,
            lines: _lines,
            onChanged: () => setState(() => _error = null),
            priceFor: (product, unit) => product.purchasePrice * unit.size,
            priceLabel: 'Cost',
            showMinimum: false,
            editSellPrice: _setsPrices,
            startUnit: (p) => p.primary,
            marginPercent: widget.purchasing.marginPercent,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _billNo,
            decoration: InputDecoration(labelText: 'Supplier bill no.', helperText: widget.purchasing.recordsVat ? 'For the Purchase Book' : 'Optional: stops the same bill being entered twice'),
          ),
          if (widget.purchasing.recordsVat) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bill date'),
              subtitle: Text('${formatDate(_billDate)} · ${formatBs(_billDate)}'),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _billDate, firstDate: DateTime(2018), lastDate: DateTime.now());
                if (d != null) setState(() => _billDate = d);
              },
            ),
            TextField(
              controller: _vat,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'VAT on the bill', helperText: 'Costs above are without VAT'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _paidController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Paid now (NPR)'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _account,
            decoration: const InputDecoration(labelText: 'Paid from'),
            items: [for (final a in widget.purchasing.moneyAccounts) DropdownMenuItem(value: a, child: Text(accountName(a)))],
            onChanged: (v) => setState(() => _account = v ?? _account),
          ),
          const SizedBox(height: 24),
          Text('Total: ${formatNpr(_total)}', style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _supplier == null || _lines.isEmpty ? null : _submit,
            child: Text(widget.corrects == null ? 'Receive Stock' : 'Save correction'),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final problem = cartProblem(_lines);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final old = widget.corrects;
    final owner = widget.auth.currentUser?.role == UserRole.owner;
    final items = [for (final l in _lines) PurchaseItem(product: l.product, qty: l.qtyValue, unitCost: l.priceValue, unit: l.unit.label, size: l.unit.size)];
    final total = items.fold(0.0, (sum, i) => sum + i.lineTotal) + (double.tryParse(_vat.text) ?? 0);
    // Double entry checks: a bill number repeats only by mistake (owner may
    // override); same supplier and total today is only a warning.
    final sameBill = widget.purchasing.duplicateBill(_supplier!, _billNo.text, except: old);
    final sameTotal = sameBill == null ? widget.purchasing.similarToday(_supplier!, total, except: old) : null;
    if (sameBill != null &&
        !await confirmNotDuplicate(context, 'Bill ${sameBill.supplierBillNo} from ${_supplier!.businessName} is already entered (purchase ${sameBill.id}, ${formatDate(sameBill.date)}).',
            blocked: true, canOverride: owner)) {
      return;
    }
    if (!mounted) return;
    if (sameTotal != null &&
        !await confirmNotDuplicate(context, 'A purchase from ${_supplier!.businessName} for ${formatNpr(total)} was already entered today at ${formatTime(sameTotal.date)}.')) {
      return;
    }
    if (!mounted) return;
    var reason = '';
    if (old != null) {
      final why = await askReason(context,
          title: 'Correct purchase ${old.id}',
          message: 'The old purchase is taken back out and this one saved in its place, in one go. Both stay on record.',
          action: 'Save correction');
      if (why == null || !mounted) return;
      reason = why;
    }
    final userName = widget.auth.currentUser?.name ?? '';
    try {
      if (old == null) {
        widget.purchasing.createPurchase(
          supplier: _supplier!,
          items: items,
          paidAmount: double.tryParse(_paidController.text) ?? 0,
          userName: userName,
          account: _account,
          vatAmount: double.tryParse(_vat.text) ?? 0,
          supplierBillNo: _billNo.text.trim(),
          supplierBillDate: widget.purchasing.recordsVat ? _billDate : null,
        );
      } else {
        widget.purchasing.correctPurchase(
          old,
          reason,
          supplier: _supplier!,
          items: items,
          paidAmount: double.tryParse(_paidController.text) ?? 0,
          userName: userName,
          owner: owner,
          account: _account,
          vatAmount: double.tryParse(_vat.text) ?? 0,
          supplierBillNo: _billNo.text.trim(),
          supplierBillDate: widget.purchasing.recordsVat ? _billDate : null,
        );
      }
    } on AccountingException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    for (final l in _lines) {
      final price = double.tryParse(l.sellPrice.text);
      if (price == null) continue;
      final p = l.product;
      if (l.unit.size == 1 && l.unit.label == p.unitLabel) {
        widget.inventory.updateProduct(p, userName: userName, unitPrice: price);
      } else {
        widget.inventory.updateProduct(p, userName: userName, packs: [
          for (final k in p.packs) k.label == l.unit.label ? ProductPack(label: k.label, size: k.size, price: price) : k,
        ]);
      }
    }
    widget.purchasing.notifyPricesNeeded({for (final l in _lines) l.product}, userName: userName);
    Navigator.pop(context);
  }
}
