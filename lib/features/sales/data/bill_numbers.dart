import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/synced_collection.dart';
import 'package:sarathigrocery/features/sales/domain/entities/vat.dart';

/// Hands out tax invoice / credit note numbers: `counters/{series}` =
/// `{next}`. A number is read from the server, then taken in the same
/// online-only batch as the bill; the rules refuse it if another device
/// took that number first (the caller retries with a fresh one).
class BillNumbers {
  BillNumbers(this._get);

  final Future<Json?> Function(String collection, String id) _get;

  final _counters = SyncedCollection<Json>('counters', idOf: (j) => j['id'], toJson: (j) => j, fromJson: (j) => j);

  List<SyncedCollection<Object?>> get collections => [_counters];

  Future<BillNumber> next(String kind, DateTime date) async {
    final s = billSeries(kind, date);
    final seq = ((await _get('counters', s.series))?['next'] as num?)?.toInt() ?? 1;
    return (series: s.series, seq: seq, number: s.format(seq));
  }

  /// Marks [n] used (same batch as the bill it numbers).
  void take(BillNumber n) => _counters.patch(n.series, {'next': n.seq + 1});
}
