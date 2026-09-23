// Replays the writes the real app made (fixtures/app_writes.json, produced
// by `fvm flutter test test/rules_fixture_test.dart`) against the rules, in
// order, as the account that made each one. Every commit must be allowed.
import { after, before, test } from 'node:test';
import { readFileSync, existsSync } from 'node:fs';
import { assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, increment, writeBatch } from 'firebase/firestore';

const fixture = new URL('./fixtures/app_writes.json', import.meta.url);
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sarathi-replay',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env?.cleanup());

// Same per-document coalescing as FirestoreRemoteStore.commit.
function coalesce(ops) {
  const docs = new Map();
  for (const op of ops) {
    const key = `${op.collection}/${op.id}`;
    if (op.kind === 'delete') {
      docs.set(key, { op, data: {}, deltas: {}, del: true });
      continue;
    }
    const cur = docs.get(key) ?? { op, data: {}, deltas: {}, del: false };
    if (op.kind === 'put') {
      Object.assign(cur.data, op.data);
      for (const f of Object.keys(op.data)) delete cur.deltas[f];
    } else {
      for (const [f, delta] of Object.entries(op.deltas)) {
        if (typeof cur.data[f] === 'number') cur.data[f] += delta;
        else cur.deltas[f] = (cur.deltas[f] ?? 0) + delta;
      }
    }
    docs.set(key, cur);
  }
  return [...docs.values()];
}

test('every write the app makes is allowed by the rules', { skip: !existsSync(fixture) && 'run the Dart fixture test first' }, async () => {
  const commits = JSON.parse(readFileSync(fixture, 'utf8'));
  await env.clearFirestore();
  for (const [i, commit] of commits.entries()) {
    const db = env.authenticatedContext(commit.actor).firestore();
    const batch = writeBatch(db);
    for (const w of coalesce(commit.ops)) {
      const ref = doc(db, w.op.collection, w.op.id);
      const data = { ...w.data };
      for (const [f, delta] of Object.entries(w.deltas)) data[f] = increment(delta);
      if (w.del && Object.keys(data).length === 0) batch.delete(ref);
      else batch.set(ref, data, { merge: !w.del });
    }
    const what = [...new Set(commit.ops.map((o) => o.collection))].join(', ');
    try {
      await assertSucceeds(batch.commit());
    } catch (e) {
      throw new Error(`commit #${i} by ${commit.actor} (${what}) was refused:\n${e.message}`);
    }
  }
});
