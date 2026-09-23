import 'package:flutter/foundation.dart';

import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/entities/expense.dart';
import 'package:sarathigrocery/features/cash/domain/entities/partner_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';

class CashController extends ChangeNotifier {
  CashController(this._repository);

  final CashRepository _repository;

  CashRepository get repository => _repository;

  List<CashLedgerEntry> get ledger => _repository.ledger;

  List<Expense> get expenses => _repository.expenses;

  List<PartnerLedgerEntry> get partnerLedger => _repository.partnerLedger;

  double get cashInHand => _repository.cashInHand;

  double get todayExpenses => _repository.todayExpenses;

  double get totalExpensesAllTime => _repository.totalExpensesAllTime;

  void addExpense(String category, double amount, String note, {String createdByName = ''}) {
    _repository.addExpense(category, amount, note, createdByName: createdByName);
    notifyListeners();
    AppSignal.instance.ping();
  }

  void addBankDeposit(double amount, String note) {
    _repository.addLedgerEntry(type: CashEntryType.deposit, amount: amount, note: note.isEmpty ? 'Bank deposit' : note);
    notifyListeners();
    AppSignal.instance.ping();
  }

  void addPartnerEntry(String partnerName, double amount, String type, String note) {
    _repository.addPartnerEntry(partnerName, amount, type, note);
    notifyListeners();
    AppSignal.instance.ping();
  }
}
