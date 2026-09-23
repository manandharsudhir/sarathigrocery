import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';

class StatementLine {
  const StatementLine({required this.date, required this.title, required this.change, required this.balance, this.sale, this.payment});

  final DateTime date;
  final String title;

  /// Effect on what the customer owes (+ bill, − payment, 0 if voided).
  final double change;

  /// Running balance after this line.
  final double balance;
  final Sale? sale;
  final CustomerPayment? payment;
}

/// A customer's account, rebuilt purely from bills (credit sales / order
/// invoices) and payments — the same view for the owner and the customer.
class CustomerStatement {
  CustomerStatement._({
    required this.opening,
    required this.lines,
    required this.actualBalance,
    required this.verifiable,
    required this.paidBySale,
    required this.openingPaid,
    required this.allocations,
  });

  final double opening;

  /// Oldest first.
  final List<StatementLine> lines;
  final double actualBalance;

  /// False for customers created before opening balances were recorded —
  /// their opening is inferred, so the balance can't be cross-checked.
  final bool verifiable;

  /// How much of each bill (by sale id) has been paid off.
  final Map<String, double> paidBySale;

  /// How much of the opening balance has been paid off.
  final double openingPaid;

  /// Per payment id: what it paid off, in order (sale id, or 'opening', or
  /// 'advance' for anything beyond what was owed).
  final Map<String, List<({String target, double amount})>> allocations;

  double get expectedBalance => lines.isEmpty ? opening : lines.last.balance;

  /// Stored balance = opening + bills − payments. If not, something changed
  /// the balance outside the recorded flows — the owner must look.
  bool get balanced => !verifiable || (expectedBalance - actualBalance).abs() < 0.01;

  double get unexplainedDifference => actualBalance - expectedBalance;

  double paidFor(Sale sale) => paidBySale[sale.id] ?? 0;

  double dueFor(Sale sale) => sale.status == SaleStatus.completed ? sale.total - paidFor(sale) : 0;
}

/// Payments settle the order they were collected against first, then the
/// oldest outstanding bills (opening balance counts as the oldest).
CustomerStatement buildStatement(Customer customer, Iterable<Sale> allSales, Iterable<CustomerPayment> allPayments) {
  final bills = allSales.where((s) => s.isCredit && s.customer?.id == customer.id).toList()..sort((a, b) => a.date.compareTo(b.date));
  final payments = allPayments.where((p) => p.customer.id == customer.id).toList()..sort((a, b) => a.date.compareTo(b.date));

  final events = <({DateTime date, Sale? sale, CustomerPayment? payment})>[
    for (final s in bills) (date: s.date, sale: s, payment: null),
    for (final p in payments) (date: p.date, sale: null, payment: p),
  ]..sort((a, b) => a.date.compareTo(b.date));

  double effect(({DateTime date, Sale? sale, CustomerPayment? payment}) e) {
    if (e.sale != null) return e.sale!.status == SaleStatus.completed ? e.sale!.total : 0;
    return e.payment!.isReversed ? 0 : -e.payment!.amount;
  }

  final totalEffect = events.fold(0.0, (sum, e) => sum + effect(e));
  final verifiable = customer.openingBalance != null;
  final opening = customer.openingBalance ?? customer.outstandingBalance - totalEffect;

  var running = opening;
  final lines = <StatementLine>[];
  for (final e in events) {
    running += effect(e);
    final s = e.sale;
    final p = e.payment;
    final title = s != null
        ? '${s.orderId != null ? 'Order ${s.orderId} invoice' : 'Credit sale ${s.id}'}${s.status == SaleStatus.completed ? '' : ' (${s.status.name})'}'
        : 'Payment · ${paymentMethodLabel(p!.method)}${p.isReversed ? ' (reversed)' : ''}';
    lines.add(StatementLine(date: e.date, title: title, change: effect(e), balance: running, sale: s, payment: p));
  }

  // Allocation.
  final due = <String, double>{for (final s in bills) if (s.status == SaleStatus.completed) s.id: s.total};
  var openingDue = opening > 0 ? opening : 0.0;
  final paidBySale = <String, double>{};
  var openingPaid = 0.0;
  final allocations = <String, List<({String target, double amount})>>{};

  void apply(String paymentId, double amount) {
    final out = allocations[paymentId] = [];
    var left = amount;
    void pay(String target, double available) {
      final take = available < left ? available : left;
      if (take <= 0) return;
      left -= take;
      out.add((target: target, amount: take));
      if (target == 'opening') {
        openingDue -= take;
        openingPaid += take;
      } else {
        due[target] = due[target]! - take;
        paidBySale[target] = (paidBySale[target] ?? 0) + take;
      }
    }

    final payment = payments.where((p) => p.id == paymentId).firstOrNull;
    final linked = payment?.orderId == null ? null : bills.where((s) => s.orderId == payment!.orderId && due.containsKey(s.id)).firstOrNull;
    if (linked != null) pay(linked.id, due[linked.id]!);
    pay('opening', openingDue);
    for (final s in bills) {
      if (due.containsKey(s.id)) pay(s.id, due[s.id]!);
    }
    if (left > 0.001) out.add((target: 'advance', amount: left));
  }

  // A negative opening is prepaid credit: spend it before any payment.
  if (opening < 0) apply('opening-credit', -opening);
  for (final p in payments.where((p) => !p.isReversed)) {
    apply(p.id, p.amount);
  }

  return CustomerStatement._(
    opening: opening,
    lines: lines,
    actualBalance: customer.outstandingBalance,
    verifiable: verifiable,
    paidBySale: paidBySale,
    openingPaid: openingPaid,
    allocations: allocations,
  );
}
