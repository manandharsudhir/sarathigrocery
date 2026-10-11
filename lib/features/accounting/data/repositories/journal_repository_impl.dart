import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/features/accounting/domain/entities/journal_entry.dart';
import 'package:sarathigrocery/features/accounting/domain/repositories/journal_repository.dart';

class JournalRepositoryImpl implements JournalRepository {
  // ponytail: every staff device mirrors the whole journal; page it by
  // fiscal year if a shop's history gets large.
  final _journal = SyncedCollection<JournalEntry>(
    'journal',
    idOf: (e) => e.id,
    toJson: (e) => {
      'date': toMillis(e.date),
      'kind': e.kind,
      'memo': e.memo,
      'reference': e.reference,
      'byName': e.byName,
      'lines': [for (final l in e.lines.entries) {'account': l.key, 'amount': l.value}],
    },
    fromJson: (j) => JournalEntry(
      id: j['id'],
      date: fromMillis(j['date']),
      kind: j['kind'] ?? '',
      memo: j['memo'] ?? '',
      reference: j['reference'] ?? '',
      byName: j['byName'] ?? '',
      lines: {for (final l in (j['lines'] as List? ?? const [])) l['account'] as String: toDouble(l['amount'])},
    ),
  );

  List<SyncedCollection<Object?>> get collections => [_journal];

  @override
  List<JournalEntry> get entries => _journal.items;

  @override
  JournalEntry? byId(String id) => _journal.byId(id);

  @override
  void add(JournalEntry entry) => _journal.add(entry);
}
