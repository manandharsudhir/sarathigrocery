/// One double-entry posting. Each line is an account and a signed amount:
/// positive = debit, negative = credit; the lines always sum to zero.
/// Entries are never edited — a correction is another entry.
class JournalEntry {
  JournalEntry({
    required this.id,
    required this.date,
    required this.kind,
    required this.memo,
    required this.lines,
    this.reference = '',
    this.byName = '',
  });

  final String id;
  final DateTime date;

  /// What produced it (`sale`, `purchase`, `transfer`, `manual`, ...).
  final String kind;
  final String memo;

  /// Account id → signed amount (+ debit, − credit).
  final Map<String, double> lines;

  /// Id of the record behind it (sale, purchase, payment, ...).
  final String reference;
  final String byName;

  double get debits => lines.values.where((v) => v > 0).fold(0.0, (s, v) => s + v);
}
