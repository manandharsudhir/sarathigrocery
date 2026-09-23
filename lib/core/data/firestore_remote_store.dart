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
  Future<void> commit(List<WriteOp> ops) {
    final batch = _db.batch();
    for (final op in ops) {
      final ref = _db.collection(op.collection).doc(op.id);
      switch (op) {
        case PutOp(:final data):
          batch.set(ref, data, SetOptions(merge: true));
        case IncrementOp(:final deltas):
          batch.set(ref, {for (final e in deltas.entries) e.key: FieldValue.increment(e.value)}, SetOptions(merge: true));
        case DeleteOp():
          batch.delete(ref);
      }
    }
    return batch.commit();
  }
}
