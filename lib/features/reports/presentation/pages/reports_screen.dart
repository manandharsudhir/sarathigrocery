import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/bs_date.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/audit/domain/entities/audit_log_entry.dart';
import 'package:sarathigrocery/features/reports/domain/daily_summary.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/adjustment_type.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/sales/presentation/pages/invoice_screen.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/presentation/controllers/settings_controller.dart';


class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    super.key,
    required this.sales,
    required this.purchasing,
    required this.cash,
    required this.inventory,
    required this.customers,
    required this.suppliers,
    required this.settings,
    required this.accounts,
    required this.daily,
    required this.onExportDaily,
    this.corrections,
  });

  /// Owner only (the audit log): every reversal and correction.
  final List<AuditLogEntry> Function()? corrections;

  final SalesController sales;
  final PurchasingController purchasing;
  final CashController cash;
  final InventoryController inventory;
  final CustomersController customers;
  final SuppliersController suppliers;
  final SettingsController settings;

  /// Profit & Loss, Balance Sheet and the rest live in Accounts.
  final WidgetBuilder accounts;

  /// Daily figures for a range, and sharing them as CSV + PDF.
  final DailySummary Function(DateTime from, DateTime to) daily;
  final Future<void> Function(DateTime from, DateTime to) onExportDaily;

  @override
  Widget build(BuildContext context) {
    final hasSuppliers = settings.has(Feature.suppliers);
    final reports = <(String, IconData, WidgetBuilder)>[
      ('Daily Summary', Icons.calendar_view_day_outlined, (_) => _DailySummaryScreen(daily: daily, onExport: onExportDaily, accounts: cash.moneyAccounts, hasSuppliers: hasSuppliers)),
      ('Sales Report', Icons.point_of_sale, (_) => _SalesReportScreen(sales: sales)),
      ('Sales by Product', Icons.inventory_2_outlined, (_) => _SalesByProductScreen(sales: sales)),
      ('Sales by Customer', Icons.people_outline, (_) => _SalesByCustomerScreen(sales: sales)),
      if (hasSuppliers) ('Purchase Report', Icons.local_shipping_outlined, (_) => _PurchaseReportScreen(purchasing: purchasing)),
      ('Expense Report', Icons.receipt_long_outlined, (_) => _ExpenseReportScreen(cash: cash)),
      ('Profit & Loss and Balance Sheet', Icons.trending_up, accounts),
      ('Inventory Report', Icons.warehouse_outlined, (_) => _InventoryReportScreen(inventory: inventory)),
      ('Stock Movement', Icons.swap_vert, (_) => _StockMovementScreen(inventory: inventory, purchasing: purchasing, sales: sales)),
      ('Customer Outstanding', Icons.call_received, (_) => _CustomerOutstandingScreen(customers: customers)),
      if (hasSuppliers) ('Supplier Outstanding', Icons.call_made, (_) => _SupplierOutstandingScreen(suppliers: suppliers)),
      ('Payment Report', Icons.payments_outlined, (_) => _PaymentReportScreen(cash: cash)),
      ('Best-Selling Products', Icons.star_outline, (_) => _BestSellingScreen(sales: sales)),
      ('Employee Performance', Icons.badge_outlined, (_) => _EmployeePerformanceScreen(sales: sales)),
      if (corrections != null) ('Corrections', Icons.history_edu_outlined, (_) => CorrectionsScreen(corrections: corrections!)),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView.separated(
        itemCount: reports.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final (title, icon, builder) = reports[index];
          return ListTile(
            leading: Icon(icon),
            title: Text(title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: builder)),
          );
        },
      ),
    );
  }
}

/// Simple start/end date range row. Defaults to the last [days] days (a
/// month); a
/// longer pick than [maxDays] keeps its end and is cut to [maxDays].
/// Every reversal and correction: when, who, what and why (owner review).
class CorrectionsScreen extends StatefulWidget {
  const CorrectionsScreen({super.key, required this.corrections});

  final List<AuditLogEntry> Function() corrections;

  @override
  State<CorrectionsScreen> createState() => _CorrectionsScreenState();
}

class _CorrectionsScreenState extends State<CorrectionsScreen> {
  DateTimeRange? _range;
  String? _person;

  @override
  Widget build(BuildContext context) {
    final all = widget.corrections().where((e) => _range == null || _inRange(e.date, _range!)).toList();
    final people = {for (final e in all) e.userName}.toList()..sort();
    final rows = all.where((e) => _person == null || e.userName == _person).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Corrections')),
      body: Column(children: [
        _DateRangeBar(onChanged: (r) => setState(() => _range = r)),
        if (people.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              for (final p in people)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text('$p (${all.where((e) => e.userName == p).length})'),
                    selected: _person == p,
                    onSelected: (on) => setState(() => _person = on ? p : null),
                  ),
                ),
            ]),
          ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No corrections in this period.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final e = rows[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${e.action} · ${e.entityId}'),
                      subtitle: Text([
                        '${formatDate(e.date)} ${formatTime(e.date)} · ${e.userName}',
                        if (e.oldValue.isNotEmpty) e.oldValue,
                        if (e.newValue.isNotEmpty) e.newValue,
                      ].join('\n')),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _DateRangeBar extends StatefulWidget {
  const _DateRangeBar({required this.onChanged, this.days = 31, this.maxDays});

  final ValueChanged<DateTimeRange> onChanged;
  final int days;
  final int? maxDays;

  @override
  State<_DateRangeBar> createState() => _DateRangeBarState();
}

class _DateRangeBarState extends State<_DateRangeBar> {
  late DateTimeRange _range = DateTimeRange(start: DateTime.now().subtract(Duration(days: widget.days - 1)), end: DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChanged(_range));
  }

  Future<void> _pick() async {
    final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _range);
    if (picked != null) {
      final max = widget.maxDays;
      final cut = max != null && picked.duration.inDays >= max;
      setState(() => _range = cut ? DateTimeRange(start: picked.end.subtract(Duration(days: max - 1)), end: picked.end) : picked);
      if (cut && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Showing the last $max days of that range.')));
      widget.onChanged(_range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: OutlinedButton.icon(
        onPressed: _pick,
        icon: const Icon(Icons.date_range),
        label: Text('${formatDate(_range.start)} – ${formatDate(_range.end)}'),
      ),
    );
  }
}

bool _inRange(DateTime date, DateTimeRange range) =>
    !date.isBefore(range.start) && date.isBefore(range.end.add(const Duration(days: 1)));

class _SalesReportScreen extends StatefulWidget {
  const _SalesReportScreen({required this.sales});
  final SalesController sales;
  @override
  State<_SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<_SalesReportScreen> {
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final sales = widget.sales.sales.where((s) => s.status == SaleStatus.completed && (_range == null || _inRange(s.date, _range!))).toList();
    final total = sales.fold(0.0, (sum, s) => sum + s.total);
    return Scaffold(
      appBar: AppBar(title: const Text('Sales Report')),
      body: Column(
        children: [
          _DateRangeBar(onChanged: (r) => setState(() => _range = r)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('${sales.length} sales · ${formatNpr(total)}', style: Theme.of(context).textTheme.titleMedium)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: sales.map((s) => ListTile(
                    dense: true,
                    title: Text(s.customer?.name ?? 'Walk-in'),
                    subtitle: Text(formatDate(s.date)),
                    trailing: Text(formatNpr(s.total)),
                  )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesByProductScreen extends StatefulWidget {
  const _SalesByProductScreen({required this.sales});
  final SalesController sales;
  @override
  State<_SalesByProductScreen> createState() => _SalesByProductScreenState();
}

class _SalesByProductScreenState extends State<_SalesByProductScreen> {
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final Map<Product, (double, double)> byProduct = {};
    for (final s in widget.sales.sales.where((s) => s.status == SaleStatus.completed && (_range == null || _inRange(s.date, _range!)))) {
      for (final item in s.items) {
        final existing = byProduct[item.product] ?? (0.0, 0.0);
        byProduct[item.product] = (existing.$1 + item.baseQty, existing.$2 + item.lineTotal);
      }
    }
    final rows = byProduct.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    return Scaffold(
      appBar: AppBar(title: const Text('Sales by Product')),
      body: Column(
        children: [
          _DateRangeBar(onChanged: (r) => setState(() => _range = r)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: rows
                  .map((e) => ListTile(
                        title: Text(e.key.name),
                        subtitle: Text('${e.key.describeQty(e.value.$1)} sold'),
                        trailing: Text(formatNpr(e.value.$2)),
                        onTap: _range == null
                            ? null
                            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ProductSalesScreen(sales: widget.sales, product: e.key, range: _range!))),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Every completed sale line of [product] in [range], newest first.
class _ProductSalesScreen extends StatelessWidget {
  const _ProductSalesScreen({required this.sales, required this.product, required this.range});
  final SalesController sales;
  final Product product;
  final DateTimeRange range;

  @override
  Widget build(BuildContext context) {
    final lines = [
      for (final s in sales.sales.where((s) => s.status == SaleStatus.completed && _inRange(s.date, range)))
        for (final item in s.items.where((i) => i.product == product)) (s, item),
    ]..sort((a, b) => b.$1.date.compareTo(a.$1.date));
    final qty = lines.fold(0.0, (sum, l) => sum + l.$2.baseQty);
    final total = lines.fold(0.0, (sum, l) => sum + l.$2.lineTotal);
    return Scaffold(
      appBar: AppBar(title: Text('Sales of ${product.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${formatDate(range.start)} – ${formatDate(range.end)}', style: Theme.of(context).textTheme.bodySmall),
          Text('${product.describeQty(qty)} · ${formatNpr(total)}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (sale, item) in lines)
            ListTile(
              dense: true,
              title: Text(sale.customer?.name ?? 'Walk-in customer'),
              subtitle: Text([
                formatDate(sale.date),
                '${formatQty(item.qty)} ${item.unit}${item.size == 1 ? '' : ' (${formatQty(item.baseQty)} ${product.unitLabel})'}',
                '${formatNpr(item.unitPrice)}/${item.unit}',
              ].join(' · ')),
              trailing: Text(formatNpr(item.lineTotal)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceScreen(sale: sale, sales: sales))),
            ),
        ],
      ),
    );
  }
}

class _SalesByCustomerScreen extends StatelessWidget {
  const _SalesByCustomerScreen({required this.sales});
  final SalesController sales;

  @override
  Widget build(BuildContext context) {
    final Map<String, double> byCustomer = {};
    for (final s in sales.sales.where((s) => s.status == SaleStatus.completed)) {
      final name = s.customer?.name ?? 'Walk-in customer';
      byCustomer[name] = (byCustomer[name] ?? 0) + s.total;
    }
    final rows = byCustomer.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: const Text('Sales by Customer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: rows.map((e) => ListTile(title: Text(e.key), trailing: Text(formatNpr(e.value)))).toList(),
      ),
    );
  }
}

class _PurchaseReportScreen extends StatefulWidget {
  const _PurchaseReportScreen({required this.purchasing});
  final PurchasingController purchasing;
  @override
  State<_PurchaseReportScreen> createState() => _PurchaseReportScreenState();
}

class _PurchaseReportScreenState extends State<_PurchaseReportScreen> {
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final purchases = widget.purchasing.purchases.where((p) => _range == null || _inRange(p.date, _range!)).toList();
    final total = purchases.fold(0.0, (sum, p) => sum + p.total);
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Report')),
      body: Column(
        children: [
          _DateRangeBar(onChanged: (r) => setState(() => _range = r)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('${purchases.length} purchases · ${formatNpr(total)}', style: Theme.of(context).textTheme.titleMedium)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: purchases.map((p) => ListTile(dense: true, title: Text(p.supplier.businessName), subtitle: Text(formatDate(p.date)), trailing: Text(formatNpr(p.total)))).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseReportScreen extends StatefulWidget {
  const _ExpenseReportScreen({required this.cash});
  final CashController cash;
  @override
  State<_ExpenseReportScreen> createState() => _ExpenseReportScreenState();
}

class _ExpenseReportScreenState extends State<_ExpenseReportScreen> {
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final expenses = widget.cash.expenses.where((e) => _range == null || _inRange(e.date, _range!)).toList();
    final total = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final Map<String, double> byCategory = {};
    for (final e in expenses) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Expense Report')),
      body: Column(
        children: [
          _DateRangeBar(onChanged: (r) => setState(() => _range = r)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('${expenses.length} expenses · ${formatNpr(total)}', style: Theme.of(context).textTheme.titleMedium)),
          const Divider(),
          ...byCategory.entries.map((e) => ListTile(dense: true, title: Text(e.key), trailing: Text(formatNpr(e.value)))),
        ],
      ),
    );
  }
}

class _InventoryReportScreen extends StatelessWidget {
  const _InventoryReportScreen({required this.inventory});
  final InventoryController inventory;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: inventory.products.map((p) => ListTile(
              title: Text(p.name),
              subtitle: Text('${p.category} · reorder at ${formatQty(p.reorderLevel)} ${p.unitLabel}'),
              trailing: Text(
                '${p.describeQty(p.stockQty)} in stock',
                style: TextStyle(color: p.isLowStock ? Colors.red : null, fontWeight: p.isLowStock ? FontWeight.bold : null),
              ),
            )).toList(),
      ),
    );
  }
}

class _StockMovementScreen extends StatelessWidget {
  const _StockMovementScreen({required this.inventory, required this.purchasing, required this.sales});
  final InventoryController inventory;
  final PurchasingController purchasing;
  final SalesController sales;

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<DateTime, String>>[
      ...inventory.adjustments.map((a) => MapEntry(a.date, '${a.type.name} · ${a.product.name} · ${a.type == AdjustmentType.returned ? '+' : '-'}${a.product.describeQty(a.qty)}')),
      ...purchasing.purchases.expand((p) => p.items.map((i) => MapEntry(p.date, 'Purchase · ${i.product.name} · +${formatQty(i.qty)} ${i.unit}'))),
      ...sales.sales.where((s) => s.status == SaleStatus.completed).expand((s) => s.items.map((i) => MapEntry(s.date, 'Sale · ${i.product.name} · -${formatQty(i.qty)} ${i.unit}'))),
    ]..sort((a, b) => b.key.compareTo(a.key));

    return Scaffold(
      appBar: AppBar(title: const Text('Stock Movement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: entries.map((e) => ListTile(dense: true, title: Text(e.value), subtitle: Text(formatDate(e.key)))).toList(),
      ),
    );
  }
}

class _CustomerOutstandingScreen extends StatelessWidget {
  const _CustomerOutstandingScreen({required this.customers});
  final CustomersController customers;

  @override
  Widget build(BuildContext context) {
    final rows = customers.customers.where((c) => c.outstandingBalance > 0).toList()..sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Outstanding')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: rows.map((c) => ListTile(title: Text(c.name), trailing: Text(formatNpr(c.outstandingBalance)))).toList(),
      ),
    );
  }
}

class _SupplierOutstandingScreen extends StatelessWidget {
  const _SupplierOutstandingScreen({required this.suppliers});
  final SuppliersController suppliers;

  @override
  Widget build(BuildContext context) {
    final rows = suppliers.suppliers.where((s) => s.amountPayable > 0).toList()..sort((a, b) => b.amountPayable.compareTo(a.amountPayable));
    return Scaffold(
      appBar: AppBar(title: const Text('Supplier Outstanding')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: rows.map((s) => ListTile(title: Text(s.businessName), trailing: Text(formatNpr(s.amountPayable)))).toList(),
      ),
    );
  }
}

class _PaymentReportScreen extends StatefulWidget {
  const _PaymentReportScreen({required this.cash});
  final CashController cash;
  @override
  State<_PaymentReportScreen> createState() => _PaymentReportScreenState();
}

class _PaymentReportScreenState extends State<_PaymentReportScreen> {
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final entries = widget.cash.ledger.where((e) => _range == null || _inRange(e.date, _range!)).toList().reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Report')),
      body: Column(
        children: [
          _DateRangeBar(onChanged: (r) => setState(() => _range = r)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: entries.map((e) => ListTile(dense: true, title: Text(e.note), subtitle: Text('${e.account} · ${e.type.name} · ${formatDate(e.date)}'), trailing: Text('${e.isOutflow ? '-' : '+'}${formatNpr(e.amount)}'))).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BestSellingScreen extends StatelessWidget {
  const _BestSellingScreen({required this.sales});
  final SalesController sales;

  @override
  Widget build(BuildContext context) {
    final Map<Product, double> qtyByProduct = {};
    for (final s in sales.sales.where((s) => s.status == SaleStatus.completed)) {
      for (final item in s.items) {
        qtyByProduct[item.product] = (qtyByProduct[item.product] ?? 0) + item.baseQty;
      }
    }
    final rows = qtyByProduct.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: const Text('Best-Selling Products')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        itemBuilder: (context, index) => ListTile(
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(rows[index].key.name),
          trailing: Text(rows[index].key.describeQty(rows[index].value)),
        ),
      ),
    );
  }
}

class _EmployeePerformanceScreen extends StatelessWidget {
  const _EmployeePerformanceScreen({required this.sales});
  final SalesController sales;

  @override
  Widget build(BuildContext context) {
    final Map<String, (int, double)> byEmployee = {};
    for (final s in sales.sales.where((s) => s.status == SaleStatus.completed && s.createdByName.isNotEmpty)) {
      final existing = byEmployee[s.createdByName] ?? (0, 0.0);
      byEmployee[s.createdByName] = (existing.$1 + 1, existing.$2 + s.total);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Employee Performance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: byEmployee.entries.map((e) => ListTile(title: Text(e.key), subtitle: Text('${e.value.$1} sales'), trailing: Text(formatNpr(e.value.$2)))).toList(),
      ),
    );
  }
}

/// Cash, bank and wallet at the end of each day, plus what moved that day.
/// Profit needs costs, which only owners and cash staff see; Reports is
/// theirs alone.
class _DailySummaryScreen extends StatefulWidget {
  const _DailySummaryScreen({required this.daily, required this.onExport, required this.accounts, required this.hasSuppliers});
  final DailySummary Function(DateTime from, DateTime to) daily;
  final Future<void> Function(DateTime from, DateTime to) onExport;
  final List<String> accounts;
  final bool hasSuppliers;
  @override
  State<_DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<_DailySummaryScreen> {
  DateTimeRange? _range;

  Widget _row(String label, String value, {bool bold = false}) => ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(value, style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null),
      );

  bool get _hasWallet => widget.accounts.any((a) => a.split(':').first == Acc.wallet);

  /// Each named bank/wallet on its own line when there is more than one.
  List<Widget> _accountRows(DaySummary d, String family) {
    final ids = widget.accounts.where((a) => a.split(':').first == family).toList();
    return ids.length < 2 ? const [] : [for (final a in ids) _row('   ${accountName(a)}', formatNpr(d.balances[a] ?? 0))];
  }

  @override
  Widget build(BuildContext context) {
    final range = _range;
    final summary = range == null ? null : widget.daily(range.start, range.end);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Summary'),
        actions: [
          IconButton(
            tooltip: 'Export CSV + PDF',
            icon: const Icon(Icons.ios_share),
            onPressed: range == null ? null : () => widget.onExport(range.start, range.end),
          ),
        ],
      ),
      body: Column(
        children: [
          _DateRangeBar(days: 7, maxDays: 366, onChanged: (r) => setState(() => _range = r)),
          if (summary != null)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Card(
                    child: Column(children: [
                      _row('Cash in hand', '${formatNpr(summary.opening.cash)} → ${formatNpr(summary.closing.cash)}', bold: true),
                      _row('Bank', '${formatNpr(summary.opening.bank)} → ${formatNpr(summary.closing.bank)}'),
                      if (_hasWallet) _row('Wallet', '${formatNpr(summary.opening.wallet)} → ${formatNpr(summary.closing.wallet)}'),
                      _row('Sales', formatNpr(summary.total((d) => d.sales)), bold: true),
                      _row('Collections', formatNpr(summary.total((d) => d.collections))),
                      _row('Expenses', formatNpr(summary.total((d) => d.expenses))),
                      if (widget.hasSuppliers) ...[
                        _row('Purchases', formatNpr(summary.total((d) => d.purchases))),
                        _row('Supplier payments', formatNpr(summary.total((d) => d.supplierPayments))),
                      ],
                      _row('Profit', formatNpr(summary.total((d) => d.profit)), bold: true),
                    ]),
                  ),
                  for (final d in summary.days.reversed)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('${formatDate(d.day)} · ${formatBs(d.day)}'),
                      subtitle: Text('Cash ${formatNpr(d.cash)} · Bank ${formatNpr(d.bank)} · Sales ${formatNpr(d.sales)}'),
                      children: [
                        _row('Cash in hand', formatNpr(d.cash), bold: true),
                        _row('Bank', formatNpr(d.bank)),
                        ..._accountRows(d, Acc.bank),
                        if (_hasWallet) ...[_row('Wallet', formatNpr(d.wallet)), ..._accountRows(d, Acc.wallet)],
                        _row('Sales', formatNpr(d.sales), bold: true),
                        _row('   Cash sales', formatNpr(d.cashSales)),
                        _row('   Udharo sales', formatNpr(d.creditSales)),
                        _row('Orders delivered', '${d.ordersDelivered}'),
                        _row('Collections', formatNpr(d.collections)),
                        _row('Expenses', formatNpr(d.expenses)),
                        if (widget.hasSuppliers) ...[
                          _row('Purchases', formatNpr(d.purchases)),
                          _row('Supplier payments', formatNpr(d.supplierPayments)),
                        ],
                        _row('Customers owe', formatNpr(d.receivables)),
                        if (widget.hasSuppliers) _row('Owed to suppliers', formatNpr(d.payables)),
                        _row('Profit', formatNpr(d.profit), bold: true),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
