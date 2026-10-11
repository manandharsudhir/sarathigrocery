import 'package:sarathigrocery/features/accounting/domain/entities/journal_entry.dart';

abstract class JournalRepository {
  List<JournalEntry> get entries;

  JournalEntry? byId(String id);

  void add(JournalEntry entry);
}
