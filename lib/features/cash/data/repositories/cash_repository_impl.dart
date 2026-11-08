import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/core/utils/id_generator.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_entry_type.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/entities/expense.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';

class CashRepositoryImpl implements CashRepository {
  final _ledger = SyncedCollection<CashLedgerEntry>(
    'cashLedger',
    idOf: (e) => e.id,
    toJson: (e) => {
      'date': toMillis(e.date),
      'type': e.type.name,
      'amount': e.amount,
      'note': e.note,
      'reference': e.reference,
      'account': e.account,
      if (e.journalId.isNotEmpty) 'journalId': e.journalId,
      if (e.reverses != null) 'reverses': e.reverses,
    },
    fromJson: (j) => CashLedgerEntry(
      id: j['id'],
      date: fromMillis(j['date']),
      type: CashEntryType.values.byName(j['type']),
      amount: toDouble(j['amount']),
      note: j['note'] ?? '',
      reference: j['reference'] ?? '',
      account: j['account'] ?? 'cash',
      journalId: j['journalId'] ?? '',
      reverses: j['reverses'],
    ),
  );

  final _expenses = SyncedCollection<Expense>(
    'expenses',
    idOf: (e) => e.id,
    toJson: (e) => {'date': toMillis(e.date), 'category': e.category, 'amount': e.amount, 'note': e.note, 'createdByName': e.createdByName},
    fromJson: (j) => Expense(id: j['id'], date: fromMillis(j['date']), category: j['category'] ?? '', amount: toDouble(j['amount']), note: j['note'] ?? '', createdByName: j['createdByName'] ?? ''),
  );

  List<SyncedCollection<Object?>> get collections => [_ledger, _expenses];

  @override
  List<CashLedgerEntry> get ledger => _ledger.items;

  @override
  List<Expense> get allExpenses => _expenses.items;

  @override
  List<Expense> get expenses => [
        for (final e in allExpenses)
          if (!_isReversed(e)) e,
      ];

  bool _isReversed(Expense e) {
    final line = lineOf(e);
    return line != null && reversalOf(line) != null;
  }

  @override
  CashLedgerEntry? reversalOf(CashLedgerEntry line) => _ledger.byId('rev-${line.id}');

  @override
  CashLedgerEntry? lineOf(Expense expense) {
    // Linked by reference since the reversal feature; older expenses are
    // matched by amount and time (written in the same instant).
    for (final l in ledger) {
      if (l.type == CashEntryType.expense && !l.isReversal && l.reference == expense.id) return l;
    }
    for (final l in ledger) {
      if (l.type == CashEntryType.expense && !l.isReversal && l.reference.isEmpty && l.amount == expense.amount && l.date.difference(expense.date).inSeconds.abs() <= 60) return l;
    }
    return null;
  }

  @override
  double get cashInHand => balanceOf('cash');

  @override
  double balanceOf(String account) => ledger.where((e) => e.account == account).fold(0.0, (sum, e) => sum + e.signedAmount);

  @override
  double get todayExpenses {
    final today = DateTime.now();
    return expenses
        .where((e) => e.date.year == today.year && e.date.month == today.month && e.date.day == today.day)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  @override
  double get totalExpensesAllTime => expenses.fold(0.0, (sum, e) => sum + e.amount);

  @override
  CashLedgerEntry addLedgerEntry(
      {required CashEntryType type, required double amount, required String note, String reference = '', String account = 'cash', String journalId = '', String? reverses, String? id}) {
    final entry = CashLedgerEntry(
        id: id ?? nextId('L'), date: DateTime.now(), type: type, amount: amount, note: note, reference: reference, account: account, journalId: journalId, reverses: reverses);
    _ledger.add(entry);
    return entry;
  }

  @override
  Expense addExpense(String category, double amount, String note, {String createdByName = '', String account = 'cash', String journalId = ''}) {
    final expense = Expense(id: nextId('E'), date: DateTime.now(), category: category, amount: amount, note: note, createdByName: createdByName);
    _expenses.add(expense);
    addLedgerEntry(type: CashEntryType.expense, amount: amount, note: '$category${note.isEmpty ? '' : ' - $note'}', account: account, reference: expense.id, journalId: journalId);
    return expense;
  }
}
