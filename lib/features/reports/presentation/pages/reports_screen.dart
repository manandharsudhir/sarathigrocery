import 'package:flutter/material.dart';

import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/cash/presentation/controllers/cash_controller.dart';
import 'package:sarathigrocery/features/customers/presentation/controllers/customers_controller.dart';
import 'package:sarathigrocery/features/inventory/presentation/controllers/inventory_controller.dart';
import 'package:sarathigrocery/features/purchasing/presentation/controllers/purchasing_controller.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/presentation/controllers/sales_controller.dart';
import 'package:sarathigrocery/features/suppliers/presentation/controllers/suppliers_controller.dart';

double _profitLoss(SalesController sales, CashController cash) => sales.totalRevenue - sales.totalCostOfGoods - cash.totalExpensesAllTime;

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    super.key,
    required this.sales,
    required this.purchasing,
    required this.cash,
    required this.inventory,
    required this.customers,
    required this.suppliers,
  });

  final SalesController sales;
  final PurchasingController purchasing;
  final CashController cash;
  final InventoryController inventory;
  final CustomersController customers;
  final SuppliersController suppliers;

  @override
  Widget build(BuildContext context) {
    final reports = <(String, IconData, WidgetBuilder)>[
      ('Sales Report', Icons.point_of_sale, (_) => _SalesReportScreen(sales: sales)),
      ('Sales by Product', Icons.inventory_2_outlined, (_) => _SalesByProductScreen(sales: sales)),
      ('Sales by Customer', Icons.people_outline, (_) => _SalesByCustomerScreen(sales: sales)),
      ('Purchase Report', Icons.local_shipping_outlined, (_) => _PurchaseReportScreen(purchasing: purchasing)),
      ('Expense Report', Icons.receipt_long_outlined, (_) => _ExpenseReportScreen(cash: cash)),
      ('Profit & Loss', Icons.trending_up, (_) => _ProfitLossScreen(sales: sales, cash: cash)),
      ('Inventory Report', Icons.warehouse_outlined, (_) => _InventoryReportScreen(inventory: inventory)),
      ('Stock Movement', Icons.swap_vert, (_) => _StockMovementScreen(inventory: inventory, purchasing: purchasing, sales: sales)),
      ('Customer Outstanding', Icons.call_received, (_) => _CustomerOutstandingScreen(customers: customers)),
      ('Supplier Outstanding', Icons.call_made, (_) => _SupplierOutstandingScreen(suppliers: suppliers)),
      ('Payment Report', Icons.payments_outlined, (_) => _PaymentReportScreen(cash: cash)),
      ('Best-Selling Products', Icons.star_outline, (_) => _BestSellingScreen(sales: sales)),
      ('Employee Performance', Icons.badge_outlined, (_) => _EmployeePerformanceScreen(sales: sales)),
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

/// Simple start/end date range row. Defaults to the last 30 days.
class _DateRangeBar extends StatefulWidget {
  const _DateRangeBar({required this.onChanged});

  final ValueChanged<DateTimeRange> onChanged;

  @override
  State<_DateRangeBar> createState() => _DateRangeBarState();
}

class _DateRangeBarState extends State<_DateRangeBar> {
  late DateTimeRange _range = DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChanged(_range));
  }

  Future<void> _pick() async {
    final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _range);
    if (picked != null) {
      setState(() => _range = picked);
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

class _SalesByProductScreen extends StatelessWidget {
  const _SalesByProductScreen({required this.sales});
  final SalesController sales;

  @override
  Widget build(BuildContext context) {
    final Map<String, (int, double)> byProduct = {};
    for (final s in sales.sales.where((s) => s.status == SaleStatus.completed)) {
      for (final item in s.items) {
        final existing = byProduct[item.product.name] ?? (0, 0.0);
        byProduct[item.product.name] = (existing.$1 + item.qty, existing.$2 + item.lineTotal);
      }
    }
    final rows = byProduct.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    return Scaffold(
      appBar: AppBar(title: const Text('Sales by Product')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: rows.map((e) => ListTile(title: Text(e.key), subtitle: Text('${e.value.$1} units sold'), trailing: Text(formatNpr(e.value.$2)))).toList(),
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

class _ProfitLossScreen extends StatelessWidget {
  const _ProfitLossScreen({required this.sales, required this.cash});
  final SalesController sales;
  final CashController cash;

  @override
  Widget build(BuildContext context) {
    final profitLoss = _profitLoss(sales, cash);
    return Scaffold(
      appBar: AppBar(title: const Text('Profit & Loss')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(title: const Text('Total Revenue'), trailing: Text(formatNpr(sales.totalRevenue))),
          ListTile(title: const Text('Cost of Goods Sold'), trailing: Text('- ${formatNpr(sales.totalCostOfGoods)}')),
          ListTile(title: const Text('Expenses'), trailing: Text('- ${formatNpr(cash.totalExpensesAllTime)}')),
          const Divider(),
          ListTile(
            title: const Text('Net Profit / Loss', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: Text(
              formatNpr(profitLoss),
              style: TextStyle(fontWeight: FontWeight.bold, color: profitLoss >= 0 ? Colors.green : Colors.red),
            ),
          ),
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
              subtitle: Text('${p.category} · reorder at ${p.reorderLevel}'),
              trailing: Text(
                '${p.stockQty} in stock',
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
      ...inventory.adjustments.map((a) => MapEntry(a.date, '${a.type.name} · ${a.product.name} · -${a.qty}')),
      ...purchasing.purchases.expand((p) => p.items.map((i) => MapEntry(p.date, 'Purchase · ${i.product.name} · +${i.qty}'))),
      ...sales.sales.where((s) => s.status == SaleStatus.completed).expand((s) => s.items.map((i) => MapEntry(s.date, 'Sale · ${i.product.name} · -${i.qty}'))),
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
              children: entries.map((e) => ListTile(dense: true, title: Text(e.note), subtitle: Text('${e.account.name} · ${e.type.name} · ${formatDate(e.date)}'), trailing: Text('${e.isOutflow ? '-' : '+'}${formatNpr(e.amount)}'))).toList(),
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
    final Map<String, int> qtyByProduct = {};
    for (final s in sales.sales.where((s) => s.status == SaleStatus.completed)) {
      for (final item in s.items) {
        qtyByProduct[item.product.name] = (qtyByProduct[item.product.name] ?? 0) + item.qty;
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
          title: Text(rows[index].key),
          trailing: Text('${rows[index].value} units'),
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
