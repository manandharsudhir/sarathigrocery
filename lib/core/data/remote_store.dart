import 'dart:async';

typedef Json = Map<String, dynamic>;

/// One document write. A list of these is committed atomically.
sealed class WriteOp {
  const WriteOp(this.collection, this.id);

  final String collection;
  final String id;
}

/// Upsert: creates the document or merges [data] into it.
class PutOp extends WriteOp {
  const PutOp(super.collection, super.id, this.data);

  final Json data;
}

/// Adds each delta to its numeric field on the server, so concurrent
/// changes from different devices both apply.
class IncrementOp extends WriteOp {
  const IncrementOp(super.collection, super.id, this.deltas);

  final Map<String, num> deltas;
}

class DeleteOp extends WriteOp {
  const DeleteOp(super.collection, super.id);
}

/// Thrown by [RemoteStore.commit] with `requireOnline` when the server
/// can't be reached. Nothing was saved.
class OfflineException implements Exception {
  const OfflineException();

  @override
  String toString() => 'No connection to the server';
}

/// The only seam between the app and whatever backend stores its data.
///
/// Repositories reach it exclusively through [SyncedCollection] using plain
/// JSON maps — no Firebase types leak past it. Moving off Firebase means one
/// new implementation of these three methods (e.g. `GET /:collection` +
/// websocket/polling, `GET /:collection/:id`, `POST /commit`) passed to
/// `AppScope`; nothing above the data layer changes.
abstract class RemoteStore {
  /// Documents in [collection] — only document [id] if given, else those
  /// whose fields equal every entry of [where] — re-emitted on any change.
  /// The first event is the initial load. Must reflect this client's own
  /// writes immediately (Firestore does, via latency compensation).
  Stream<List<Json>> watch(String collection, {String? id, Map<String, Object?> where = const {}});

  /// One-shot read; null if missing. Works before sign-in only where the
  /// backend allows it (e.g. `meta/setup`).
  Future<Json?> get(String collection, String id);

  /// Ids of every document in [collection], straight from the server.
  Future<List<String>> listIds(String collection);

  /// Applies [ops] all-or-nothing. With [requireOnline], the write must reach
  /// the server now or fail — it is never queued for later (used where the
  /// server's answer decides what happens next, e.g. delivery-code checks).
  Future<void> commit(List<WriteOp> ops, {bool requireOnline = false});
}

bool _matches(Json doc, String? id, Map<String, Object?> where) =>
    (id == null || doc['id'] == id) && where.entries.every((e) => doc[e.key] == e.value);

/// In-process [RemoteStore] — used by tests, and runs the app with no
/// backend at all. Enforces no access rules.
class InMemoryRemoteStore implements RemoteStore {
  final Map<String, Map<String, Json>> _data = {};

  /// Test hooks: simulate no connection (online-only commits fail) or a
  /// server rejection (return true to refuse a batch).
  bool online = true;
  bool Function(List<WriteOp> ops)? rejectIf;
  final Map<String, List<void Function()>> _watchers = {};

  List<Json> _snapshot(String collection) => [
        for (final entry in (_data[collection] ?? {}).entries) {...entry.value, 'id': entry.key},
      ];

  @override
  Stream<List<Json>> watch(String collection, {String? id, Map<String, Object?> where = const {}}) {
    late final StreamController<List<Json>> controller;
    void emit() => controller.add([for (final doc in _snapshot(collection)) if (_matches(doc, id, where)) doc]);
    controller = StreamController(
      onListen: emit,
      onCancel: () => _watchers[collection]?.remove(emit),
    );
    (_watchers[collection] ??= []).add(emit);
    return controller.stream;
  }

  @override
  Future<List<String>> listIds(String collection) async => (_data[collection] ?? {}).keys.toList();

  /// Every document, for tests.
  int get documentCount => _data.values.fold(0, (sum, docs) => sum + docs.length);

  @override
  Future<Json?> get(String collection, String id) async {
    final doc = _data[collection]?[id];
    return doc == null ? null : {...doc, 'id': id};
  }

  @override
  Future<void> commit(List<WriteOp> ops, {bool requireOnline = false}) async {
    if (requireOnline && !online) throw const OfflineException();
    if (rejectIf?.call(ops) ?? false) throw StateError('permission-denied');
    for (final op in ops) {
      final docs = _data[op.collection] ??= {};
      switch (op) {
        case PutOp(:final data):
          docs[op.id] = {...?docs[op.id], ...data};
        case IncrementOp(:final deltas):
          final doc = docs[op.id] ??= {};
          deltas.forEach((field, delta) => doc[field] = ((doc[field] as num?) ?? 0) + delta);
        case DeleteOp():
          docs.remove(op.id);
      }
    }
    for (final collection in {for (final op in ops) op.collection}) {
      for (final emit in List.of(_watchers[collection] ?? const <void Function()>[])) {
        emit();
      }
    }
  }
}
