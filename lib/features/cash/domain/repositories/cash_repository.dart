import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/entities/expense.dart';

abstract class CashRepository {
  List<CashLedgerEntry> get ledger;

  List<Expense> get expenses;

  double get cashInHand;

  double balanceOf(String account);

  double get todayExpenses;

  double get totalExpensesAllTime;

  void addLedgerEntry({required CashEntryType type, required double amount, required String note, String reference = '', String account = 'cash'});

  void addExpense(String category, double amount, String note, {String createdByName = '', String account = 'cash'});
}
