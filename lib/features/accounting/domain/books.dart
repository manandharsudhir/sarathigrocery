import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/journal_entry.dart';
import 'package:sarathigrocery/features/accounting/domain/repositories/journal_repository.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer.dart';
import 'package:sarathigrocery/features/customers/domain/entities/customer_payment.dart';
import 'package:sarathigrocery/features/inventory/domain/entities/product.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase.dart';
import 'package:sarathigrocery/features/purchasing/domain/entities/purchase_return.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

/// A refused posting (e.g. into a closed year), with a displayable message.
class AccountingException implements Exception {
  AccountingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The bookkeeper: turns every business event into a balanced journal
/// entry, written in the same batch as the event itself. Every mapping from
/// "what happened" to debits and credits lives in this one file, so an
/// accountant can review it in one place.
///
/// Entries for a record use deterministic ids (`sale-<id>`, `cogs-<id>`),
/// so the same event can never be booked twice.
class Books {
  Books(this._journal, this._settings);

  final JournalRepository _journal;
  final BusinessSettings Function() _settings;

  List<JournalEntry> get entries => _journal.entries;

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  /// Posts [lines] (account → amount, + debit / − credit). Zero lines are
  /// dropped; an all-zero entry posts nothing (returns null). Throws
  /// [AccountingException] for a date inside a closed year.
  JournalEntry? post(String kind, String memo, Map<String, double> lines, {String reference = '', String? id, DateTime? date, String by = ''}) {
    final rounded = <String, double>{};
    lines.forEach((account, v) => rounded[account] = _round((rounded[account] ?? 0) + v));
    rounded.removeWhere((_, v) => v == 0);
    if (rounded.isEmpty) return null;
    final diff = _round(rounded.values.fold(0.0, (s, v) => s + v));
    if (diff.abs() > 0.05) throw StateError('Unbalanced $kind entry: $lines');
    if (diff != 0) {
      // Paisa rounding: absorbed by the biggest line.
      final biggest = rounded.keys.reduce((a, b) => rounded[a]!.abs() >= rounded[b]!.abs() ? a : b);
      rounded[biggest] = _round(rounded[biggest]! - diff);
    }
    final when = date ?? DateTime.now();
    final closed = _settings().closedThrough;
    if (closed != null && !when.isAfter(closed)) throw AccountingException('The books are closed up to ${formatDate(closed)}.');
    final entry = JournalEntry(id: id ?? nextId('J'), date: when, kind: kind, memo: memo, lines: rounded, reference: reference, byName: by);
    _journal.add(entry);
    return entry;
  }

  /// [amount] split across the owners' capital by share (credit side).
  Map<String, double> capitalSplit(double amount) {
    final owners = _settings().owners.where((o) => o.percent > 0).toList();
    if (owners.isEmpty) return {Acc.capitalUnassigned: -amount};
    final total = owners.fold(0.0, (s, o) => s + o.percent);
    return {for (final o in owners) Acc.capital(o.name): -amount * o.percent / total};
  }

  // ---- Sales

  void sale(Sale s) {
    post(
      'sale',
      'Sale ${s.invoiceNumber ?? s.id}${s.customer == null ? '' : ' – ${s.customer!.name}'}',
      {s.isCredit && s.customer != null ? Acc.receivables : s.account: s.total, Acc.sales: -s.netSales, Acc.vatPayable: -s.vatAmount},
      reference: s.id,
      id: 'sale-${s.id}',
      date: s.date,
      by: s.createdByName,
    );
    if (s.items.every((i) => i.unitCost != null)) saleCost(s);
  }

  /// Cost of goods sold for [s], once. Lines whose seller couldn't see costs
  /// (delivery staff) use the current cost, which is why a staff device posts
  /// those later ([postMissingCosts]).
  void saleCost(Sale s) {
    if (_journal.byId('cogs-${s.id}') != null) return;
    final cost = s.items.fold(0.0, (sum, i) => sum + i.cost);
    post('cogs', 'Cost of sale ${s.invoiceNumber ?? s.id}', {Acc.cogs: cost, Acc.stock: -cost}, reference: s.id, id: 'cogs-${s.id}', date: s.date);
  }

  /// Run on devices that can see costs: books the cost of sales that a
  /// delivery device invoiced.
  void postMissingCosts(Iterable<Sale> sales) {
    for (final s in sales) {
      if (_journal.byId('sale-${s.id}') != null && _journal.byId('cogs-${s.id}') == null) saleCost(s);
    }
  }

  /// Cancellation or return: the sale and its cost, reversed.
  void saleReversed(Sale s, String why, {String by = ''}) {
    final original = _journal.byId('sale-${s.id}');
    if (original != null) {
      post('saleReversed', '$why: sale ${s.invoiceNumber ?? s.id}', {for (final l in original.lines.entries) l.key: -l.value}, reference: s.id, id: 'sale-rev-${s.id}', by: by);
    }
    saleCost(s);
    final cost = _journal.byId('cogs-${s.id}');
    if (cost != null) {
      post('cogsReversed', 'Stock back from sale ${s.invoiceNumber ?? s.id}', {for (final l in cost.lines.entries) l.key: -l.value}, reference: s.id, id: 'cogs-rev-${s.id}');
    }
  }

  // ---- Purchases and stock

  void purchase(Purchase p, {String by = ''}) {
    post(
      'purchase',
      'Purchase ${p.supplierBillNo.isEmpty ? p.id : 'bill ${p.supplierBillNo}'} – ${p.supplier.name}',
      {Acc.stock: p.goodsTotal, Acc.vatInput: p.vatAmount, p.account: -p.paidAmount, Acc.payables: -p.remainingAmount},
      reference: p.id,
      id: 'purchase-${p.id}',
      date: p.date,
      by: by,
    );
  }

  void purchaseReturn(PurchaseReturn r, {String by = ''}) {
    post('purchaseReturn', 'Returned ${r.product.name} to ${r.supplier.name}', {Acc.payables: r.total, Acc.stock: -r.total}, reference: r.id, id: 'preturn-${r.id}', by: by);
  }

  void supplierPaid(String supplierId, String supplierName, double amount, String account, {String by = ''}) {
    post('supplierPayment', 'Paid \$supplierName', {Acc.payables: amount, account: -amount}, reference: supplierId, by: by);
  }

  /// Stock that left (−) or came back (+) without a sale: damaged,
  /// expired, returned. Valued at average cost.
  void stockAdjusted(Product p, double baseQtyDelta, String why, {String by = ''}) {
    final value = baseQtyDelta * p.purchasePrice;
    post('stockAdjustment', '$why: ${p.name}', {Acc.stock: value, Acc.stockLoss: -value}, reference: p.id, by: by);
  }

  /// A manual cost correction re-values the stock on hand.
  void stockRevalued(Product p, double oldCost, double newCost, {String by = ''}) {
    final value = p.stockQty * (newCost - oldCost);
    post('stockRevalued', 'Cost of ${p.name} changed ${formatNpr(oldCost)} → ${formatNpr(newCost)}', {Acc.stock: value, Acc.stockLoss: -value}, reference: p.id, by: by);
  }

  /// Goods already owned when added to the app: part of opening capital.
  void openingStock(Product p, {String by = ''}) {
    final value = p.stockQty * p.purchasePrice;
    post('openingStock', 'Opening stock: ${p.name}', {Acc.stock: value, ...capitalSplit(value)}, reference: p.id, id: 'open-stock-${p.id}', by: by);
  }

  /// A customer's udharo from before the app: part of opening capital.
  void customerOpening(Customer c, {String by = ''}) {
    final owed = c.openingBalance ?? 0;
    post('openingUdharo', 'Opening udharo: ${c.name}', {Acc.receivables: owed, ...capitalSplit(owed)}, reference: c.id, id: 'open-cust-${c.id}', by: by);
  }

  // ---- Customer payments

  /// The customer paid: they owe less, and the money is with the collector
  /// until it is counted into an account.
  void paymentRecorded(CustomerPayment p) {
    post('payment', 'Payment from ${p.customer.name}', {Acc.collectors: p.amount, Acc.receivables: -p.amount},
        reference: p.id, id: 'pay-${p.id}', date: p.date, by: p.collectedByName);
  }

  void paymentSettled(CustomerPayment p, String account) {
    final counted = p.settledAmount ?? 0;
    post('settlement', 'Counted in: payment from ${p.customer.name} via ${p.collectedByName}',
        {account: counted, Acc.cashShortage: p.amount - counted, Acc.collectors: -p.amount},
        reference: p.id, id: 'settle-${p.id}', by: p.settledByName);
  }

  void paymentReversed(CustomerPayment p, String account) {
    final counted = p.settledAmount ?? 0;
    post(
      'paymentReversed',
      'Undo of payment from ${p.customer.name}',
      p.isSettled
          ? {Acc.receivables: p.amount, account: -counted, Acc.cashShortage: -(p.amount - counted)}
          : {Acc.receivables: p.amount, Acc.collectors: -p.amount},
      reference: p.id,
      id: 'pay-rev-${p.id}',
      by: p.reversedByName,
    );
  }

  // ---- Money

  void expense(String category, double amount, String account, String note, {String by = ''}) {
    post('expense', '$category${note.isEmpty ? '' : ' – $note'}', {Acc.expense(category): amount, account: -amount}, by: by);
  }

  /// Paid out, for the accountant to classify later (equipment, deposits, ...).
  void toClassify(double amount, String account, String note, {String by = ''}) {
    post('toClassify', note, {Acc.toClassify: amount, account: -amount}, by: by);
  }

  void transfer(String from, String to, double amount, String note, {String by = ''}) {
    post('transfer', note.isEmpty ? '${accountName(from)} → ${accountName(to)}' : note, {to: amount, from: -amount}, by: by);
  }

  void capitalIn(String person, double amount, String account, {String by = ''}) =>
      post('capital', 'Capital put in by $person', {account: amount, Acc.capital(person): -amount}, by: by);

  void drawing(String person, double amount, String account, String note, {String by = ''}) =>
      post('drawing', 'Taken out by $person${note.isEmpty ? '' : ' – $note'}', {Acc.drawings(person): amount, account: -amount}, by: by);

  void loanReceived(String lender, double amount, String account, {String by = ''}) =>
      post('loan', 'Loan from $lender', {account: amount, Acc.loan(lender): -amount}, by: by);

  void loanRepaid(String lender, double amount, String account, {String by = ''}) =>
      post('loanRepaid', 'Repaid to $lender', {Acc.loan(lender): amount, account: -amount}, by: by);

  /// A dividend paid out of retained earnings, shared by ownership.
  void dividend(double amount, String account, {String by = ''}) {
    final owners = _settings().owners;
    final split = owners.isEmpty ? '' : ' (${[for (final o in owners) '${o.name} ${formatNpr(amount * o.percent / 100)}'].join(', ')})';
    post('dividend', 'Dividend$split', {Acc.dividends: amount, account: -amount}, by: by);
  }

  /// VAT return for a period: VAT collected ([output]) set against VAT paid
  /// on purchases ([input]); the difference is paid to IRD from [account].
  /// If input exceeds output, only output is offset; the rest carries on.
  void vatSettled(double output, double input, String account, String period, {String by = ''}) {
    final offset = input < output ? input : output;
    post('vatPayment', 'VAT for $period', {Acc.vatPayable: output, Acc.vatInput: -offset, account: -(output - offset)}, by: by);
  }

  /// Opening balances: what the business owns and owes on [date]; the
  /// difference is the owners' opening capital.
  void opening(Map<String, double> owns, Map<String, double> owes, DateTime date, {String by = ''}) {
    final net = owns.values.fold(0.0, (s, v) => s + v) - owes.values.fold(0.0, (s, v) => s + v);
    post('opening', 'Opening balances', {
      ...owns,
      for (final o in owes.entries) o.key: -o.value,
      ...capitalSplit(net),
    }, id: 'opening', date: date, by: by);
  }

  /// Year-end close through [end]: income and costs move to retained
  /// earnings, as do dividends; then the year is locked (caller saves
  /// [BusinessSettings.closedThrough]).
  JournalEntry? closeYear(DateTime end, {String by = ''}) {
    final from = _settings().closedThrough;
    final totals = <String, double>{};
    for (final e in entries) {
      if (e.date.isAfter(end) || (from != null && !e.date.isAfter(from))) continue;
      for (final l in e.lines.entries) {
        final type = accountType(l.key);
        if (type == AccountType.income || type == AccountType.expense || l.key == Acc.dividends) totals[l.key] = (totals[l.key] ?? 0) + l.value;
      }
    }
    final net = totals.values.fold(0.0, (s, v) => s + v);
    return post('close', 'Year closed ${formatDate(end)}', {for (final t in totals.entries) t.key: -t.value, Acc.retained: net}, date: end, by: by);
  }
}
