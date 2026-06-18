const { doc, getDoc, setDoc, addDoc, collection, deleteDoc } = require('firebase/firestore');
const { getEnv, authed, seed, assertSucceeds, assertFails } = require('../helpers');

// F-22: abuse reports + per-user block lists
describe('reports', () => {
  let env;
  before(async () => { env = await getEnv(); });

  it('lets a user file a report as themselves', async () => {
    const db = authed(env, 'me');
    await assertSucceeds(addDoc(collection(db, 'reports'), { reporterId: 'me', reportedId: 'them', reason: 'spam' }));
  });

  it('blocks filing a report under someone else\'s reporterId', async () => {
    const db = authed(env, 'me');
    await assertFails(addDoc(collection(db, 'reports'), { reporterId: 'someoneElse', reportedId: 'them' }));
  });

  it('blocks reading reports from the client', async () => {
    await seed(env, (db) => setDoc(doc(db, 'reports/r1'), { reporterId: 'me', reportedId: 'them' }));
    await assertFails(getDoc(doc(authed(env, 'me'), 'reports/r1')));
  });
});

describe('block list', () => {
  let env;
  before(async () => { env = await getEnv(); });

  it('lets a user manage their own block list', async () => {
    const db = authed(env, 'me');
    await assertSucceeds(setDoc(doc(db, 'users/me/blocked/them'), { createdAt: new Date() }));
    await assertSucceeds(getDoc(doc(db, 'users/me/blocked/them')));
    await assertSucceeds(deleteDoc(doc(db, 'users/me/blocked/them')));
  });

  it('blocks writing to another user\'s block list', async () => {
    const db = authed(env, 'mallory');
    await assertFails(setDoc(doc(db, 'users/victim/blocked/x'), { createdAt: new Date() }));
  });

  it('blocks reading another user\'s block list', async () => {
    await seed(env, (db) => setDoc(doc(db, 'users/victim/blocked/x'), { createdAt: new Date() }));
    await assertFails(getDoc(doc(authed(env, 'mallory'), 'users/victim/blocked/x')));
  });
});
