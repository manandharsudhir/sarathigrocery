import 'dart:async';

import 'package:sarathigrocery/core/data/remote_store.dart';
import 'package:sarathigrocery/core/data/write_queue.dart';
import 'package:sarathigrocery/core/services/app_signal.dart';
import 'package:sarathigrocery/core/services/error_reporter.dart';

int toMillis(DateTime date) => date.millisecondsSinceEpoch;

DateTime fromMillis(Object? value) => DateTime.fromMillisecondsSinceEpoch((value as num).toInt());

DateTime? fromMillisOrNull(Object? value) => value == null ? null : fromMillis(value);

double toDouble(Object? value) => (value as num? ?? 0).toDouble();

int toInt(Object? value) => (value as num? ?? 0).toInt();

/// A local, synchronously-readable mirror of one backend collection.
///
/// Repositories keep their existing synchronous API by reading from [items]
/// and writing through a shared [WriteQueue] (fire-and-forget, batched per
/// event-loop turn; the store queues writes offline). Remote changes stream back in and are merged
/// **in place** — entities hold direct references to each other (a `Sale`
/// points at its `Customer` object), so replacing objects would leave those
/// references stale.
///
/// ponytail: mirrors the whole collection in memory — fine for one shop's
/// data; switch hot collections (sales, audit) to paged queries if they grow
/// into the tens of thousands.
class SyncedCollection<T> {
  SyncedCollection(
    this.name, {
    required this.idOf,
    required this.toJson,
    required this.fromJson,
    this.merge,
    this.counters = const {},
  });

  final String name;
  final String Function(T item) idOf;
  final Json Function(T item) toJson;

  /// Returns null when the document references something not loaded (yet).
  final T? Function(Json json) fromJson;

  /// Copies mutable fields from a remote snapshot onto an existing object.
  /// Null for append-only collections (ledger entries, audit log, ...).
  final void Function(T existing, Json json)? merge;

  /// Numeric fields only ever changed via [increment]; excluded from [save]
  /// so a full-object save can't clobber a concurrent increment elsewhere.
  final Set<String> counters;

  final List<T> items = [];
  WriteQueue? _writes;
  StreamSubscription<List<Json>>? _subscription;

  /// Where writes go. Separate from [attach]: a role may write to a
  /// collection it may not read (customers append audit entries).
  void bind(WriteQueue writes) {
    _writes = writes;
    writes.onRollback(_rollback);
  }

  /// Back to the last state the server sent, in place.
  void _rollback() {
    _apply(_lastDocs);
    AppSignal.instance.ping();
  }

  /// Starts mirroring — the whole collection, or only document [id], or only
  /// documents matching [where] (what a restricted role is allowed to see).
  /// Completes once the initial snapshot is applied.
  Future<void> attach({String? id, Map<String, Object?> where = const {}}) {
    detach();
    items.clear();
    AppSignal.instance.addListener(_retryUnresolved);
    final loaded = Completer<void>();
    _subscription = _writes!.store.watch(name, id: id, where: where).listen(
      (docs) {
        _apply(docs);
        if (!loaded.isCompleted) loaded.complete();
        AppSignal.instance.ping();
      },
      onError: (Object error, StackTrace stack) {
        reportError(error, stack, 'watch $name failed');
        if (!loaded.isCompleted) loaded.completeError(error, stack);
      },
    );
    return loaded.future;
  }

  /// One-shot fetch of a single document, bypassing the mirror.
  Future<Json?> fetch(String id) => _writes!.store.get(name, id);

  /// Stops mirroring and forgets the local copy (e.g. on logout, so the
  /// next account on this device never sees the previous one's data).
  void detach() {
    AppSignal.instance.removeListener(_retryUnresolved);
    _subscription?.cancel();
    _subscription = null;
    _lastDocs = const [];
    _hasUnresolved = false;
    items.clear();
  }

  // Collections load in parallel and independently, so a sale can arrive
  // before the product it references. Such docs are skipped, then retried
  // whenever any collection changes (every snapshot pings AppSignal).
  List<Json> _lastDocs = const [];
  bool _hasUnresolved = false;

  void _retryUnresolved() {
    if (_hasUnresolved) _apply(_lastDocs);
  }

  void _apply(List<Json> docs) {
    _lastDocs = docs;
    _hasUnresolved = false;
    final byId = {for (final item in items) idOf(item): item};
    final next = <T>[];
    for (final json in docs) {
      final existing = byId[json['id']];
      if (existing != null) {
        merge?.call(existing, json);
        next.add(existing);
      } else {
        final created = fromJson(json);
        if (created != null) {
          next.add(created);
        } else {
          _hasUnresolved = true;
        }
      }
    }
    // Snapshot order is by id; ids from nextId() are time-ordered, so this
    // keeps "oldest first" just like the old in-memory lists.
    items
      ..clear()
      ..addAll(next);
  }

  T? byId(String? id) {
    for (final item in items) {
      if (idOf(item) == id) return item;
    }
    return null;
  }

  void add(T item) {
    items.add(item);
    _writes?.enqueue(PutOp(name, idOf(item), toJson(item)));
  }

  /// Persists changed non-counter fields of an already-added [item]: only
  /// fields that differ from the server's copy are sent. Besides being
  /// smaller, this matters for access rules that compare changed keys — a
  /// field missing on an older document (e.g. `openingBalance`) is null on
  /// both sides, so re-saving never looks like "adding" it.
  void save(T item) {
    final json = toJson(item)..removeWhere((key, _) => counters.contains(key));
    final server = serverDoc(idOf(item));
    if (server != null) json.removeWhere((key, value) => _jsonEquals(value, server[key]));
    if (json.isEmpty) return;
    _writes?.enqueue(PutOp(name, idOf(item), json));
  }

  /// Merges [data] into document [id] on the server, bypassing the mirror.
  void patch(String id, Json data) => _writes?.enqueue(PutOp(name, id, data));

  /// Nulls a field on the server (data migrations).
  void clearField(T item, String field) => patch(idOf(item), {field: null});

  /// The last version of document [id] the server sent (mirrored collections only).
  Json? serverDoc(String id) {
    for (final doc in _lastDocs) {
      if (doc['id'] == id) return doc;
    }
    return null;
  }

  /// Caller has already applied the deltas locally; this makes them durable.
  void increment(T item, Map<String, num> deltas) => _writes?.enqueue(IncrementOp(name, idOf(item), deltas));

  void remove(T item) {
    items.remove(item);
    _writes?.enqueue(DeleteOp(name, idOf(item)));
  }
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is num && b is num) return a == b; // 3200 == 3200.0
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}
