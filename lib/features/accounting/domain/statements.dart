import 'package:sarathigrocery/features/accounting/domain/entities/accounts.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/journal_entry.dart';

/// Financial statements computed from the journal.
class Statements {
  Statements(this.entries);

  final List<JournalEntry> entries;

  static bool _inRange(DateTime d, DateTime? from, DateTime? to) => (from == null || !d.isBefore(from)) && (to == null || !d.isAfter(to));

  /// Debit-positive balance of every account over entries dated in
  /// [from]..[to] (inclusive; null = open). [includeClosing]: count the
  /// year-end closing entries (off for profit figures, which they zero).
  Map<String, double> balances({DateTime? from, DateTime? to, bool includeClosing = true}) {
    final totals = <String, double>{};
    for (final e in entries) {
      if (!_inRange(e.date, from, to) || (!includeClosing && e.kind == 'close')) continue;
      e.lines.forEach((account, v) => totals[account] = (totals[account] ?? 0) + v);
    }
    return totals;
  }

  /// Balance shown the "natural" way round: positive for a normal balance
  /// (assets/costs in debit, the rest in credit).
  static double natural(String account, double debitBalance) => accountType(account).debitNormal ? debitBalance : -debitBalance;

  ProfitAndLoss profitAndLoss(DateTime from, DateTime to) {
    final b = balances(from: from, to: to, includeClosing: false);
    final income = {for (final e in b.entries) if (accountType(e.key) == AccountType.income && e.value != 0) e.key: -e.value};
    final costs = {for (final e in b.entries) if (accountType(e.key) == AccountType.expense && e.value != 0) e.key: e.value};
    return ProfitAndLoss(income, costs);
  }

  BalanceSheet balanceSheet(DateTime asOf) {
    final b = balances(to: asOf);
    Map<String, double> of(AccountType t) => {
          for (final e in b.entries)
            if (accountType(e.key) == t && e.value.abs() >= 0.005) e.key: natural(e.key, e.value),
        };
    // Income and costs not yet closed into retained earnings.
    final unclosed = -b.entries.where((e) => accountType(e.key) == AccountType.income || accountType(e.key) == AccountType.expense).fold(0.0, (s, e) => s + e.value);
    return BalanceSheet(of(AccountType.asset), of(AccountType.liability), of(AccountType.equity), unclosed);
  }
}

class ProfitAndLoss {
  ProfitAndLoss(this.income, this.costs);

  final Map<String, double> income;
  final Map<String, double> costs;

  double get totalIncome => income.values.fold(0.0, (s, v) => s + v);
  double get totalCosts => costs.values.fold(0.0, (s, v) => s + v);
  double get profit => totalIncome - totalCosts;
}

class BalanceSheet {
  BalanceSheet(this.assets, this.liabilities, this.equity, this.profitNotClosed);

  final Map<String, double> assets;
  final Map<String, double> liabilities;

  /// Owners' money accounts (drawings/dividends show negative).
  final Map<String, double> equity;
  final double profitNotClosed;

  double get totalAssets => assets.values.fold(0.0, (s, v) => s + v);
  double get totalLiabilities => liabilities.values.fold(0.0, (s, v) => s + v);
  double get totalEquity => equity.values.fold(0.0, (s, v) => s + v) + profitNotClosed;

  /// Assets = liabilities + owners' money (always true when every entry
  /// balanced; shown as the books' self-check).
  bool get balanced => (totalAssets - totalLiabilities - totalEquity).abs() < 1;
}
