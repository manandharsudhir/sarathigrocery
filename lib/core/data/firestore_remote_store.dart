import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:sarathigrocery/core/data/remote_store.dart';

/// Firebase implementation of [RemoteStore]. This file and
/// `FirebaseAuthRepository` are the only places that use Firebase data/auth
/// APIs — delete both (plus `firestore.rules`) when migrating.
class FirestoreRemoteStore implements RemoteStore {
  FirestoreRemoteStore([FirebaseFirestore? firestore]) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static Json _json(DocumentSnapshot<Json> doc) => {...doc.data()!, 'id': doc.id};

  @override
  Stream<List<Json>> watch(String collection, {String? id, Map<String, Object?> where = const {}}) {
    if (id != null) {
      return _db.collection(collection).doc(id).snapshots().map((doc) => [if (doc.exists) _json(doc)]);
    }
    Query<Json> query = _db.collection(collection);
    where.forEach((field, value) => query = query.where(field, isEqualTo: value));
    return query.snapshots().map((snapshot) => [for (final doc in snapshot.docs) _json(doc)]);
  }

  @override
  Future<Json?> get(String collection, String id) async {
    final doc = await _db.collection(collection).doc(id).get();
    return doc.exists ? _json(doc) : null;
  }

  @override
  Future<List<String>> listIds(String collection) async {
    try {
      final snapshot = await _db.collection(collection).get(const GetOptions(source: Source.server));
      return [for (final doc in snapshot.docs) doc.id];
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') throw const OfflineException();
      rethrow;
    }
  }

  /// One Firestore write per document: security rules judge each write on
  /// its own, so "create payment" + "settle it" (or "increment balance" +
  /// "save payment date") in one operation must reach them as a single
  /// write showing the final state.
  @override
  Future<void> commit(List<WriteOp> ops, {bool requireOnline = false}) {
    final docs = <String, ({String collection, String id, Json data, Map<String, num> deltas, Map<String, List<Object?>> unions, bool delete})>{};
    ({String collection, String id, Json data, Map<String, num> deltas, Map<String, List<Object?>> unions, bool delete}) fresh(WriteOp op, {bool delete = false}) =>
        (collection: op.collection, id: op.id, data: <String, dynamic>{}, deltas: <String, num>{}, unions: <String, List<Object?>>{}, delete: delete);
    for (final op in ops) {
      final key = '${op.collection}/${op.id}';
      final cur = docs[key] ?? fresh(op);
      switch (op) {
        case PutOp(:final data):
          cur.data.addAll(data);
          for (final field in data.keys) {
            cur.deltas.remove(field);
            cur.unions.remove(field);
          }
        case IncrementOp(:final deltas):
          deltas.forEach((field, delta) {
            final literal = cur.data[field];
            if (literal is num) {
              cur.data[field] = literal + delta;
            } else {
              cur.deltas[field] = (cur.deltas[field] ?? 0) + delta;
            }
          });
        case ArrayUnionOp(:final values):
          values.forEach((field, add) {
            final literal = cur.data[field];
            if (literal is List) {
              cur.data[field] = [...literal, for (final v in add) if (!literal.contains(v)) v];
            } else {
              cur.unions[field] = [...?cur.unions[field], ...add];
            }
          });
        case DeleteOp():
          docs[key] = fresh(op, delete: true);
          continue;
      }
      docs[key] = cur;
    }

    final writes = [
      for (final d in docs.values)
        (
          ref: _db.collection(d.collection).doc(d.id),
          data: {
            ...d.data,
            for (final e in d.deltas.entries) e.key: FieldValue.increment(e.value),
            for (final e in d.unions.entries) e.key: FieldValue.arrayUnion(e.value),
          },
          delete: d.delete,
        ),
    ];

    if (requireOnline) {
      // Transactions never queue offline: they reach the server now or fail.
      return _db.runTransaction((tx) async {
        for (final w in writes) {
          if (w.delete && w.data.isEmpty) {
            tx.delete(w.ref);
          } else {
            tx.set(w.ref, w.data, SetOptions(merge: !w.delete));
          }
        }
      }, timeout: const Duration(seconds: 20), maxAttempts: 1).catchError((Object e) {
        if (e is TimeoutException || (e is FirebaseException && (e.code == 'unavailable' || e.code == 'deadline-exceeded'))) {
          throw const OfflineException();
        }
        throw e;
      });
    }

    final batch = _db.batch();
    for (final w in writes) {
      if (w.delete && w.data.isEmpty) {
        batch.delete(w.ref);
      } else {
        // After a delete in the same batch, replace instead of merging.
        batch.set(w.ref, w.data, SetOptions(merge: !w.delete));
      }
    }
    return batch.commit();
  }
}
