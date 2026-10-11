// Security-rules tests for ../firestore.rules, run against the emulator.
// From the project root:
//   (cd firestore_tests && npm install)
//   firebase emulators:exec --only firestore --project demo-sarathi "cd firestore_tests && npm test"
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { arrayUnion, collection, deleteDoc, doc, getDoc, getDocs, increment, query, setDoc, updateDoc, where, writeBatch } from 'firebase/firestore';

let env;

const SHOP = 'S1';
const OTHER_SHOP = 'S2';
const OTHER_OWNER = 'other-owner-uid';
/** A path inside a shop (default: the main test shop). */
const p = (path, shop = SHOP) => `shops/${shop}/${path}`;

const OWNER = 'owner-uid';
const EMPLOYEE = 'employee-uid';
const CASHIER = 'cashier-uid'; // staff with "Can handle cash & accounts"
const RESTRICTED = 'restricted-uid';
const INACTIVE = 'inactive-uid';
const DELIVERY = 'delivery-uid';

// Mirrors defaultRolePermissions[employee] + cashPermissions in permission.dart.
const CASH_STAFF_PERMISSIONS = ['viewSales', 'createSales', 'viewCustomers', 'recordPayments', 'deliverOrders', 'createCustomers',
  'viewPurchases', 'createPurchases', 'manageCustomers', 'viewSuppliers', 'manageSuppliers', 'manageExpenses', 'viewAccounting', 'viewReports', 'reconcileCash'];

const user = (role, extra = {}) => ({ name: role, phone: `98${role.length}`, role, active: true, customPermissions: null, ...extra });

const payment = (extra = {}) => ({
  customerId: 'C1', amount: 7000, method: 'cash', reference: '', orderId: null, collectedById: EMPLOYEE, collectedByName: 'x',
  disputedAt: null, disputeNote: '', settledAt: null, settledAmount: null,
  settledById: null, settledByName: '', reversedAt: null, reversedByName: '', reversalReason: '', ...extra,
});

const ALL_SAFEGUARDS = ['signature', 'phoneConfirm', 'handover', 'onlineOnly'];

/** Sets the main shop's safeguards (Settings → Safeguards). */
const safeguards = (list) => env.withSecurityRulesDisabled((ctx) =>
  setDoc(doc(ctx.firestore(), p('settings/business')), { safeguards: list }, { merge: true }));

const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();
/** A login whose email is verified (opened the sign-up link). */
const verified = (uid) => env.authenticatedContext(uid, { email: `${uid}@shop.test`, email_verified: true }).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sarathi',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

/** A shop that's already set up, seeded with rules disabled. */
async function seedBusiness() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, `shops/${SHOP}`), { ownerId: OWNER, createdAt: 1 });
    // Safeguards on: the tests below cover the strict behaviour unless they switch them off.
    await setDoc(doc(d, p('settings/business')), { businessName: 'Test', features: [], safeguards: ALL_SAFEGUARDS });
    for (const uid of [OWNER, EMPLOYEE, CASHIER, RESTRICTED, INACTIVE, DELIVERY]) await setDoc(doc(d, `accounts/${uid}`), { shopIds: [SHOP] });
    await setDoc(doc(d, p(`users/${OWNER}`)), user('owner'));
    await setDoc(doc(d, p(`users/${EMPLOYEE}`)), user('employee'));
    await setDoc(doc(d, p(`users/${CASHIER}`)), user('employee', { customPermissions: CASH_STAFF_PERMISSIONS }));
    await setDoc(doc(d, p(`users/${RESTRICTED}`)), user('employee', { customPermissions: ['viewSales'] }));
    await setDoc(doc(d, p(`users/${INACTIVE}`)), user('employee', { active: false }));
    await setDoc(doc(d, p(`users/${DELIVERY}`)), user('delivery'));
    await setDoc(doc(d, p('orders/O3')), { customerId: 'C1', status: 'outForDelivery', assignedToId: DELIVERY, assignedToName: 'delivery', updatedDate: 1 });
    await setDoc(doc(d, p('customerPayments/PM1')), payment({ collectedById: DELIVERY, orderId: 'O3' }));
    await setDoc(doc(d, p('customerPayments/PM2')), payment({ collectedById: CASHIER }));
    await setDoc(doc(d, p('customerPayments/PM3')), payment({ signature: '1,1 2,2', signedName: 'x' }));
    await setDoc(doc(d, p('customers/C1')), { name: 'Mine', outstandingBalance: 100, creditLimit: 1000, lastPaymentDate: null });
    await setDoc(doc(d, p('customers/C2')), { name: 'Other', outstandingBalance: 0, creditLimit: 1000, lastPaymentDate: null });
    await setDoc(doc(d, p('products/P1')), { name: 'Rice', unitPrice: 100, stockQty: 10, reservedQty: 0 });
    await setDoc(doc(d, p('productCosts/P1')), { purchasePrice: 80 });
    await setDoc(doc(d, p('orders/O1')), { customerId: 'C1', status: 'placed' });
    await setDoc(doc(d, p('orders/O2')), { customerId: 'C2', status: 'placed' });
    await setDoc(doc(d, p('sales/S1')), { status: 'completed', total: 100 });
    await setDoc(doc(d, p('cashLedger/L1')), { amount: 100, type: 'sale' });
    await setDoc(doc(d, p('auditLog/A1')), { action: 'x' });
    await setDoc(doc(d, p('notifications/N1')), { targetUserId: DELIVERY, read: false });
    await setDoc(doc(d, p('notifications/N2')), { targetUserId: 'someone-else', read: false });
  });
}

beforeEach(() => env.clearFirestore());

/** Everything "Set up a new business" writes, as one batch. */
function setupBatch(d, uid, shop, accountShops = [shop]) {
  const batch = writeBatch(d);
  batch.set(doc(d, `shops/${shop}`), { ownerId: uid, createdAt: 1 });
  batch.set(doc(d, p(`users/${uid}`, shop)), user('owner'));
  batch.set(doc(d, `accounts/${uid}`), { shopIds: accountShops });
  batch.set(doc(d, p('settings/business', shop)), { businessName: 'New', features: [] });
  return batch;
}

describe('shop setup', () => {
  test('any signed-in user can create a shop they own, in one batch', async () => {
    await assertSucceeds(setupBatch(verified(OWNER), OWNER, SHOP).commit());
    await assertFails(setupBatch(db(null), 'x', 'S9').commit(), 'signed out');
  });

  test('a login without a verified email cannot create a shop', async () => {
    await assertFails(setupBatch(db(OWNER), OWNER, SHOP).commit());
    const unverified = env.authenticatedContext(OWNER, { email: `${OWNER}@shop.test`, email_verified: false }).firestore();
    await assertFails(setupBatch(unverified, OWNER, SHOP).commit());
  });

  test('an existing shop cannot be set up again or taken over', async () => {
    await assertSucceeds(setupBatch(verified(OWNER), OWNER, SHOP).commit());
    await assertFails(setupBatch(verified('intruder'), 'intruder', SHOP).commit());
    await assertFails(setDoc(doc(db('intruder'), p('users/intruder')), user('owner')));
    await assertFails(setDoc(doc(db('intruder'), p('settings/business')), { businessName: 'Mine now' }));
  });

  test('an owner profile alone, or a shop owned by someone else, is refused', async () => {
    await assertFails(setDoc(doc(db('x'), p('users/x', 'S9')), user('owner')));
    const d = verified('x');
    const batch = writeBatch(d);
    batch.set(doc(d, 'shops/S9'), { ownerId: 'victim', createdAt: 1 });
    batch.set(doc(d, p('users/victim', 'S9')), user('owner'));
    await assertFails(batch.commit());
  });

  test('an owner of one shop can create another; the new shop is appended to their account', async () => {
    await assertSucceeds(setupBatch(verified(OWNER), OWNER, SHOP).commit());
    await assertSucceeds(setupBatch(verified(OWNER), OWNER, OTHER_SHOP, [SHOP, OTHER_SHOP]).commit());
  });
});

describe('staff', () => {
  beforeEach(seedBusiness);

  test('employee records a sale with its stock/balance/ledger/audit side effects in one batch', async () => {
    const d = db(EMPLOYEE);
    const batch = writeBatch(d);
    batch.set(doc(d, p('sales/S2')), { status: 'completed', total: 100 });
    batch.set(doc(d, p('products/P1')), { stockQty: increment(-1) }, { merge: true });
    batch.set(doc(d, p('customers/C1')), { outstandingBalance: increment(100) }, { merge: true });
    batch.set(doc(d, p('cashLedger/L2')), { amount: 100, type: 'sale' });
    batch.set(doc(d, p('auditLog/A2')), { action: 'Sale recorded', userId: EMPLOYEE });
    await assertSucceeds(batch.commit());
  });

  test('employee cannot change prices, customer limits, or log expenses', async () => {
    const d = db(EMPLOYEE);
    await assertFails(updateDoc(doc(d, p('products/P1')), { unitPrice: 1 }));
    await assertFails(updateDoc(doc(d, p('customers/C1')), { creditLimit: 999999 }));
    await assertFails(setDoc(doc(d, p('expenses/E1')), { amount: 5 }));
  });

  test('employee cannot cancel a sale; owner can', async () => {
    await assertFails(updateDoc(doc(db(EMPLOYEE), p('sales/S1')), { status: 'cancelled' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), p('sales/S1')), { status: 'cancelled' }));
  });

  test('ledgers and audit log are append-only', async () => {
    await assertFails(updateDoc(doc(db(OWNER), p('cashLedger/L1')), { amount: 1 }));
    await assertFails(updateDoc(doc(db(OWNER), p('auditLog/A1')), { action: 'edited' }));
  });

  test('only the owner reads the audit log', async () => {
    await assertSucceeds(getDoc(doc(db(OWNER), p('auditLog/A1'))));
    await assertFails(getDoc(doc(db(CASHIER), p('auditLog/A1'))));
  });

  test('staff granted manageSettings can edit settings but never the safeguards', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      updateDoc(doc(ctx.firestore(), p(`users/${EMPLOYEE}`)), { customPermissions: ['manageSettings'] }));
    const settings = doc(db(EMPLOYEE), p('settings/business'));
    await assertSucceeds(updateDoc(settings, { businessName: 'Renamed' }));
    await assertFails(updateDoc(settings, { safeguards: [] }));
    await assertFails(deleteDoc(settings));
    await assertSucceeds(updateDoc(doc(db(OWNER), p('settings/business')), { safeguards: [] }));
  });

  test('custom permissions replace the role default', async () => {
    await assertFails(setDoc(doc(db(RESTRICTED), p('sales/S3')), { status: 'completed' }));
  });

  test('deactivated accounts can read nothing', async () => {
    await assertFails(getDoc(doc(db(INACTIVE), p('products/P1'))));
  });

  test('owner adds staff; staff cannot add staff or edit their own permissions', async () => {
    await assertSucceeds(setDoc(doc(db(OWNER), p('users/new-hire')), user('employee')));
    await assertFails(setDoc(doc(db(CASHIER), p('users/sneaky')), user('employee')));
    await assertSucceeds(setDoc(doc(db(OWNER), p('users/second-owner')), user('owner')), 'the founder adds a co-owner');
    await assertFails(setDoc(doc(db(OWNER), p('users/old-role')), user('accountant')), 'accountant is a staff toggle now');
    await assertFails(updateDoc(doc(db(EMPLOYEE), p(`users/${EMPLOYEE}`)), { customPermissions: ['manageSettings'] }));
    await assertSucceeds(updateDoc(doc(db(OWNER), p(`users/${EMPLOYEE}`)), { active: false }));
    await assertFails(updateDoc(doc(db(OWNER), p(`users/${EMPLOYEE}`)), { role: 'owner' }));
  });

  test('nobody can create a customer login', async () => {
    await assertFails(setDoc(doc(db(OWNER), p('users/cust2')), user('customer')));
  });
});

// Mirrors AppScope._loadPlan (lib/app/injection.dart): every watch a role
// opens at login must be allowed, or that role can't log in at all.
describe('app load plan', () => {
  beforeEach(seedBusiness);

  const staffCollections = ['users', 'products', 'categories', 'stockAdjustments', 'customers', 'suppliers', 'cashLedger', 'expenses',
    'journal', 'creditNotes', 'sales', 'purchases', 'purchaseReturns', 'orders', 'notifications', 'settings', 'customerPayments', 'productCosts'];

  for (const [uid, extra] of [[OWNER, ['auditLog']], [CASHIER, []], [EMPLOYEE, []]]) {
    test(`${uid} can load its plan`, async () => {
      const d = db(uid);
      for (const name of [...staffCollections, ...extra]) {
        await assertSucceeds(getDocs(collection(d, p(name))));
      }
    });
  }

  test('login: every account reads its shop list and probes its own profile, even where it has none', async () => {
    for (const uid of [OWNER, EMPLOYEE, DELIVERY, INACTIVE]) {
      await assertSucceeds(getDoc(doc(db(uid), `accounts/${uid}`)));
      await assertSucceeds(getDoc(doc(db(uid), p(`users/${uid}`))));
    }
    await assertSucceeds(getDoc(doc(db(EMPLOYEE), p(`users/${EMPLOYEE}`, 'stale-shop'))));
  });

  test('delivery staff can load their plan', async () => {
    const d = db(DELIVERY);
    for (const name of ['products', 'categories', 'settings', 'customers']) await assertSucceeds(getDocs(collection(d, p(name))));
    await assertSucceeds(getDoc(doc(d, p(`users/${DELIVERY}`))));
    await assertSucceeds(getDocs(query(collection(d, p('orders')), where('assignedToId', '==', DELIVERY))));
    await assertSucceeds(getDocs(query(collection(d, p('customerPayments')), where('collectedById', '==', DELIVERY))));
    await assertSucceeds(getDocs(query(collection(d, p('notifications')), where('targetUserId', '==', DELIVERY))));
  });
});

describe('delivery and payment verification', () => {
  beforeEach(seedBusiness);

  /** Everything "Deliver & Collect" writes, as one batch. */
  function deliverBatch(d) {
    const batch = writeBatch(d);
    batch.set(doc(d, p('orders/O3')), { status: 'delivered', updatedDate: 2, receivedSignature: '1,1 2,2', receivedBy: 'x' }, { merge: true });
    batch.set(doc(d, p('products/P1')), { stockQty: increment(-1) }, { merge: true });
    batch.set(doc(d, p('sales/INV1')), { status: 'completed', customerId: 'C1', orderId: 'O3', total: 5000, isCredit: true });
    batch.set(doc(d, p('customers/C1')), { outstandingBalance: increment(-2000), lastPaymentDate: 5 }, { merge: true });
    batch.set(doc(d, p('customerPayments/PM9')), payment({ collectedById: DELIVERY, orderId: 'O3', signature: '1,1 2,2', signedName: 'x' }));
    batch.set(doc(d, p('auditLog/A9')), { action: 'Order invoiced', userId: DELIVERY });
    return batch;
  }

  test('the assigned delivery person delivers and collects in one batch', async () => {
    await assertSucceeds(deliverBatch(db(DELIVERY)).commit());
  });

  test('a delivery person can only deliver and collect for orders assigned to them', async () => {
    await assertFails(deliverBatch(db('someone-else')).commit());
    await assertFails(getDoc(doc(db(DELIVERY), p('orders/O1'))));
    await assertFails(getDoc(doc(db(DELIVERY), p('sales/S1'))));
    await assertFails(getDoc(doc(db(DELIVERY), p('cashLedger/L1'))));
    await assertFails(setDoc(doc(db(DELIVERY), p('customerPayments/PM8')), payment({ collectedById: DELIVERY })), 'counter payments need recordPayments');
  });

  test('handover: only reconcileCash, never your own collection (except the owner)', async () => {
    const settle = (amount) => ({ settledAt: 10, settledAmount: amount, settledById: '', settledByName: 'x' });
    await assertFails(updateDoc(doc(db(DELIVERY), p('customerPayments/PM1')), { ...settle(7000), settledById: DELIVERY }));
    await assertFails(updateDoc(doc(db(EMPLOYEE), p('customerPayments/PM1')), { ...settle(7000), settledById: EMPLOYEE }));
    await assertFails(updateDoc(doc(db(CASHIER), p('customerPayments/PM2')), { ...settle(7000), settledById: CASHIER }), 'own collection');
    await assertFails(updateDoc(doc(db(CASHIER), p('customerPayments/PM1')), { ...settle(8000), settledById: CASHIER }), 'more than collected');
    await assertSucceeds(updateDoc(doc(db(CASHIER), p('customerPayments/PM1')), { ...settle(6500), settledById: CASHIER }));
    await assertFails(updateDoc(doc(db(OWNER), p('customerPayments/PM1')), { ...settle(7000), settledById: OWNER }), 'already settled');
  });

  test('"Can handle cash & accounts" is an override the owner grants and revokes', async () => {
    const settle = { settledAt: 10, settledAmount: 7000, settledById: EMPLOYEE, settledByName: 'x' };
    await assertSucceeds(updateDoc(doc(db(OWNER), p(`users/${EMPLOYEE}`)), { customPermissions: CASH_STAFF_PERMISSIONS }));
    await assertSucceeds(updateDoc(doc(db(EMPLOYEE), p('customerPayments/PM1')), settle));
    await assertSucceeds(setDoc(doc(db(CASHIER), p('expenses/E8')), { amount: 1 }));
    await assertSucceeds(updateDoc(doc(db(OWNER), p(`users/${CASHIER}`)), { customPermissions: null }));
    await assertFails(setDoc(doc(db(CASHIER), p('expenses/E9')), { amount: 1 }), 'toggle off: back to employee defaults');
  });

  test('amounts and collectors can never be edited', async () => {
    await assertFails(updateDoc(doc(db(OWNER), p('customerPayments/PM1')), { amount: 1 }));
    await assertFails(updateDoc(doc(db(OWNER), p('customerPayments/PM1')), { collectedById: OWNER }));
  });

  test('only the owner reverses — before or after it reached the till — and only once', async () => {
    const reverse = { reversedAt: 10, reversedByName: 'x', reversalReason: 'wrong' };
    await assertFails(updateDoc(doc(db(CASHIER), p('customerPayments/PM1')), reverse));
    await assertSucceeds(updateDoc(doc(db(OWNER), p('customerPayments/PM1')), reverse));
    await assertFails(updateDoc(doc(db(OWNER), p('customerPayments/PM1')), { ...reverse, reversalReason: 'again' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), p('customerPayments/PM2')), { settledAt: 10, settledAmount: 7000, settledById: OWNER, settledByName: 'o' }));
    await assertSucceeds(updateDoc(doc(db(OWNER), p('customerPayments/PM2')), reverse));
  });

  test('cost prices are staff-only and never on the catalogue', async () => {
    await assertFails(getDoc(doc(db(DELIVERY), p('productCosts/P1'))));
    await assertSucceeds(getDoc(doc(db(EMPLOYEE), p('productCosts/P1'))));
    await assertFails(setDoc(doc(db(OWNER), p('products/P9')), { name: 'x', purchasePrice: 1 }));
    await assertFails(updateDoc(doc(db(OWNER), p('products/P1')), { purchasePrice: 1 }));
    await assertSucceeds(updateDoc(doc(db(CASHIER), p('productCosts/P1')), { purchasePrice: 85 }), 'receiving a purchase');
    await assertFails(updateDoc(doc(db(EMPLOYEE), p('productCosts/P1')), { purchasePrice: 1 }));
  });

  test('audit entries carry the real author', async () => {
    await assertSucceeds(setDoc(doc(db(EMPLOYEE), p('auditLog/A20')), { action: 'x', userId: EMPLOYEE }));
    await assertFails(setDoc(doc(db(EMPLOYEE), p('auditLog/A21')), { action: 'x', userId: OWNER }));
    await assertFails(setDoc(doc(db(EMPLOYEE), p('auditLog/A22')), { action: 'x' }));
  });

  test('opening balances are fixed', async () => {
    await assertFails(updateDoc(doc(db(OWNER), p('customers/C1')), { openingBalance: 0 }));
  });
});

describe('business reset', () => {
  beforeEach(seedBusiness);

  test('only the owner can delete, and can finish by deleting their profile, the shop and their account entry', async () => {
    for (const uid of [CASHIER, EMPLOYEE, DELIVERY]) {
      await assertFails(deleteDoc(doc(db(uid), p('customerPayments/PM1'))));
      await assertFails(deleteDoc(doc(db(uid), p('cashLedger/L1'))));
    }
    const d = db(OWNER);
    for (const path of ['customerPayments/PM1', 'cashLedger/L1', 'auditLog/A1', 'productCosts/P1', `users/${EMPLOYEE}`]) {
      await assertSucceeds(deleteDoc(doc(d, p(path))));
    }
    const last = writeBatch(d);
    last.delete(doc(d, p(`users/${OWNER}`)));
    last.delete(doc(d, `shops/${SHOP}`));
    last.set(doc(d, `accounts/${OWNER}`), { shopIds: [] }, { merge: true });
    await assertSucceeds(last.commit());
    await assertFails(deleteDoc(doc(d, p('sales/S1'))), 'no profile left: no more deletes');
  });
});

/** A second, unrelated shop with its own owner and data. */
async function seedOtherShop() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const d = ctx.firestore();
    await setDoc(doc(d, `shops/${OTHER_SHOP}`), { ownerId: OTHER_OWNER, createdAt: 1 });
    await setDoc(doc(d, `accounts/${OTHER_OWNER}`), { shopIds: [OTHER_SHOP] });
    await setDoc(doc(d, p(`users/${OTHER_OWNER}`, OTHER_SHOP)), user('owner'));
    await setDoc(doc(d, p('products/P1', OTHER_SHOP)), { name: 'Theirs', unitPrice: 100, stockQty: 10, reservedQty: 0 });
    await setDoc(doc(d, p('customers/C1', OTHER_SHOP)), { name: 'Theirs', outstandingBalance: 0, creditLimit: 0, lastPaymentDate: null });
    await setDoc(doc(d, p('settings/business', OTHER_SHOP)), { businessName: 'Other' });
    await setDoc(doc(d, p('sales/S1', OTHER_SHOP)), { status: 'completed', total: 100 });
  });
}

describe('shop isolation', () => {
  beforeEach(async () => {
    await seedBusiness();
    await seedOtherShop();
  });

  test('members of one shop cannot read another shop', async () => {
    for (const uid of [OWNER, CASHIER, EMPLOYEE, DELIVERY]) {
      const d = db(uid);
      for (const path of ['products/P1', 'customers/C1', 'settings/business', 'sales/S1', `users/${OTHER_OWNER}`]) {
        await assertFails(getDoc(doc(d, p(path, OTHER_SHOP))), `${uid} read ${path}`);
      }
      await assertFails(getDocs(collection(d, p('products', OTHER_SHOP))));
      await assertFails(getDoc(doc(d, `shops/${OTHER_SHOP}`)));
    }
    await assertFails(getDoc(doc(db(OTHER_OWNER), p('products/P1'))), 'and the other way round');
  });

  test('members of one shop cannot write or delete in another shop', async () => {
    const d = db(OWNER);
    await assertFails(setDoc(doc(d, p('sales/S9', OTHER_SHOP)), { status: 'completed', total: 1 }));
    await assertFails(updateDoc(doc(d, p('products/P1', OTHER_SHOP)), { stockQty: increment(-1) }));
    await assertFails(setDoc(doc(d, p('products/P9', OTHER_SHOP)), { name: 'x' }));
    await assertFails(setDoc(doc(d, p('auditLog/A9', OTHER_SHOP)), { action: 'x', userId: OWNER }));
    await assertFails(setDoc(doc(d, p('settings/business', OTHER_SHOP)), { businessName: 'Hijacked' }));
    await assertFails(deleteDoc(doc(d, p('sales/S1', OTHER_SHOP))));
    await assertFails(deleteDoc(doc(d, `shops/${OTHER_SHOP}`)));
  });

  test('nobody can add themselves (or a second owner) to another shop', async () => {
    const d = db(OWNER);
    await assertFails(setDoc(doc(d, p(`users/${OWNER}`, OTHER_SHOP)), user('owner')));
    await assertFails(setDoc(doc(d, p(`users/${OWNER}`, OTHER_SHOP)), user('employee')));
    await assertFails(setDoc(doc(d, p('users/friend', OTHER_SHOP)), user('employee')));
  });

  test('top-level (pre-multi-shop) collections are closed', async () => {
    await assertFails(getDoc(doc(db(OWNER), 'products/P1')));
    await assertFails(setDoc(doc(db(OWNER), 'products/P1'), { name: 'x' }));
  });
});

describe('accounts', () => {
  beforeEach(async () => {
    await seedBusiness();
    await seedOtherShop();
  });

  test('an account reads only its own shop list', async () => {
    await assertSucceeds(getDoc(doc(db(EMPLOYEE), `accounts/${EMPLOYEE}`)));
    await assertFails(getDoc(doc(db(OWNER), `accounts/${EMPLOYEE}`)));
    await assertFails(getDoc(doc(db(null), `accounts/${EMPLOYEE}`)));
  });

  test('the owner adds a new staff member: profile + account entry for their own shop', async () => {
    const d = db(OWNER);
    const batch = writeBatch(d);
    batch.set(doc(d, p('users/new-hire')), user('employee'));
    batch.set(doc(d, 'accounts/new-hire'), { shopIds: [SHOP] }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  test('a shop can only be added to an account that has a profile in it, by its manager', async () => {
    await assertFails(setDoc(doc(db(OWNER), 'accounts/nobody'), { shopIds: [SHOP] }), 'no profile in the shop');
    await assertFails(setDoc(doc(db(OWNER), 'accounts/nobody'), { shopIds: [OTHER_SHOP] }), 'not their shop');
    const d = db(EMPLOYEE);
    const batch = writeBatch(d);
    batch.set(doc(d, p('users/hire2')), user('employee'));
    batch.set(doc(d, 'accounts/hire2'), { shopIds: [SHOP] });
    await assertFails(batch.commit(), 'no manageEmployees');
  });

  test('a manager can append only their own shop to an existing account', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), p(`users/${OTHER_OWNER}`)), user('employee')));
    await assertSucceeds(updateDoc(doc(db(OWNER), `accounts/${OTHER_OWNER}`), { shopIds: arrayUnion(SHOP) }));
    await assertFails(updateDoc(doc(db(OWNER), `accounts/${EMPLOYEE}`), { shopIds: arrayUnion(OTHER_SHOP) }), 'another shop');
    await assertFails(updateDoc(doc(db(OWNER), `accounts/${EMPLOYEE}`), { shopIds: [] }), 'only the account itself removes');
    await assertFails(updateDoc(doc(db(OWNER), `accounts/${EMPLOYEE}`), { shopIds: [SHOP], extra: 1 }));
  });

  test('an account cannot add a shop it has no profile in, but can drop entries', async () => {
    await assertFails(updateDoc(doc(db(EMPLOYEE), `accounts/${EMPLOYEE}`), { shopIds: [SHOP, OTHER_SHOP] }));
    await assertFails(updateDoc(doc(db(EMPLOYEE), `accounts/${EMPLOYEE}`), { shopIds: [OTHER_SHOP] }), 'swap is not a removal');
    await assertSucceeds(updateDoc(doc(db(EMPLOYEE), `accounts/${EMPLOYEE}`), { shopIds: [] }));
  });
});

describe('emails', () => {
  const as = (uid, local) => env.authenticatedContext(uid, { email: `${local}@shop.test` }).firestore();

  test('a login registers its own email; nobody claims or overwrites another email', async () => {
    await assertSucceeds(setDoc(doc(as(EMPLOYEE, '9800000003'), 'emails/9800000003@shop.test'), { uid: EMPLOYEE }));
    await assertSucceeds(setDoc(doc(as(EMPLOYEE, '9800000003'), 'emails/9800000003@shop.test'), { uid: EMPLOYEE }, { merge: true }));
    await assertFails(setDoc(doc(as(OWNER, '9800000001'), 'emails/9800000003@shop.test'), { uid: OWNER }), 'not their email');
    await assertFails(setDoc(doc(as(OWNER, '9800000001'), 'emails/9800000009@shop.test'), { uid: OWNER }), 'unclaimed, still not theirs');
    await assertFails(setDoc(doc(as(OWNER, '9800000001'), 'emails/9800000001@shop.test'), { uid: EMPLOYEE }), 'must point at itself');
    await assertFails(setDoc(doc(as(OWNER, '9800000001'), 'emails/9800000001@shop.test'), { uid: OWNER, extra: 1 }));
    await assertFails(setDoc(doc(db(OWNER), 'emails/9800000001@shop.test'), { uid: OWNER }), 'no email in the token');
    await assertFails(deleteDoc(doc(as(OWNER, '9800000001'), 'emails/9800000003@shop.test')), 'not their email');
  });

  test('any signed-in user looks up one email; nobody lists them', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'emails/9800000003@shop.test'), { uid: EMPLOYEE }));
    await assertSucceeds(getDoc(doc(db(OTHER_OWNER), 'emails/9800000003@shop.test')));
    await assertFails(getDoc(doc(db(null), 'emails/9800000003@shop.test')));
    await assertFails(getDocs(collection(db(OTHER_OWNER), 'emails')));
  });
});

describe('account deletion', () => {
  beforeEach(async () => {
    await seedBusiness();
    await seedOtherShop();
  });
  const gone = { name: 'Former staff', phone: '', email: '', active: false };
  const as = (uid, local) => env.authenticatedContext(uid, { email: `${local}@shop.test` }).firestore();

  test('staff anonymise and switch off their own profile, with exactly those changes', async () => {
    await assertFails(updateDoc(doc(db(EMPLOYEE), p(`users/${EMPLOYEE}`)), { ...gone, name: 'Someone' }));
    await assertFails(updateDoc(doc(db(EMPLOYEE), p(`users/${EMPLOYEE}`)), { ...gone, phone: '1' }));
    await assertFails(updateDoc(doc(db(EMPLOYEE), p(`users/${EMPLOYEE}`)), { ...gone, email: 'x@shop.test' }));
    await assertFails(updateDoc(doc(db(EMPLOYEE), p(`users/${EMPLOYEE}`)), { name: 'Former staff', phone: '' }), 'must switch off');
    await assertFails(updateDoc(doc(db(EMPLOYEE), p(`users/${EMPLOYEE}`)), { ...gone, role: 'owner' }));
    await assertFails(updateDoc(doc(db(EMPLOYEE), p(`users/${EMPLOYEE}`)), { ...gone, customPermissions: ['manageSettings'] }));
    await assertFails(updateDoc(doc(db(OWNER), p(`users/${OWNER}`)), gone), 'owners delete their shop instead');
    await assertFails(updateDoc(doc(db(EMPLOYEE), p(`users/${DELIVERY}`)), gone), 'not someone else');
    await assertFails(updateDoc(doc(db(EMPLOYEE), p(`users/${EMPLOYEE}`, OTHER_SHOP)), gone), 'no profile there');
    await assertSucceeds(updateDoc(doc(db(DELIVERY), p(`users/${DELIVERY}`)), gone));
    await assertSucceeds(updateDoc(doc(db(INACTIVE), p(`users/${INACTIVE}`)), gone), 'even when already switched off');
  });

  test('a login deletes only its own account and email docs', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'emails/9800000003@shop.test'), { uid: EMPLOYEE }));
    await assertFails(deleteDoc(doc(db(OWNER), `accounts/${EMPLOYEE}`)));
    await assertFails(deleteDoc(doc(as(OWNER, '9800000001'), 'emails/9800000003@shop.test')));
    await assertFails(deleteDoc(doc(db(EMPLOYEE), 'emails/9800000003@shop.test')), 'no email in the token');
    const d = as(EMPLOYEE, '9800000003');
    const batch = writeBatch(d);
    batch.update(doc(d, p(`users/${EMPLOYEE}`)), gone);
    batch.delete(doc(d, 'emails/9800000003@shop.test'));
    batch.delete(doc(d, `accounts/${EMPLOYEE}`));
    await assertSucceeds(batch.commit());
  });
});

describe('customer records and phone confirmation', () => {
  beforeEach(seedBusiness);

  const newCustomer = (extra = {}) => ({ name: 'N', phone: '1', location: '', creditLimit: 0, outstandingBalance: 0, openingBalance: 0, ...extra });

  test('sales staff add customers only without credit terms', async () => {
    await assertSucceeds(setDoc(doc(db(EMPLOYEE), p('customers/N1')), newCustomer()));
    await assertFails(setDoc(doc(db(EMPLOYEE), p('customers/N2')), newCustomer({ creditLimit: 50000 })));
    await assertFails(setDoc(doc(db(EMPLOYEE), p('customers/N3')), newCustomer({ openingBalance: 9000, outstandingBalance: 9000 })));
    await assertFails(setDoc(doc(db(DELIVERY), p('customers/N4')), newCustomer()));
  });

  test('staff can take orders for customers; delivery staff cannot', async () => {
    await assertSucceeds(setDoc(doc(db(EMPLOYEE), p('orders/P1')), { customerId: 'C2', status: 'placed', placedByStaffName: 'employee' }));
    await assertFails(setDoc(doc(db(EMPLOYEE), p('orders/P2')), { customerId: 'nope', status: 'placed', placedByStaffName: 'employee' }));
    await assertFails(setDoc(doc(db(DELIVERY), p('orders/P4')), { customerId: 'C1', status: 'placed', placedByStaffName: 'x' }));
  });

  test('phone confirmation: owner/cash staff only, never the collector, once', async () => {
    const confirm = (uid, at = 10) => updateDoc(doc(db(uid), p('customerPayments/PM2')), { phoneConfirmedAt: at, phoneConfirmedByName: 'x' });
    await assertFails(confirm(CASHIER), 'PM2 was collected by the cash staff');
    await assertFails(confirm(EMPLOYEE), 'no reconcileCash');
    await assertFails(confirm(DELIVERY));
    await assertSucceeds(confirm(OWNER));
    await assertFails(confirm(OWNER, 11), 'already confirmed');
    await assertFails(updateDoc(doc(db(OWNER), p('customerPayments/PM3')), { phoneConfirmedAt: 10, phoneConfirmedByName: 'x' }), 'signed payments need no call');
    await assertSucceeds(updateDoc(doc(db(CASHIER), p('customerPayments/PM1')), { disputedAt: 10, disputeNote: 'on call', disputedByName: 'acc (phone call)' }));
  });
});

describe('safeguards', () => {
  beforeEach(seedBusiness);

  const deliver = (d, { signed = true, settle = false } = {}) => {
    const batch = writeBatch(d);
    batch.set(doc(d, p('orders/O3')), { status: 'delivered', updatedDate: 2, ...(signed ? { receivedSignature: '1,1 2,2', receivedBy: 'x' } : {}) }, { merge: true });
    batch.set(doc(d, p('sales/INV1')), { status: 'completed', customerId: 'C1', orderId: 'O3', total: 5000, isCredit: true });
    batch.set(doc(d, p('customers/C1')), { outstandingBalance: increment(-2000), lastPaymentDate: 5 }, { merge: true });
    batch.set(doc(d, p('customerPayments/PM9')), payment({
      collectedById: DELIVERY, orderId: 'O3',
      ...(signed ? { signature: '1,1 2,2', signedName: 'x' } : { autoConfirmed: true }),
      ...(settle ? { settledAt: 5, settledAmount: 7000, settledById: DELIVERY, settledByName: 'd' } : {}),
    }));
    if (settle) batch.set(doc(d, p('cashLedger/L9')), { type: 'collection', amount: 7000, reference: 'PM9', account: 'cash' });
    return batch;
  };

  test('signature at the door: on, a delivery and its payment must be signed; off, not', async () => {
    await safeguards(['signature']);
    await assertFails(deliver(db(DELIVERY), { signed: false }).commit());
    const d = db(DELIVERY);
    const unsignedOrder = writeBatch(d);
    unsignedOrder.set(doc(d, p('orders/O3')), { status: 'delivered', updatedDate: 2 }, { merge: true });
    await assertFails(unsignedOrder.commit(), 'delivered on credit, unsigned');
    await safeguards([]);
    await assertSucceeds(deliver(db(DELIVERY), { signed: false }).commit());
  });

  test('phone check: on, unsigned payments cannot be recorded as confirmed; off, they can (and need no call)', async () => {
    const counter = (id) => setDoc(doc(db(EMPLOYEE), p(`customerPayments/${id}`)), payment({ autoConfirmed: true }));
    await assertFails(counter('PM10'));
    await assertSucceeds(setDoc(doc(db(EMPLOYEE), p('customerPayments/PM11')), payment()), 'unconfirmed is fine');
    await safeguards([]);
    await assertSucceeds(counter('PM12'));
    await assertFails(updateDoc(doc(db(OWNER), p('customerPayments/PM12')), { phoneConfirmedAt: 10, phoneConfirmedByName: 'x' }), 'already confirmed');
  });

  test('cash handover: on, collectors without reconcileCash never settle their own; off, everyone counts in their own at once', async () => {
    const ownSettle = { settledAt: 10, settledAmount: 7000, settledById: CASHIER, settledByName: 'x' };
    await safeguards(['signature', 'phoneConfirm', 'onlineOnly']);
    await assertSucceeds(deliver(db(DELIVERY), { settle: true }).commit());
    await assertSucceeds(updateDoc(doc(db(CASHIER), p('customerPayments/PM2')), ownSettle), 'no separation of duties');
    await assertFails(setDoc(doc(db(DELIVERY), p('cashLedger/L10')), { type: 'collection', amount: 7000, reference: 'PM9', account: 'cash' }), 'only alongside a new own settlement');
    await assertFails(setDoc(doc(db(DELIVERY), p('cashLedger/L11')), { type: 'expense', amount: 7000, reference: 'PM9', account: 'cash' }));
  });

  test('cash handover on: delivery staff cannot settle at collection or write the ledger', async () => {
    await assertFails(deliver(db(DELIVERY), { settle: true }).commit());
    await assertFails(updateDoc(doc(db(CASHIER), p('customerPayments/PM2')), { settledAt: 10, settledAmount: 7000, settledById: CASHIER, settledByName: 'x' }));
  });
});

describe('journal and accounting settings', () => {
  beforeEach(seedBusiness);
  const entry = (kind, extra = {}) => ({ date: Date.now(), kind, memo: 'x', reference: '', byName: 'x', lines: [{ account: 'cash', amount: 10 }, { account: 'sales', amount: -10 }], ...extra });

  test('staff book trading; owners\' money, adjustments and the year close are the owner\'s', async () => {
    await assertSucceeds(setDoc(doc(db(EMPLOYEE), p('journal/J1')), entry('sale')));
    await assertSucceeds(setDoc(doc(db(CASHIER), p('journal/J2')), entry('expense')));
    for (const kind of ['capital', 'drawing', 'loan', 'loanRepaid', 'dividend', 'manual', 'opening', 'close']) {
      await assertFails(setDoc(doc(db(CASHIER), p(`journal/K-${kind}`)), entry(kind)), kind);
      await assertSucceeds(setDoc(doc(db(OWNER), p(`journal/O-${kind}`)), entry(kind)), kind);
    }
    await assertFails(setDoc(doc(db(EMPLOYEE), p('journal/J1')), entry('sale', { memo: 'changed' })), 'append-only');
    await assertFails(updateDoc(doc(db(OWNER), p('journal/J1')), { memo: 'changed' }));
    await assertFails(setDoc(doc(db(INACTIVE), p('journal/J9')), entry('sale')));
  });

  test('delivery staff book only invoices and collections, and cannot read the journal', async () => {
    for (const kind of ['sale', 'payment', 'settlement']) await assertSucceeds(setDoc(doc(db(DELIVERY), p(`journal/D-${kind}`)), entry(kind)));
    await assertFails(setDoc(doc(db(DELIVERY), p('journal/D-x')), entry('expense')));
    await assertFails(getDoc(doc(db(DELIVERY), p('journal/D-sale'))));
  });

  test('nothing is dated into a closed year, and a closed year never reopens', async () => {
    await assertSucceeds(updateDoc(doc(db(OWNER), p('settings/business')), { safeguards: [], owners: [], closedThrough: null }), 'saving with no close date');
    await assertSucceeds(updateDoc(doc(db(OWNER), p('settings/business')), { closedThrough: 1000 }));
    await assertFails(setDoc(doc(db(OWNER), p('journal/old')), entry('manual', { date: 999 })));
    await assertSucceeds(setDoc(doc(db(OWNER), p('journal/new')), entry('manual', { date: 1001 })));
    await assertFails(updateDoc(doc(db(OWNER), p('settings/business')), { closedThrough: 500 }));
    await assertFails(updateDoc(doc(db(OWNER), p('settings/business')), { closedThrough: null }));
  });

  test('only the owner changes owners, accounts or VAT registration', async () => {
    await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), p(`users/${CASHIER}`)), { customPermissions: [...CASH_STAFF_PERMISSIONS, 'manageSettings'] }));
    await assertSucceeds(updateDoc(doc(db(CASHIER), p('settings/business')), { businessName: 'Renamed' }));
    for (const field of [{ owners: [{ name: 'Me', percent: 100 }] }, { moneyAccounts: ['bank:Mine'] }, { vatRegistered: true }, { panNumber: '1' }, { closedThrough: 5 }]) {
      await assertFails(updateDoc(doc(db(CASHIER), p('settings/business')), field), JSON.stringify(field));
    }
    await assertSucceeds(updateDoc(doc(db(OWNER), p('settings/business')), { owners: [{ name: 'Me', percent: 100 }], vatRegistered: true, panNumber: '1' }));
  });
});

describe('VAT bills', () => {
  beforeEach(async () => {
    await seedBusiness();
    await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), p('settings/business')), { vatRegistered: true }));
  });
  const sale = (extra = {}) => ({ status: 'completed', total: 113, items: [], ...extra });
  const billed = (d, id, seq, { counter = seq + 1, series = 'invoice-2083' } = {}) => {
    const batch = writeBatch(d);
    batch.set(doc(d, p(`sales/${id}`)), sale({ invoiceSeries: series, invoiceSeq: seq, invoiceNumber: `2083/84-${seq}` }));
    batch.set(doc(d, p(`counters/${series}`)), { next: counter }, { merge: true });
    return batch.commit();
  };

  test('tax invoices take the next number, in order, never twice', async () => {
    const d = db(EMPLOYEE);
    await assertFails(setDoc(doc(d, p('sales/X0')), sale()), 'unnumbered sale in a VAT shop');
    await assertFails(billed(d, 'X1', 2), 'must start at 1');
    await assertSucceeds(billed(d, 'X1', 1));
    await assertFails(billed(d, 'X2', 1, { counter: 2 }), 'number 1 is taken');
    await assertFails(billed(d, 'X2', 3), 'cannot skip 2');
    await assertFails(billed(d, 'X2', 2, { counter: 4 }), 'counter moves by one');
    await assertFails(billed(d, 'X2', 1, { series: 'other-2083' }), 'only the invoice series');
    await assertSucceeds(billed(db(CASHIER), 'X2', 2), 'the next number, from another device');
    await assertFails(setDoc(doc(d, p('counters/invoice-2083')), { next: 9 }, { merge: true }), 'counter alone cannot jump');
  });

  test('credit notes are numbered in their own series, by whoever may cancel sales', async () => {
    const note = (d, seq) => {
      const batch = writeBatch(d);
      batch.set(doc(d, p(`creditNotes/CN${seq}`)), { saleId: 'S1', number: `CN ${seq}`, series: 'credit-2083', seq, reason: 'x' });
      batch.set(doc(d, p('counters/credit-2083')), { next: seq + 1 }, { merge: true });
      return batch.commit();
    };
    await assertFails(note(db(EMPLOYEE), 1), 'employees cannot cancel sales');
    await assertSucceeds(note(db(OWNER), 1));
    await assertFails(note(db(OWNER), 1));
    await assertSucceeds(note(db(OWNER), 2));
  });

  test('a shop without VAT sells unnumbered', async () => {
    await env.withSecurityRulesDisabled((ctx) => updateDoc(doc(ctx.firestore(), p('settings/business')), { vatRegistered: false }));
    await assertSucceeds(setDoc(doc(db(EMPLOYEE), p('sales/X9')), sale()));
  });
});

describe('co-owners', () => {
  const CO = 'co-owner-uid';
  const CO2 = 'co-owner-2-uid';
  beforeEach(async () => {
    await seedBusiness();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), p(`users/${CO}`)), user('owner'));
      await setDoc(doc(ctx.firestore(), p(`users/${CO2}`)), user('owner'));
    });
  });

  test('co-owners have owner rights, but only the founder erases data', async () => {
    await assertSucceeds(setDoc(doc(db(CO), p('journal/cap')), { date: Date.now(), kind: 'capital', memo: 'x', lines: [{ account: 'cash', amount: 1 }, { account: 'capital:CO', amount: -1 }] }));
    await assertSucceeds(updateDoc(doc(db(CO), p('settings/business')), { safeguards: [] }));
    await assertFails(deleteDoc(doc(db(CO), p('products/P1'))), 'co-owner cannot wipe');
    await assertFails(deleteDoc(doc(db(CO), `shops/${SHOP}`)));
    await assertSucceeds(deleteDoc(doc(db(OWNER), p('products/P1'))));
  });

  test('only the founder adds or removes co-owners; a co-owner may leave', async () => {
    await assertFails(setDoc(doc(db(CO), p('users/new')), user('owner')), 'co-owner cannot add owners');
    await assertFails(setDoc(doc(db(CASHIER), p('users/new')), user('owner')));
    await assertSucceeds(setDoc(doc(db(OWNER), p('users/new')), user('owner')));
    await assertFails(updateDoc(doc(db(CO), p(`users/${CO2}`)), { active: false }), 'co-owners cannot remove each other');
    await assertFails(updateDoc(doc(db(CO), p(`users/${OWNER}`)), { active: false }));
    await assertSucceeds(updateDoc(doc(db(OWNER), p(`users/${CO2}`)), { active: false }));
    await assertSucceeds(updateDoc(doc(db(OWNER), p(`users/${CO2}`)), { active: true }));
    await assertFails(updateDoc(doc(db(OWNER), p(`users/${CO2}`)), { role: 'employee' }));
    await assertSucceeds(updateDoc(doc(db(CO), p(`users/${CO}`)), { active: false }), 'leaving');
    await assertFails(updateDoc(doc(db(CO), p(`users/${CO}`)), { active: true }), 'only the founder lets them back');
    await assertFails(updateDoc(doc(db(OWNER), p(`users/${OWNER}`)), { active: false }), 'the founder hands over instead of leaving');
  });

  test('the founder hands the role to an active co-owner, who then holds it alone', async () => {
    await assertFails(updateDoc(doc(db(CO), `shops/${SHOP}`), { ownerId: CO }));
    await assertFails(updateDoc(doc(db(OWNER), `shops/${SHOP}`), { ownerId: EMPLOYEE }), 'not an owner');
    await assertFails(updateDoc(doc(db(OWNER), `shops/${SHOP}`), { ownerId: CO, createdAt: 9 }));
    await assertSucceeds(updateDoc(doc(db(OWNER), `shops/${SHOP}`), { ownerId: CO }));
    await assertFails(deleteDoc(doc(db(OWNER), p('products/P1'))), 'old founder is now a co-owner');
    await assertSucceeds(deleteDoc(doc(db(CO), p('products/P1'))));
  });
});
