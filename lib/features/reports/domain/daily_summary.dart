import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/journal_entry.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/entities/expense.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';

/// One calendar day (device clock, midnight to midnight): closing balances
/// and what moved that day.
class DaySummary {
  DaySummary(this.day);

  final DateTime day;

  /// Money account id → balance at the end of the day (from the cash book).
  final Map<String, double> balances = {};
  double sales = 0, cashSales = 0, creditSales = 0;
  double collections = 0, expenses = 0, purchases = 0, supplierPayments = 0;
  int ordersDelivered = 0;

  /// Customers owe / owed to suppliers at the end of the day (journal).
  double receivables = 0, payables = 0;

  /// Income − costs posted that day (journal, closing entries excluded).
  double profit = 0;

  double get cash => balances[Acc.cash] ?? 0;
  double get bank => _family(Acc.bank);
  double get wallet => _family(Acc.wallet);
  double _family(String f) => balances.entries.where((e) => e.key.split(':').first == f).fold(0.0, (s, e) => s + e.value);
}

/// [days] oldest first; [opening] is every money account's balance at the
/// start of the first day.
class DailySummary {
  DailySummary(this.days, this.opening);

  final List<DaySummary> days;
  final DaySummary opening;

  DaySummary get closing => days.last;
  double total(double Function(DaySummary d) f) => days.fold(0.0, (s, d) => s + f(d));
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Daily figures for [from]..[to] (whole days, inclusive). Every day gets a
/// row, quiet ones carrying their balances over. Sales and collections count
/// what still stands (cancelled/returned sales and reversed payments drop out).
DailySummary dailySummary({
  required DateTime from,
  required DateTime to,
  required List<String> accounts,
  required List<CashLedgerEntry> ledger,
  required List<Sale> sales,
  required List<CustomerPayment> payments,
  required List<Expense> expenses,
  required List<Purchase> purchases,
  required List<JournalEntry> journal,
}) {
  final start = _day(from);
  final days = [for (var d = start; !d.isAfter(_day(to)); d = DateTime(d.year, d.month, d.day + 1)) DaySummary(d)];
  final byDay = {for (final d in days) d.day: d};
  final opening = DaySummary(start.subtract(const Duration(days: 1)));
  final balances = {for (final a in accounts) a: 0.0};
  var receivables = 0.0, payables = 0.0;

  // Movements before the range build the opening; inside it, the day's row.
  final moves = <DateTime, List<void Function()>>{};
  void at(DateTime date, void Function() f) => moves.putIfAbsent(_day(date).isBefore(start) ? opening.day : _day(date), () => []).add(f);
  for (final e in ledger) {
    at(e.date, () => balances[e.account] = (balances[e.account] ?? 0) + e.signedAmount);
    if (e.type == CashEntryType.supplierPayment) byDay[_day(e.date)]?.supplierPayments += e.amount;
  }
  for (final e in journal) {
    at(e.date, () {
      receivables += e.lines[Acc.receivables] ?? 0;
      payables -= e.lines[Acc.payables] ?? 0;
    });
    final day = byDay[_day(e.date)];
    if (day == null || e.kind == 'close') continue;
    e.lines.forEach((a, v) {
      final t = accountType(a);
      if (t == AccountType.income || t == AccountType.expense) day.profit -= v;
    });
  }
  for (final s in sales) {
    final day = byDay[_day(s.date)];
    if (day == null || s.status != SaleStatus.completed) continue;
    day.sales += s.total;
    if (s.isCredit) {
      day.creditSales += s.total;
    } else {
      day.cashSales += s.total;
    }
    if (s.orderId != null) day.ordersDelivered++;
  }
  for (final p in payments) {
    if (!p.isReversed) byDay[_day(p.date)]?.collections += p.amount;
  }
  for (final e in expenses) {
    byDay[_day(e.date)]?.expenses += e.amount;
  }
  for (final p in purchases) {
    byDay[_day(p.date)]?.purchases += p.total;
  }

  for (final d in [opening, ...days]) {
    for (final f in moves[d.day] ?? const []) {
      f();
    }
    d.balances.addAll(balances);
    d.receivables = receivables;
    d.payables = payables;
  }
  return DailySummary(days, opening);
}
