import 'package:sarathigrocery/core/utils/formatters.dart';
import 'package:sarathigrocery/features/accounting/domain/books.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/journal_entry.dart';
import 'package:sarathigrocery/features/audit/domain/repositories/audit_repository.dart';
import 'package:sarathigrocery/features/cash/domain/entities/cash_ledger_entry.dart';
import 'package:sarathigrocery/features/cash/domain/repositories/cash_repository.dart';

/// Undoes a cash book entry made by mistake (expense, money move, supplier
/// payment): every line it wrote is written again with a negative amount
/// and its journal entry is posted again negated, both dated today. The
/// original stays, marked reversed. Callers add their own side effects
/// (e.g. a supplier's payable) in the same turn.
class ReverseCashEntry {
  ReverseCashEntry(this._cash, this._books, this._audit);

  final CashRepository _cash;
  final Books _books;
  final AuditRepository _audit;

  /// The journal entry [line] was booked with. Lines from before the link
  /// existed are matched: same account and amount, written within a minute.
  JournalEntry? journalFor(CashLedgerEntry line) {
    if (line.journalId.isNotEmpty) return _books.byId(line.journalId);
    JournalEntry? best;
    for (final e in _books.entries) {
      final gap = e.date.difference(line.date).inMilliseconds.abs();
      if (gap > 60000 || e.id.startsWith('rev-') || ((e.lines[line.account] ?? 0) - line.signedAmount).abs() > 0.005) continue;
      if (best == null || gap < best.date.difference(line.date).inMilliseconds.abs()) best = e;
    }
    return best;
  }

  /// Checks [line] can be reversed by this person; returns its journal entry.
  /// [owner]: owners reverse anything; cash staff only today's entries and
  /// never owners' money.
  JournalEntry check(CashLedgerEntry line, String reason, {required bool owner}) {
    if (line.isReversal) throw AccountingException('This is already a correction.');
    if (_cash.reversalOf(line) != null) throw AccountingException('This entry is already reversed.');
    if (reason.trim().isEmpty) throw AccountingException('Say why it is being reversed.');
    if (!owner && !isToday(line.date)) throw AccountingException('Only the owner can reverse an entry from before today.');
    final journal = journalFor(line);
    if (journal == null) throw AccountingException('This entry can\'t be found in the books. Ask your accountant to post an adjustment.');
    if (!owner && Books.ownerKinds.contains(journal.kind)) throw AccountingException('Only the owner can reverse owners\' money entries.');
    return journal;
  }

  /// Returns the lines that were reversed (both sides of a transfer).
  List<CashLedgerEntry> call(CashLedgerEntry line, String reason, {required String userName, required bool owner}) {
    final journal = check(line, reason, owner: owner);
    reason = reason.trim();
    final group = [
      for (final l in _cash.ledger)
        if (!l.isReversal && (l.id == line.id || (l.date.difference(line.date).inSeconds.abs() <= 60 && journalFor(l)?.id == journal.id))) l,
    ];
    final rev = _books.reverse(journal, reason, by: userName);
    for (final l in group) {
      _cash.addLedgerEntry(
        id: 'rev-${l.id}',
        type: l.type,
        amount: -l.amount,
        note: 'Reversed: ${l.note} – $reason',
        reference: l.reference,
        account: l.account,
        journalId: rev?.id ?? '',
        reverses: l.id,
      );
    }
    _audit.record(userName, 'Entry reversed', 'Money', entityId: line.id, oldValue: '${formatNpr(line.amount)} ${line.note}', newValue: reason);
    return group;
  }
}
