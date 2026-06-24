const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require('firebase/firestore');
const { getEnv, authed, seed, assertSucceeds, assertFails } = require('../helpers');

// The `payments` collection mirrors the Supabase ledger into Firestore so the app
// can render charges through its existing listeners. It is written ONLY by the
// trusted backend (Admin SDK, bypasses rules). Clients may read their own; never write.
const payment = {
  walkId: 'w1', chatId: 'c1', postId: 'p1',
  ownerId: 'owner1', sitterId: 'sitter1',
  amountAgorot: 15000, currency: 'ILS', status: 'succeeded', provider: 'mock', text: 'paid',
};
const seedPayment = (env) => seed(env, (db) => setDoc(doc(db, 'payments/pay1'), payment));

describe('payments (backend-only ledger mirror)', () => {
  let env;
  before(async () => { env = await getEnv(); });
  beforeEach(async () => { await seedPayment(env); });

  it('lets the owner read their own payment', async () => {
    await assertSucceeds(getDoc(doc(authed(env, 'owner1'), 'payments/pay1')));
  });

  it('lets the sitter read their own payment', async () => {
    await assertSucceeds(getDoc(doc(authed(env, 'sitter1'), 'payments/pay1')));
  });

  it('blocks a stranger from reading a payment', async () => {
    await assertFails(getDoc(doc(authed(env, 'stranger'), 'payments/pay1')));
  });

  it('blocks any client from creating a payment (backend-only)', async () => {
    await assertFails(setDoc(doc(authed(env, 'owner1'), 'payments/pay2'), payment));
    await assertFails(setDoc(doc(authed(env, 'sitter1'), 'payments/pay2'), payment));
  });

  it('blocks updating a payment (e.g. tampering with the amount)', async () => {
    await assertFails(updateDoc(doc(authed(env, 'owner1'), 'payments/pay1'), { amountAgorot: 1 }));
  });

  it('blocks deleting a payment', async () => {
    await assertFails(deleteDoc(doc(authed(env, 'owner1'), 'payments/pay1')));
  });
});
