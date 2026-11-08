import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/entities/expense.dart';

abstract class CashRepository {
  List<CashLedgerEntry> get ledger;

  /// Expenses still standing (reversed ones left out).
  List<Expense> get expenses;

  /// Every expense, reversed ones included (for lists that show them).
  List<Expense> get allExpenses;

  /// The reversal of [line], if it has been reversed.
  CashLedgerEntry? reversalOf(CashLedgerEntry line);

  /// The cash book line [expense] was paid with.
  CashLedgerEntry? lineOf(Expense expense);

  double get cashInHand;

  double balanceOf(String account);

  double get todayExpenses;

  double get totalExpensesAllTime;

  CashLedgerEntry addLedgerEntry(
      {required CashEntryType type, required double amount, required String note, String reference = '', String account = 'cash', String journalId = '', String? reverses, String? id});

  Expense addExpense(String category, double amount, String note, {String createdByName = '', String account = 'cash', String journalId = ''});
}
