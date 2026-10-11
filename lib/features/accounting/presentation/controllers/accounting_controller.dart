import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/journal_entry.dart';
import 'package:sarathigrocery/features/accounting/domain/statements.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/auth/domain/entities/app_user.dart';
import 'package:sarathigrocery/features/auth/domain/entities/user_role.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/customer_repository.dart';
import 'package:sarathigrocery/features/customers/domain/repositories/payment_repository.dart';
import 'package:sarathigrocery/features/inventory/domain/repositories/product_repository.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale.dart';
import 'package:sarathigrocery/features/sales/domain/entities/sale_status.dart';
import 'package:sarathigrocery/features/sales/domain/repositories/sale_repository.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';
import 'package:sarathigrocery/features/settings/domain/repositories/settings_repository.dart';
import 'package:sarathigrocery/features/suppliers/domain/entities/supplier.dart';
import 'package:sarathigrocery/features/suppliers/domain/repositories/supplier_repository.dart';

/// One "books agree with the records" check: the journal's balance of an
/// account against what the shop's own records (cash book, customers,
/// suppliers, stock) say.
typedef BooksCheck = ({String label, double books, double records});

/// Accounting views (Simple and Accountant) and the owner's bookkeeping
/// actions: opening balances, manual adjustments, year-end close.
class AccountingController extends ChangeNotifier {
  AccountingController(this._books, this._cash, this._customers, this._suppliers, this._products, this._payments, this._sales, this._settings, this._audit);

  final Books _books;
  final CashRepository _cash;
  final CustomerRepository _customers;
  final SupplierRepository _suppliers;
  final ProductRepository _products;
  final PaymentRepository _payments;
  final SaleRepository _sales;
  final SettingsRepository _settings;
  final AuditRepository _audit;

  BusinessSettings get settings => _settings.current;

  List<JournalEntry> get journal => _books.entries;

  Statements get statements => Statements(_books.entries);

  void _done() {
    notifyListeners();
    AppSignal.instance.ping();
  }

  /// Books the cost of sales a delivery device invoiced (it can't see
  /// costs). Run on staff devices.
  void postMissingCosts() => _books.postMissingCosts(_sales.sales);

  /// Every account that has entries, plus the core ones, in chart order.
  List<String> get accounts {
    final ids = {...Acc.core, ..._settings.current.moneyAccounts, for (final e in journal) ...e.lines.keys};
    return ids.toList()..sort((a, b) => accountType(a).index != accountType(b).index ? accountType(a).index.compareTo(accountType(b).index) : a.compareTo(b));
  }

  List<BooksCheck> get checks {
    final b = statements.balances();
    double books(String account) => Statements.natural(account, b[account] ?? 0);
    final money = {Acc.cash, Acc.bank, Acc.wallet, ..._settings.current.moneyAccounts, for (final e in _cash.ledger) e.account};
    return [
      for (final m in money) (label: accountName(m), books: books(m), records: _cash.balanceOf(m)),
      (label: 'Customers owe', books: books(Acc.receivables), records: _customers.totalOutstanding),
      (label: 'Owed to suppliers', books: books(Acc.payables), records: _suppliers.totalPayable),
      (
        label: 'Money with collectors',
        books: books(Acc.collectors),
        records: _payments.payments.where((p) => p.isPendingHandover).fold(0.0, (s, p) => s + p.amount),
      ),
      (label: 'Stock at cost', books: books(Acc.stock), records: _products.products.fold(0.0, (s, p) => s + p.stockQty * p.purchasePrice)),
    ];
  }

  /// Completed sales with a line whose product still has no cost (sold
  /// before its first purchase). Their cost of goods is booked once a
  /// purchase gives the product a cost ([postMissingCosts]).
  List<Sale> get salesWithoutCost => [
        for (final s in _sales.sales)
          if (s.status == SaleStatus.completed && s.items.any((i) => i.lineTotal > 0 && i.cost == 0)) s,
      ];

  /// All checks agree to within a rupee.
  bool get booksBalanced => checks.every((c) => (c.books - c.records).abs() < 1);

  // ---- Opening balances

  /// Opening balances can be entered until the shop's first sale or
  /// purchase (or once entered).
  bool get openingLocked => journal.any((e) => e.id == 'opening' || !e.kind.startsWith('opening'));

  /// Saves owners/shares, named money accounts and expense categories.
  void saveSetup({List<OwnerShare>? owners, List<String>? moneyAccounts, List<String>? expenseCategories, required AppUser by}) {
    if (by.role != UserRole.owner) throw AccountingException('Only the owner changes the accounts setup.');
    if (owners != null) {
      final total = owners.fold(0.0, (s, o) => s + o.percent);
      if (owners.isNotEmpty && (total - 100).abs() > 0.01) throw AccountingException('Shares must add up to 100% (now ${formatQty(total)}%).');
      if (owners.map((o) => o.name).toSet().length != owners.length || owners.any((o) => o.name.trim().isEmpty)) throw AccountingException('Each owner needs a different name.');
    }
    final s = _settings.current;
    if (owners != null) {
      // A partner's capital is booked under their name: they can only leave
      // the list (or be renamed) once it is paid out to zero.
      final b = statements.balances();
      for (final gone in s.owners.where((o) => !owners.any((n) => n.name == o.name))) {
        final left = -((b[Acc.capital(gone.name)] ?? 0) + (b[Acc.drawings(gone.name)] ?? 0));
        if (left.abs() >= 0.01) {
          throw AccountingException('${gone.name} still has ${formatNpr(left)} capital in the business. Pay it out (Drawings) before removing or renaming them.');
        }
      }
      s.owners = owners;
    }
    if (moneyAccounts != null) s.moneyAccounts = moneyAccounts;
    if (expenseCategories != null) s.expenseCategories = expenseCategories;
    _settings.update(s);
    _audit.record(by.name, 'Accounts setup changed', 'Books', newValue: [for (final o in s.owners) '${o.name} ${formatQty(o.percent)}%'].join(', '));
    _done();
  }

  /// [owns]: money accounts and deposits; [owes]: loans by lender. Stock,
  /// customers' old udharo and suppliers come from their own screens.
  void postOpening({
    required Map<String, double> owns,
    required Map<String, double> loans,
    Map<Supplier, double> suppliersOwed = const {},
    required DateTime date,
    required AppUser by,
  }) {
    if (by.role != UserRole.owner) throw AccountingException('Only the owner enters opening balances.');
    if (openingLocked) throw AccountingException('Opening balances are locked: the shop has already started trading. Use an adjustment instead.');
    if (_settings.current.owners.isEmpty) throw AccountingException('First add the owners and their shares (Accounts setup).');
    final owed = suppliersOwed.values.fold(0.0, (s, v) => s + v);
    _books.opening({...owns}..removeWhere((_, v) => v == 0), {
      for (final l in loans.entries)
        if (l.value != 0) Acc.loan(l.key): l.value,
      Acc.payables: owed,
    }, date, by: by.name);
    for (final s in suppliersOwed.entries) {
      if (s.value != 0) _suppliers.applyPayableChange(s.key, s.value);
    }
    for (final m in owns.entries) {
      if (Acc.isMoney(m.key) && m.value > 0) _cash.addLedgerEntry(type: CashEntryType.moneyIn, amount: m.value, note: 'Opening balance', account: m.key, reference: 'opening');
    }
    _audit.record(by.name, 'Opening balances entered', 'Books', newValue: [for (final e in owns.entries) '${accountName(e.key)} ${formatNpr(e.value)}'].join(', '));
    _done();
  }

  // ---- Adjustments and year end

  /// Owner-only manual journal entry (accountant's adjustments).
  void manualEntry(Map<String, double> lines, String reason, DateTime date, {required AppUser by}) {
    if (by.role != UserRole.owner) throw AccountingException('Only the owner posts adjustments.');
    if (reason.trim().isEmpty) throw AccountingException('Give a reason for the adjustment.');
    if (lines.keys.any(Acc.isMoney)) throw AccountingException('Money accounts change only through real payments and transfers.');
    final debits = lines.values.where((v) => v > 0).fold(0.0, (s, v) => s + v);
    final credits = -lines.values.where((v) => v < 0).fold(0.0, (s, v) => s + v);
    if ((debits - credits).abs() > 0.005) throw AccountingException('Debits (${formatNpr(debits)}) and credits (${formatNpr(credits)}) must be equal.');
    if (debits == 0) throw AccountingException('Enter at least one debit and one credit.');
    _books.post('manual', reason.trim(), lines, date: date, by: by.name);
    _audit.record(by.name, 'Adjustment posted', 'Books', newValue: reason.trim());
    _done();
  }

  /// Closes the books through [end]: profit to retained earnings, year locked.
  void closeYear(DateTime end, {required AppUser by}) {
    if (by.role != UserRole.owner) throw AccountingException('Only the owner closes the year.');
    if (end.isAfter(DateTime.now())) throw AccountingException('You can only close a year that has ended.');
    postMissingCosts();
    _books.closeYear(end, by: by.name);
    _settings.update(_settings.current..closedThrough = end);
    _audit.record(by.name, 'Year closed', 'Books', newValue: formatDate(end));
    _done();
  }
}
