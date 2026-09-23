import 'dart:async';

import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/services/error_reporter.dart';

/// Collects every write made during one synchronous turn of the event loop
/// and commits them as a single atomic batch.
///
/// Use cases are synchronous, so one call — e.g. `RecordSale` touching
/// stock, customer balance, cash ledger, audit and notifications — lands
/// on the backend all-or-nothing, without the domain layer knowing
/// batches exist. If the backend rejects the batch, none of it applies and
/// the next snapshots roll the local mirror back.
class WriteQueue {
  WriteQueue(this.store);

  final RemoteStore store;

  // Firestore's per-batch limit. Larger bursts (bulk imports) are split
  // and lose cross-chunk atomicity, which no normal operation comes near.
  static const _maxBatch = 500;

  List<WriteOp> _pending = [];
  Future<void>? _scheduled;

  void enqueue(WriteOp op) {
    _pending.add(op);
    // ignore(): failures are already reported in _commit; only flush()
    // callers should see them, not the zone's uncaught-error handler.
    _scheduled ??= Future.microtask(_commit)..ignore();
  }

  /// Commits anything queued now and completes when the backend accepts it.
  /// Only needed where the next step depends on the server already having
  /// the data (first-run setup); ordinary writes are fire-and-forget.
  Future<void> flush() => _scheduled ?? Future.value();

  Future<void> _commit() async {
    final ops = _pending;
    _pending = [];
    _scheduled = null;
    for (var i = 0; i < ops.length; i += _maxBatch) {
      final chunk = ops.sublist(i, i + _maxBatch > ops.length ? ops.length : i + _maxBatch);
      try {
        await store.commit(chunk);
      } catch (e, stack) {
        reportError(e, stack, 'commit of ${chunk.length} writes to ${{for (final op in chunk) op.collection}.join(', ')} failed');
        rethrow;
      }
    }
  }
}
