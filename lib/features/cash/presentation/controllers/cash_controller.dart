import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/entities/expense.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';
import 'package:sarathigrocery/features/settings/domain/entities/business_settings.dart';

/// The Money screen: the cash book per account, expenses, transfers and
/// owners' money. Every action writes the cash book line(s) and the
/// matching journal entry in one batch.
class CashController extends ChangeNotifier {
  CashController(this._repository, this._books, this._audit, this._settings);

  final CashRepository _repository;
  final Books _books;
  final AuditRepository _audit;
  final BusinessSettings Function() _settings;

  CashRepository get repository => _repository;

  List<CashLedgerEntry> get ledger => _repository.ledger;

  List<Expense> get expenses => _repository.expenses;

  double get cashInHand => _repository.cashInHand;

  double balanceOf(String account) => _repository.balanceOf(account);

  /// Cash, Bank, Wallet, then the shop's named banks/wallets.
  List<String> get moneyAccounts => moneyAccountIds(_settings().moneyAccounts);

  List<String> get expenseCategories => [...kExpenseCategories, ..._settings().expenseCategories];

  List<String> get ownerNames => [for (final o in _settings().owners) o.name];

  double get todayExpenses => _repository.todayExpenses;

  double get totalExpensesAllTime => _repository.totalExpensesAllTime;

  void _done() {
    notifyListeners();
    AppSignal.instance.ping();
  }

  void _check(double amount) {
    if (amount <= 0) throw AccountingException('Enter an amount greater than zero.');
  }

  void addExpense(String category, double amount, String note, {String createdByName = '', String account = Acc.cash}) {
    _check(amount);
    _books.expense(category, amount, account, note, by: createdByName);
    _repository.addExpense(category, amount, note, createdByName: createdByName, account: account);
    _done();
  }

  void _out(String account, double amount, String note, {String reference = ''}) =>
      _repository.addLedgerEntry(type: CashEntryType.moneyOut, amount: amount, note: note, account: account, reference: reference);

  void _in(String account, double amount, String note, {String reference = ''}) =>
      _repository.addLedgerEntry(type: CashEntryType.moneyIn, amount: amount, note: note, account: account, reference: reference);

  /// Money moved between two of the shop's accounts (bank deposit, ATM
  /// withdrawal, wallet top-up).
  void transfer(String from, String to, double amount, String note, {required String userName}) {
    _check(amount);
    if (from == to) throw AccountingException('Pick two different accounts.');
    final text = note.isEmpty ? '${accountName(from)} → ${accountName(to)}' : note;
    _books.transfer(from, to, amount, text, by: userName);
    _out(from, amount, text);
    _in(to, amount, text);
    _audit.record(userName, 'Money transferred', 'Money', newValue: '${formatNpr(amount)} $text');
    _done();
  }

  void capitalIn(String person, double amount, String account, {required String userName}) {
    _check(amount);
    _books.capitalIn(person, amount, account, by: userName);
    _in(account, amount, 'Capital from $person');
    _audit.record(userName, 'Capital put in', 'Money', newValue: '${formatNpr(amount)} by $person');
    _done();
  }

  void drawing(String person, double amount, String account, String note, {required String userName}) {
    _check(amount);
    _books.drawing(person, amount, account, note, by: userName);
    _out(account, amount, 'Taken out by $person${note.isEmpty ? '' : ' – $note'}');
    _audit.record(userName, 'Drawings', 'Money', newValue: '${formatNpr(amount)} by $person');
    _done();
  }

  void drawingReturned(String person, double amount, String account, String note, {required String userName}) {
    _check(amount);
    _books.drawingReturned(person, amount, account, note, by: userName);
    _in(account, amount, 'Drawings returned by $person${note.isEmpty ? '' : ' – $note'}');
    _audit.record(userName, 'Drawings returned', 'Money', newValue: '${formatNpr(amount)} by $person');
    _done();
  }

  void loanReceived(String lender, double amount, String account, {required String userName}) {
    _check(amount);
    _books.loanReceived(lender, amount, account, by: userName);
    _in(account, amount, 'Loan from $lender');
    _audit.record(userName, 'Loan received', 'Money', newValue: '${formatNpr(amount)} from $lender');
    _done();
  }

  void loanRepaid(String lender, double amount, String account, {required String userName}) {
    _check(amount);
    _books.loanRepaid(lender, amount, account, by: userName);
    _out(account, amount, 'Loan repaid to $lender');
    _audit.record(userName, 'Loan repaid', 'Money', newValue: '${formatNpr(amount)} to $lender');
    _done();
  }

  void dividend(double amount, String account, {required String userName}) {
    _check(amount);
    _books.dividend(amount, account, by: userName);
    _out(account, amount, 'Dividend to owners');
    _audit.record(userName, 'Dividend paid', 'Money', newValue: formatNpr(amount));
    _done();
  }

  /// VAT return for [period]: output VAT less input VAT, paid to IRD.
  void vatPaid(double output, double input, String account, String period, {required String userName}) {
    if (output <= 0) throw AccountingException('No VAT collected in $period.');
    _books.vatSettled(output, input, account, period, by: userName);
    final net = output - input;
    if (net > 0) _out(account, net, 'VAT paid to IRD for $period');
    _audit.record(userName, 'VAT paid', 'Money', newValue: '${formatNpr(net > 0 ? net : 0)} for $period');
    _done();
  }

  /// Paid out for something the accountant will classify (equipment,
  /// deposits, fees).
  void otherPayment(double amount, String account, String note, {required String userName}) {
    _check(amount);
    if (note.trim().isEmpty) throw AccountingException('Say what it was for, so your accountant can classify it.');
    _books.toClassify(amount, account, note.trim(), by: userName);
    _out(account, amount, 'To classify: ${note.trim()}');
    _audit.record(userName, 'Other payment', 'Money', newValue: '${formatNpr(amount)} ${note.trim()}');
    _done();
  }
}
