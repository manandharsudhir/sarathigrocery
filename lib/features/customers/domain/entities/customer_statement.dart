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
    required this.returnedBySale,
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

  /// Goods refused at the door, per bill (sale id), as a positive amount.
  final Map<String, double> returnedBySale;

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

  double returnedFor(Sale sale) => returnedBySale[sale.id] ?? 0;

  double dueFor(Sale sale) => sale.status == SaleStatus.completed && !sale.isDoorReturn ? sale.total - returnedFor(sale) - paidFor(sale) : 0;
}

String _paymentTitle(CustomerPayment p, List<Sale> bills) {
  final bill = p.saleId == null ? null : bills.where((s) => s.id == p.saleId).firstOrNull;
  return bill == null ? 'Payment' : 'Payment for bill ${bill.invoiceNumber ?? bill.id}';
}

/// Payments settle the bill or order they were collected against first, then the
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
        ? s.isDoorReturn
            ? '${s.orderId != null ? 'Refused at delivery' : 'Returned'} (bill ${bills.where((b) => b.id == s.returnOf).firstOrNull?.invoiceNumber ?? s.returnOf})${s.invoiceNumber == null ? '' : ' · credit note ${s.invoiceNumber}'}'
            : '${s.orderId != null ? 'Order ${s.orderId} invoice' : 'Credit sale ${s.invoiceNumber ?? s.id}'}'
                '${s.status == SaleStatus.completed ? '' : bills.any((b) => b.corrects == s.id) ? ' (corrected)' : ' (${s.status.name})'}'
                '${s.corrects == null ? '' : ' · corrects ${bills.where((b) => b.id == s.corrects).firstOrNull?.invoiceNumber ?? s.corrects}'}'
        : '${_paymentTitle(p!, bills)} · ${paymentMethodLabel(p.method)}${p.isReversed ? ' (undone)' : ''}';
    lines.add(StatementLine(date: e.date, title: title, change: effect(e), balance: running, sale: s, payment: p));
  }

  // Allocation.
  final due = <String, double>{for (final s in bills) if (s.status == SaleStatus.completed && !s.isDoorReturn) s.id: s.total};
  // Refused goods come off their own bill.
  final returnedBySale = <String, double>{};
  for (final r in bills.where((s) => s.isDoorReturn && s.status == SaleStatus.completed)) {
    returnedBySale[r.returnOf!] = (returnedBySale[r.returnOf!] ?? 0) - r.total;
    if (due.containsKey(r.returnOf)) due[r.returnOf!] = due[r.returnOf!]! + r.total;
  }
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
    // A corrected bill hands its payments on to the bill that replaced it.
    var billId = payment?.saleId;
    for (var hops = 0; billId != null && !due.containsKey(billId) && hops < 20; hops++) {
      billId = bills.where((s) => s.corrects == billId).firstOrNull?.id;
    }
    final linked = payment == null
        ? null
        : bills.where((s) => due.containsKey(s.id) && (s.id == billId || (payment.orderId != null && s.orderId == payment.orderId))).firstOrNull;
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
    returnedBySale: returnedBySale,
    openingPaid: openingPaid,
    allocations: allocations,
  );
}

/// One row of [FullStatement]: a bill (cash or udharo, with the returns
/// folded in) or a payment. [change] moves the balance only for udharo.
class HistoryLine {
  const HistoryLine({required this.date, required this.title, required this.change, required this.balance, this.sale, this.returns = const [], this.payment});

  final DateTime date;
  final String title;
  final double change;
  final double balance;
  final Sale? sale;

  /// Returns against [sale] (negative-quantity sales), shown under it.
  final List<Sale> returns;
  final CustomerPayment? payment;

  double get returnedAmount => returns.fold(0.0, (s, r) => s - r.total);
}

/// Everything this customer bought and paid in [from]..[to]: cash and udharo
/// bills (cancelled/corrected ones hidden), payments (reversed ones marked),
/// balance brought forward and closing.
/// broughtForward + bought − returned − paid == closing.
class FullStatement {
  const FullStatement({required this.broughtForward, required this.lines, required this.bought, required this.returned, required this.paid, required this.closing});

  final double broughtForward;

  /// Oldest first.
  final List<HistoryLine> lines;
  final double bought;
  final double returned;

  /// Payments plus cash bills (net of their returns).
  final double paid;
  final double closing;
}

FullStatement buildFullStatement(Customer customer, CustomerStatement statement, Iterable<Sale> allSales, {DateTime? from, DateTime? to}) {
  final mine = allSales.where((s) => s.customer?.id == customer.id && s.status == SaleStatus.completed).toList();
  final bills = mine.where((s) => !s.isDoorReturn).toList();
  final billIds = {for (final b in bills) b.id};
  final returnsOf = <String, List<Sale>>{};
  final orphanReturns = <Sale>[];
  for (final r in mine.where((s) => s.isDoorReturn)) {
    billIds.contains(r.returnOf) ? (returnsOf[r.returnOf!] ??= []).add(r) : orphanReturns.add(r);
  }

  String billTitle(Sale s) => s.isDoorReturn
      ? 'Returned (bill ${s.returnOf})'
      : s.isCredit
          ? (s.orderId != null ? 'Order ${s.orderId} invoice' : 'Udharo bill ${s.invoiceNumber ?? s.id}')
          : 'Cash bill ${s.invoiceNumber ?? s.id} · paid';

  final events = <HistoryLine>[
    for (final s in [...bills, ...orphanReturns])
      HistoryLine(
        date: s.soldDate,
        title: billTitle(s),
        change: s.isCredit ? s.total + (returnsOf[s.id] ?? []).fold(0.0, (t, r) => t + r.total) : 0,
        balance: 0,
        sale: s,
        returns: returnsOf[s.id] ?? const [],
      ),
    for (final l in statement.lines)
      if (l.payment != null) HistoryLine(date: l.date, title: l.title, change: l.change, balance: 0, payment: l.payment),
  ]..sort((a, b) => a.date.compareTo(b.date));

  var running = statement.opening;
  var broughtForward = running;
  var bought = 0.0, returned = 0.0, paid = 0.0;
  final lines = <HistoryLine>[];
  for (final e in events) {
    running += e.change;
    if (from != null && e.date.isBefore(from)) {
      broughtForward = running;
      continue;
    }
    if (to != null && e.date.isAfter(to)) break;
    final s = e.sale;
    if (s != null) {
      final ret = s.isDoorReturn ? -s.total : e.returnedAmount;
      bought += s.isDoorReturn ? 0 : s.total;
      returned += ret;
      if (!s.isCredit) paid += (s.isDoorReturn ? 0 : s.total) - ret;
    } else if (!e.payment!.isReversed) {
      paid += e.payment!.amount;
    }
    lines.add(HistoryLine(date: e.date, title: e.title, change: e.change, balance: running, sale: s, returns: e.returns, payment: e.payment));
  }
  return FullStatement(
    broughtForward: broughtForward,
    lines: lines,
    bought: bought,
    returned: returned,
    paid: paid,
    closing: lines.isEmpty ? broughtForward : lines.last.balance,
  );
}

/// Udharo still owed right now: old udharo left, then each unpaid or part-paid
/// bill (oldest first) with what's been paid on it.
({double openingDue, List<({Sale sale, double paid, double returned, double due})> bills, double total}) amountDue(CustomerStatement statement) {
  final openingDue = statement.opening - statement.openingPaid;
  final bills = [
    for (final l in statement.lines)
      if (l.sale != null && statement.dueFor(l.sale!) > 0.005)
        (sale: l.sale!, paid: statement.paidFor(l.sale!), returned: statement.returnedFor(l.sale!), due: statement.dueFor(l.sale!)),
  ];
  final opening = openingDue > 0.005 ? openingDue : 0.0;
  return (openingDue: opening, bills: bills, total: bills.fold(opening, (t, b) => t + b.due));
}
