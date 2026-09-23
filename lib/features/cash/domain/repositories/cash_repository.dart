import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/entities/expense.dart';
import 'package:sarathigrocery/features/cash/domain/entities/partner_ledger_entry.dart';

abstract class CashRepository {
  List<CashLedgerEntry> get ledger;

  List<Expense> get expenses;

  List<PartnerLedgerEntry> get partnerLedger;

  double get cashInHand;

  double get todayExpenses;

  double get totalExpensesAllTime;

  void addLedgerEntry({required CashEntryType type, required double amount, required String note, String reference = ''});

  void addExpense(String category, double amount, String note, {String createdByName = ''});

  void addPartnerEntry(String partnerName, double amount, String type, String note, {DateTime? date});
}
