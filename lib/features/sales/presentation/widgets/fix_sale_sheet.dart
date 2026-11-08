import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/auth/presentation/controllers/auth_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/new_sale_screen.dart';

/// Everything that fixes a sale: correct a mistake, take some items back,
/// or cancel / return it whole. Tax invoices get credit notes (online).
void showFixSaleSheet(BuildContext context, Sale sale,
    {required SalesController sales, required InventoryController inventory, required CustomersController customers, required AuthController auth}) {
  final whole = sale.status == SaleStatus.completed && sales.doorReturnsOf(sale).every((r) => r.status != SaleStatus.completed);
  showModalBottomSheet(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text('Fix sale ${sale.invoiceNumber ?? sale.id}', style: Theme.of(sheet).textTheme.titleMedium)),
        if (sales.canCorrect(sale))
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Correct a mistake'),
            subtitle: const Text('Wrong item, quantity, price or customer: enter it again'),
            onTap: () {
              Navigator.pop(sheet);
              Navigator.push(context, MaterialPageRoute(builder: (_) => NewSaleScreen(sales: sales, inventory: inventory, customers: customers, auth: auth, corrects: sale)));
            },
          ),
        if (sales.canReturnItems(sale))
          ListTile(
            leading: const Icon(Icons.assignment_return_outlined),
            title: const Text('Some items came back'),
            onTap: () {
              Navigator.pop(sheet);
              _returnItemsSheet(context, sale, sales, auth);
            },
          ),
        if (whole)
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Cancel or return the whole sale'),
            onTap: () {
              Navigator.pop(sheet);
              _cancelReturnSheet(context, sale, sales, auth);
            },
          ),
      ]),
    ),
  );
}

void _returnItemsSheet(BuildContext context, Sale sale, SalesController sales, AuthController auth) {
  final left = sales.remainingOn(sale);
  final qty = [for (final _ in sale.items) TextEditingController()];
  final reason = TextEditingController();
  String? error;
  var saving = false;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sheet).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Items brought back', style: Theme.of(sheet).textTheme.titleMedium),
            Text(sale.isCredit ? 'Taken off what they owe.' : 'Refunded from ${accountName(sale.account)}.'),
            for (var i = 0; i < sale.items.length; i++)
              if (left[i] > 1e-9)
                Row(children: [
                  Expanded(child: Text('${sale.items[i].product.name} (${formatQty(left[i])} ${sale.items[i].unit} at ${formatNpr(sale.items[i].unitPrice)})')),
                  SizedBox(
                    width: 90,
                    child: TextField(controller: qty[i], keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Back', suffixText: sale.items[i].unit)),
                  ),
                ]),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (required)')),
            if (error != null) Text(error!, style: TextStyle(color: Theme.of(sheet).colorScheme.error)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final returned = {for (var i = 0; i < qty.length; i++) if ((double.tryParse(qty[i].text) ?? 0) > 0) i: double.parse(qty[i].text)};
                      final navigator = Navigator.of(sheet);
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => saving = true);
                      try {
                        final back = await sales.returnItems(sale, returned, reason.text, userName: auth.currentUser?.name ?? '', userId: auth.currentUser?.id);
                        navigator.pop();
                        messenger.showSnackBar(SnackBar(content: Text('${formatNpr(-back.total)} returned${back.invoiceNumber == null ? '' : ' · credit note ${back.invoiceNumber}'}.')));
                      } on AccountingException catch (e) {
                        setState(() => error = e.message);
                      } finally {
                        if (sheet.mounted) setState(() => saving = false);
                      }
                    },
              child: const Text('Record return'),
            ),
          ]),
        ),
      ),
    ),
  );
}

void _cancelReturnSheet(BuildContext context, Sale sale, SalesController sales, AuthController auth) {
  final reasonController = TextEditingController();
  Future<void> reverse(BuildContext sheetContext, SaleStatus status) async {
    if (reasonController.text.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(sheetContext);
    final navigator = Navigator.of(sheetContext);
    try {
      await sales.reverse(sale, status, reasonController.text.trim(), userName: auth.currentUser?.name ?? '');
      navigator.pop();
      final note = sales.creditNoteFor(sale);
      if (note != null) messenger.showSnackBar(SnackBar(content: Text('Credit note ${note.number} issued.')));
    } on AccountingException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cancel or return sale ${sale.id}', style: Theme.of(sheetContext).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Reason (required)')),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => reverse(sheetContext, SaleStatus.cancelled), child: const Text('Cancel Sale'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: () => reverse(sheetContext, SaleStatus.returned), child: const Text('Return Goods'))),
            ],
          ),
        ],
      ),
    ),
  );
}
