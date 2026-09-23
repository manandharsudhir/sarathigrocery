// Security-rules tests for ../firestore.rules, run against the emulator.
// From the project root:
//   (cd firestore_tests && npm install)
//   firebase emulators:exec --only firestore --project demo-sarathi "cd firestore_tests && npm test"
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, increment, query, setDoc, updateDoc, where, writeBatch } from 'firebase/firestore';

let env;

const OWNER = 'owner-uid';
const EMPLOYEE = 'employee-uid';
const ACCOUNTANT = 'accountant-uid';
const CUSTOMER = 'customer-uid';
const RESTRICTED = 'restricted-uid';
const INACTIVE = 'inactive-uid';
const DELIVERY = 'delivery-uid';

const user = (role, extra = {}) => ({ name: role, phone: `98${role.length}`, role, active: true, linkedCustomerId: null, customPermissions: null, ...extra });

const payment = (extra = {}) => ({
  customerId: 'C1', amount: 7000, method: 'cash', reference: '', orderId: null, collectedById: EMPLOYEE, collectedByName: 'x',
  deliveryCode: null, customerConfirmedAt: null, disputedAt: null, disputeNote: '', settledAt: null, settledAmount: null,
  settledById: null, settledByName: '', reversedAt: null, reversedByName: '', reversalReason: '', ...extra,
});

const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sarathi',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

/** A business that's already set up, seeded with rules disabled. */
async function seedBusiness() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, 'meta/setup'), { ownerId: OWNER });
    await setDoc(doc(d, `users/${OWNER}`), user('owner'));
    await setDoc(doc(d, `users/${EMPLOYEE}`), user('employee'));
    await setDoc(doc(d, `users/${ACCOUNTANT}`), user('accountant'));
    await setDoc(doc(d, `users/${CUSTOMER}`), user('customer', { linkedCustomerId: 'C1' }));
    await setDoc(doc(d, `users/${RESTRICTED}`), user('employee', { customPermissions: ['viewSales'] }));
    await setDoc(doc(d, `users/${INACTIVE}`), user('employee', { active: false }));
    await setDoc(doc(d, `users/${DELIVERY}`), user('delivery'));
    await setDoc(doc(d, 'orders/O3'), { customerId: 'C1', status: 'outForDelivery', assignedToId: DELIVERY, assignedToName: 'delivery', updatedDate: 1 });
    await setDoc(doc(d, 'deliveryCodes/O3'), { customerId: 'C1', code: '123456' });
    await setDoc(doc(d, 'customerPayments/PM1'), payment({ collectedById: DELIVERY, orderId: 'O3' }));
    await setDoc(doc(d, 'customerPayments/PM2'), payment({ collectedById: ACCOUNTANT }));
    await setDoc(doc(d, 'sales/S9'), { status: 'completed', customerId: 'C1', total: 100 });
    await setDoc(doc(d, 'sales/S10'), { status: 'completed', customerId: 'C2', total: 100 });
    await setDoc(doc(d, 'customers/C1'), { name: 'Mine', outstandingBalance: 100, creditLimit: 1000, lastPaymentDate: null });
    await setDoc(doc(d, 'customers/C2'), { name: 'Other', outstandingBalance: 0, creditLimit: 1000, lastPaymentDate: null });
    await setDoc(doc(d, 'products/P1'), { name: 'Rice', unitPrice: 100, stockQty: 10, reservedQty: 0 });
    await setDoc(doc(d, 'productCosts/P1'), { purchasePrice: 80 });
    await setDoc(doc(d, 'orders/O1'), { customerId: 'C1', status: 'placed' });
    await setDoc(doc(d, 'orders/O2'), { customerId: 'C2', status: 'placed' });
    await setDoc(doc(d, 'sales/S1'), { status: 'completed', total: 100 });
    await setDoc(doc(d, 'cashLedger/L1'), { amount: 100, type: 'sale' });
    await setDoc(doc(d, 'auditLog/A1'), { action: 'x' });
    await setDoc(doc(d, 'notifications/N1'), { targetUserId: CUSTOMER, read: false });
    await setDoc(doc(d, 'notifications/N2'), { targetUserId: 'someone-else', read: false });
  });
}

beforeEach(() => env.clearFirestore());

describe('first-run setup', () => {
  test('anyone can check whether setup happened', async () => {
    await assertSucceeds(getDoc(doc(db(null), 'meta/setup')));
  });

  test('the first owner can set up; nobody can set up twice', async () => {
    const owner = db(OWNER);
    const first = writeBatch(owner);
    first.set(doc(owner, `users/${OWNER}`), user('owner'));
    first.set(doc(owner, 'meta/setup'), { ownerId: OWNER });
    await assertSucceeds(first.commit());

    const intruder = db('intruder');
    const second = writeBatch(intruder);
    second.set(doc(intruder, 'users/intruder'), user('owner'));
    second.set(doc(intruder, 'meta/setup'), { ownerId: 'intruder' });
    await assertFails(second.commit());
  });

  test('an owner profile alone (without the setup marker) is refused', async () => {
    await assertFails(setDoc(doc(db('x'), 'users/x'), user('owner')));
  });
});

describe('staff', () => {
  beforeEach(seedBusiness);

  test('employee records a sale with its stock/balance/ledger/audit side effects in one batch', async () => {
    const d = db(EMPLOYEE);
    const batch = writeBatch(d);
    batch.set(doc(d, 'sales/S2'), { status: 'completed', total: 100 });
    batch.set(doc(d, 'products/P1'), { stockQty: increment(-1) }, { merge: true });
    batch.set(doc(d, 'customers/C1'), { outstandingBalance: increment(100) }, { merge: true });
    batch.set(doc(d, 'cashLedger/L2'), { amount: 100, type: 'sale' });
    batch.set(doc(d, 'auditLog/A2'), { action: 'Sale recorded', userId: EMPLOYEE });
    await assertSucceeds(batch.commit());
  });

  test('employee cannot change prices, customer limits, or log expenses', async () => {
    const d = db(EMPLOYEE);
    await assertFails(updateDoc(doc(d, 'products/P1'), { unitPrice: 1 }));
    await assertFails(updateDoc(doc(d, 'customers/C1'), { creditLimit: 999999 }));
    await assertFails(setDoc(doc(d, 'expenses/E1'), { amount: 5 }));
  });

  test('employee cannot cancel a sale; owner can', async () => {
    await assertFails(updateDoc(doc(db(EMPLOYEE), 'sales/S1'), { status: 'cancelled' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), 'sales/S1'), { status: 'cancelled' }));
  });

  test('ledgers and audit log are append-only', async () => {
    await assertFails(updateDoc(doc(db(OWNER), 'cashLedger/L1'), { amount: 1 }));
    await assertFails(updateDoc(doc(db(OWNER), 'auditLog/A1'), { action: 'edited' }));
  });

  test('only the owner reads the audit log', async () => {
    await assertSucceeds(getDoc(doc(db(OWNER), 'auditLog/A1')));
    await assertFails(getDoc(doc(db(ACCOUNTANT), 'auditLog/A1')));
  });

  test('custom permissions replace the role default', async () => {
    await assertFails(setDoc(doc(db(RESTRICTED), 'sales/S3'), { status: 'completed' }));
  });

  test('deactivated accounts can read nothing', async () => {
    await assertFails(getDoc(doc(db(INACTIVE), 'products/P1')));
  });

  test('owner adds staff; staff cannot add staff or edit their own permissions', async () => {
    await assertSucceeds(setDoc(doc(db(OWNER), 'users/new-hire'), user('employee')));
    await assertFails(setDoc(doc(db(ACCOUNTANT), 'users/sneaky'), user('employee')));
    await assertFails(setDoc(doc(db(OWNER), 'users/second-owner'), user('owner')));
    await assertFails(updateDoc(doc(db(EMPLOYEE), `users/${EMPLOYEE}`), { customPermissions: ['manageSettings'] }));
    await assertSucceeds(updateDoc(doc(db(OWNER), `users/${EMPLOYEE}`), { active: false }));
    await assertFails(updateDoc(doc(db(OWNER), `users/${EMPLOYEE}`), { role: 'owner' }));
  });

  test('customer logins must link to an existing customer', async () => {
    await assertSucceeds(setDoc(doc(db(ACCOUNTANT), 'users/cust2'), user('customer', { linkedCustomerId: 'C2' })));
    await assertFails(setDoc(doc(db(ACCOUNTANT), 'users/cust3'), user('customer', { linkedCustomerId: 'nope' })));
  });
});

describe('customers', () => {
  beforeEach(seedBusiness);

  test('see only their own account, orders and notifications', async () => {
    const d = db(CUSTOMER);
    await assertSucceeds(getDoc(doc(d, 'customers/C1')));
    await assertFails(getDoc(doc(d, 'customers/C2')));
    await assertSucceeds(getDocs(query(collection(d, 'orders'), where('customerId', '==', 'C1'))));
    await assertFails(getDocs(collection(d, 'orders')));
    await assertFails(getDoc(doc(d, 'orders/O2')));
    await assertSucceeds(getDocs(query(collection(d, 'notifications'), where('targetUserId', '==', CUSTOMER))));
    await assertFails(getDoc(doc(d, 'notifications/N2')));
  });

  test('cannot read business data', async () => {
    const d = db(CUSTOMER);
    for (const path of ['sales/S1', 'cashLedger/L1', 'auditLog/A1', `users/${OWNER}`]) {
      await assertFails(getDoc(doc(d, path)));
    }
    await assertSucceeds(getDoc(doc(d, 'products/P1')));
  });

  test('can place their own order (reserving stock) but not someone else\'s', async () => {
    const d = db(CUSTOMER);
    const batch = writeBatch(d);
    batch.set(doc(d, 'orders/O30'), { customerId: 'C1', status: 'placed' });
    batch.set(doc(d, 'deliveryCodes/O30'), { customerId: 'C1', code: '654321' });
    batch.set(doc(d, 'products/P1'), { reservedQty: increment(2) }, { merge: true });
    batch.set(doc(d, 'auditLog/A3'), { action: 'Order placed', userId: CUSTOMER });
    batch.set(doc(d, 'notifications/N3'), { targetRole: 'owner', read: false });
    await assertSucceeds(batch.commit());

    await assertFails(setDoc(doc(d, 'orders/O4'), { customerId: 'C2', status: 'placed' }));
    await assertFails(setDoc(doc(d, 'deliveryCodes/O2'), { customerId: 'C1', code: '111111' }), "no code for someone else's order");
    await assertFails(setDoc(doc(d, 'orders/O5'), { customerId: 'C1', status: 'delivered' }));
  });

  test('cannot change stock, prices, balances or order status', async () => {
    const d = db(CUSTOMER);
    await assertFails(updateDoc(doc(d, 'products/P1'), { stockQty: 999 }));
    await assertFails(updateDoc(doc(d, 'products/P1'), { reservedQty: 0 }));
    await assertFails(updateDoc(doc(d, 'customers/C1'), { outstandingBalance: 0 }));
    await assertFails(updateDoc(doc(d, 'orders/O1'), { status: 'delivered' }));
  });

  test('can mark own notifications read, nothing else', async () => {
    const d = db(CUSTOMER);
    await assertSucceeds(updateDoc(doc(d, 'notifications/N1'), { read: true }));
    await assertFails(updateDoc(doc(d, 'notifications/N1'), { title: 'x' }));
  });
});

// Mirrors AppScope._loadPlan (lib/app/injection.dart): every watch a role
// opens at login must be allowed, or that role can't log in at all.
describe('app load plan', () => {
  beforeEach(seedBusiness);

  const staffCollections = ['users', 'products', 'categories', 'stockAdjustments', 'customers', 'suppliers', 'cashLedger', 'expenses',
    'partnerLedger', 'sales', 'purchases', 'purchaseReturns', 'orders', 'notifications', 'settings', 'customerPayments', 'productCosts'];

  for (const [uid, extra] of [[OWNER, ['auditLog']], [ACCOUNTANT, []], [EMPLOYEE, []]]) {
    test(`${uid} can load its plan`, async () => {
      const d = db(uid);
      for (const name of [...staffCollections, ...extra]) {
        await assertSucceeds(getDocs(collection(d, name)));
      }
    });
  }

  test('customer can load its plan', async () => {
    const d = db(CUSTOMER);
    for (const name of ['products', 'categories', 'settings']) await assertSucceeds(getDocs(collection(d, name)));
    await assertSucceeds(getDoc(doc(d, `users/${CUSTOMER}`)));
    await assertSucceeds(getDoc(doc(d, 'customers/C1')));
    await assertSucceeds(getDocs(query(collection(d, 'orders'), where('customerId', '==', 'C1'))));
    await assertSucceeds(getDocs(query(collection(d, 'notifications'), where('targetUserId', '==', CUSTOMER))));
    for (const name of ['sales', 'customerPayments', 'deliveryCodes']) {
      await assertSucceeds(getDocs(query(collection(d, name), where('customerId', '==', 'C1'))));
    }
  });

  test('delivery staff can load their plan', async () => {
    const d = db(DELIVERY);
    for (const name of ['products', 'categories', 'settings', 'customers']) await assertSucceeds(getDocs(collection(d, name)));
    await assertSucceeds(getDoc(doc(d, `users/${DELIVERY}`)));
    await assertSucceeds(getDocs(query(collection(d, 'orders'), where('assignedToId', '==', DELIVERY))));
    await assertSucceeds(getDocs(query(collection(d, 'customerPayments'), where('collectedById', '==', DELIVERY))));
    await assertSucceeds(getDocs(query(collection(d, 'notifications'), where('targetUserId', '==', DELIVERY))));
  });
});

describe('delivery and payment verification', () => {
  beforeEach(seedBusiness);

  /** Everything "Deliver & Collect" writes, as one batch. */
  function deliverBatch(d, code) {
    const batch = writeBatch(d);
    batch.set(doc(d, 'orders/O3'), { status: 'delivered', updatedDate: 2 }, { merge: true });
    batch.set(doc(d, 'products/P1'), { stockQty: increment(-1) }, { merge: true });
    batch.set(doc(d, 'sales/INV1'), { status: 'completed', customerId: 'C1', orderId: 'O3', total: 5000, isCredit: true });
    batch.set(doc(d, 'customers/C1'), { outstandingBalance: increment(-2000), lastPaymentDate: 5 }, { merge: true });
    batch.set(doc(d, 'customerPayments/PM9'), payment({ collectedById: DELIVERY, orderId: 'O3', deliveryCode: code }));
    batch.set(doc(d, 'auditLog/A9'), { action: 'Order invoiced', userId: DELIVERY });
    return batch;
  }

  test('only the customer can see the delivery code', async () => {
    await assertFails(getDoc(doc(db(DELIVERY), 'deliveryCodes/O3')));
    await assertFails(getDoc(doc(db(OWNER), 'deliveryCodes/O3')));
    await assertSucceeds(getDoc(doc(db(CUSTOMER), 'deliveryCodes/O3')));
  });

  const attempt = (d, code, n) => setDoc(doc(d, 'codeChecks/O3'), { lastCode: code, attempts: n, verified: false }, { merge: true });
  const verify = (d) => updateDoc(doc(d, 'codeChecks/O3'), { verified: true });

  test('deliver & collect succeeds with the right code, fails with a wrong one', async () => {
    const d = db(DELIVERY);
    await assertSucceeds(attempt(d, '000000', 1));
    await assertFails(verify(d), 'wrong code cannot be verified');
    await assertFails(deliverBatch(d, '000000').commit(), 'unverified code');
    await assertSucceeds(attempt(d, '123456', 2));
    await assertSucceeds(verify(d));
    await assertSucceeds(deliverBatch(d, '123456').commit());
  });

  test('a code must be registered as an attempt first, and attempts stop at 5', async () => {
    const d = db(DELIVERY);
    await assertFails(deliverBatch(d, '123456').commit(), 'right code, but never registered');
    await assertFails(setDoc(doc(d, 'codeChecks/O3'), { lastCode: '123456', attempts: 1, verified: true }), 'cannot register already-verified');
    await assertFails(attempt(d, '111111', 2), 'must start at 1');
    for (let n = 1; n <= 5; n++) await assertSucceeds(attempt(d, `00000${n}`, n));
    await assertFails(attempt(d, '123456', 6), 'locked after 5');
    await assertFails(attempt(d, '123456', 5), 'cannot rewind the counter');
    await assertFails(deleteDoc(doc(d, 'codeChecks/O3')), 'only the owner unlocks');
    await assertSucceeds(deleteDoc(doc(db(OWNER), 'codeChecks/O3')));
    await assertSucceeds(attempt(d, '123456', 1));
    await assertSucceeds(verify(d));
    await assertSucceeds(deliverBatch(d, '123456').commit());
  });

  test('a delivery person can only deliver and collect for orders assigned to them', async () => {
    await assertFails(deliverBatch(db('someone-else'), null).commit());
    await assertFails(getDoc(doc(db(DELIVERY), 'orders/O1')));
    await assertFails(getDoc(doc(db(DELIVERY), 'sales/S1')));
    await assertFails(getDoc(doc(db(DELIVERY), 'cashLedger/L1')));
    await assertFails(setDoc(doc(db(DELIVERY), 'customerPayments/PM8'), payment({ collectedById: DELIVERY })), 'counter payments need recordPayments');
  });

  test('handover: only reconcileCash, never your own collection (except the owner)', async () => {
    const settle = (amount) => ({ settledAt: 10, settledAmount: amount, settledById: '', settledByName: 'x' });
    await assertFails(updateDoc(doc(db(DELIVERY), 'customerPayments/PM1'), { ...settle(7000), settledById: DELIVERY }));
    await assertFails(updateDoc(doc(db(EMPLOYEE), 'customerPayments/PM1'), { ...settle(7000), settledById: EMPLOYEE }));
    await assertFails(updateDoc(doc(db(ACCOUNTANT), 'customerPayments/PM2'), { ...settle(7000), settledById: ACCOUNTANT }), 'own collection');
    await assertFails(updateDoc(doc(db(ACCOUNTANT), 'customerPayments/PM1'), { ...settle(8000), settledById: ACCOUNTANT }), 'more than collected');
    await assertSucceeds(updateDoc(doc(db(ACCOUNTANT), 'customerPayments/PM1'), { ...settle(6500), settledById: ACCOUNTANT }));
    await assertFails(updateDoc(doc(db(OWNER), 'customerPayments/PM1'), { ...settle(7000), settledById: OWNER }), 'already settled');
  });

  test('amounts and collectors can never be edited', async () => {
    await assertFails(updateDoc(doc(db(OWNER), 'customerPayments/PM1'), { amount: 1 }));
    await assertFails(updateDoc(doc(db(OWNER), 'customerPayments/PM1'), { collectedById: OWNER }));
  });

  test('the customer confirms once or disputes once, and nothing else', async () => {
    const d = db(CUSTOMER);
    await assertSucceeds(updateDoc(doc(d, 'customerPayments/PM1'), { customerConfirmedAt: 10 }));
    await assertFails(updateDoc(doc(d, 'customerPayments/PM1'), { customerConfirmedAt: 11 }));
    await assertSucceeds(updateDoc(doc(d, 'customerPayments/PM2'), { disputedAt: 10, disputeNote: 'I paid 200' }));
    await assertFails(updateDoc(doc(d, 'customerPayments/PM2'), { disputedAt: 11, disputeNote: 'changed my mind' }));
    await assertFails(updateDoc(doc(d, 'customerPayments/PM2'), { amount: 200 }));
    await assertFails(setDoc(doc(d, 'customerPayments/PM7'), payment({ collectedById: CUSTOMER })), 'customers cannot record payments');
  });

  test('only the owner reverses — before or after it reached the till — and only once', async () => {
    const reverse = { reversedAt: 10, reversedByName: 'x', reversalReason: 'wrong' };
    await assertFails(updateDoc(doc(db(ACCOUNTANT), 'customerPayments/PM1'), reverse));
    await assertSucceeds(updateDoc(doc(db(OWNER), 'customerPayments/PM1'), reverse));
    await assertFails(updateDoc(doc(db(OWNER), 'customerPayments/PM1'), { ...reverse, reversalReason: 'again' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), 'customerPayments/PM2'), { settledAt: 10, settledAmount: 7000, settledById: OWNER, settledByName: 'o' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), 'customerPayments/PM2'), reverse));
  });

  test('cost prices are staff-only and never on the catalogue', async () => {
    await assertFails(getDoc(doc(db(CUSTOMER), 'productCosts/P1')));
    await assertFails(getDoc(doc(db(DELIVERY), 'productCosts/P1')));
    await assertSucceeds(getDoc(doc(db(EMPLOYEE), 'productCosts/P1')));
    await assertFails(setDoc(doc(db(OWNER), 'products/P9'), { name: 'x', purchasePrice: 1 }));
    await assertFails(updateDoc(doc(db(OWNER), 'products/P1'), { purchasePrice: 1 }));
    await assertSucceeds(updateDoc(doc(db(ACCOUNTANT), 'productCosts/P1'), { purchasePrice: 85 }), 'receiving a purchase');
    await assertFails(updateDoc(doc(db(EMPLOYEE), 'productCosts/P1'), { purchasePrice: 1 }));
  });

  test('audit entries carry the real author', async () => {
    await assertSucceeds(setDoc(doc(db(EMPLOYEE), 'auditLog/A20'), { action: 'x', userId: EMPLOYEE }));
    await assertFails(setDoc(doc(db(EMPLOYEE), 'auditLog/A21'), { action: 'x', userId: OWNER }));
    await assertFails(setDoc(doc(db(EMPLOYEE), 'auditLog/A22'), { action: 'x' }));
  });

  test('customers see only their own bills; opening balances are fixed', async () => {
    await assertSucceeds(getDoc(doc(db(CUSTOMER), 'sales/S9')));
    await assertFails(getDoc(doc(db(CUSTOMER), 'sales/S10')));
    await assertFails(updateDoc(doc(db(OWNER), 'customers/C1'), { openingBalance: 0 }));
  });
});

describe('business reset', () => {
  beforeEach(seedBusiness);

  test('only the owner can delete, and can finish by deleting their own profile and the setup marker', async () => {
    for (const uid of [ACCOUNTANT, EMPLOYEE, DELIVERY, CUSTOMER]) {
      await assertFails(deleteDoc(doc(db(uid), 'customerPayments/PM1')));
      await assertFails(deleteDoc(doc(db(uid), 'cashLedger/L1')));
    }
    const d = db(OWNER);
    for (const path of ['customerPayments/PM1', 'cashLedger/L1', 'auditLog/A1', 'deliveryCodes/O3', 'codeChecks/O3', 'productCosts/P1', `users/${EMPLOYEE}`]) {
      await assertSucceeds(deleteDoc(doc(d, path)));
    }
    const last = writeBatch(d);
    last.delete(doc(d, `users/${OWNER}`));
    last.delete(doc(d, 'meta/setup'));
    await assertSucceeds(last.commit());
    await assertFails(deleteDoc(doc(d, 'sales/S1')), 'no profile left: no more deletes');
  });
});
