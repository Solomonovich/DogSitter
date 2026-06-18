const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require('firebase/firestore');
const { getEnv, authed, unauthed, seed, assertSucceeds, assertFails } = require('../helpers');

// F-01: mass-assignment / privilege escalation on users/{uid}
describe('users', () => {
  let env;
  before(async () => { env = await getEnv(); });

  it('lets a user create their own profile (no reputation seeded)', async () => {
    const db = authed(env, 'u1');
    await assertSucceeds(setDoc(doc(db, 'users/u1'), {
      name: 'Dana', email: 'd@x.com', username: '@dana', role: 'sitter',
    }));
  });

  it('blocks creating a profile for another uid', async () => {
    const db = authed(env, 'u1');
    await assertFails(setDoc(doc(db, 'users/u2'), {
      name: 'Mallory', email: 'm@x.com', username: '@m', role: 'sitter',
    }));
  });

  it('blocks seeding reputation fields at create', async () => {
    const db = authed(env, 'u1');
    await assertFails(setDoc(doc(db, 'users/u1'), {
      name: 'Dana', email: 'd@x.com', username: '@dana', role: 'sitter',
      averageRating: 5.0, totalReviews: 999,
    }));
  });

  it('lets the owner edit allow-listed profile fields', async () => {
    await seed(env, (db) => setDoc(doc(db, 'users/u1'), {
      name: 'Dana', email: 'd@x.com', username: '@dana', role: 'sitter', averageRating: 4.2, totalReviews: 3,
    }));
    const db = authed(env, 'u1');
    await assertSucceeds(updateDoc(doc(db, 'users/u1'), { name: 'Dana B', phone: '050', address: 'TLV' }));
  });

  it('blocks self-promoting role (escalation)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'users/u1'), {
      name: 'Dana', email: 'd@x.com', username: '@dana', role: 'sitter',
    }));
    const db = authed(env, 'u1');
    await assertFails(updateDoc(doc(db, 'users/u1'), { role: 'owner' }));
  });

  it('blocks self-inflating rating / review count', async () => {
    await seed(env, (db) => setDoc(doc(db, 'users/u1'), {
      name: 'Dana', email: 'd@x.com', username: '@dana', role: 'sitter', averageRating: 3.0, totalReviews: 1,
    }));
    const db = authed(env, 'u1');
    await assertFails(updateDoc(doc(db, 'users/u1'), { averageRating: 5.0 }));
    await assertFails(updateDoc(doc(db, 'users/u1'), { totalReviews: 999 }));
  });

  it('allows the one-time needsRole -> sitter onboarding transition', async () => {
    await seed(env, (db) => setDoc(doc(db, 'users/u1'), {
      name: 'New', email: 'n@x.com', username: '@n', role: 'needsRole',
    }));
    const db = authed(env, 'u1');
    await assertSucceeds(setDoc(doc(db, 'users/u1'), {
      id: 'u1', name: 'New', email: 'n@x.com', username: '@n', role: 'owner', address: 'TLV',
    }));
  });

  it('blocks flipping owner <-> sitter after onboarding', async () => {
    await seed(env, (db) => setDoc(doc(db, 'users/u1'), {
      name: 'Dana', email: 'd@x.com', username: '@dana', role: 'sitter',
    }));
    const db = authed(env, 'u1');
    await assertFails(setDoc(doc(db, 'users/u1'), {
      name: 'Dana', email: 'd@x.com', username: '@dana', role: 'owner',
    }, { merge: false }));
  });

  it('lets any signed-in user read a profile, but blocks anonymous reads', async () => {
    await seed(env, (db) => setDoc(doc(db, 'users/u1'), {
      name: 'Dana', email: 'd@x.com', username: '@dana', role: 'sitter',
    }));
    await assertSucceeds(getDoc(doc(authed(env, 'someoneElse'), 'users/u1')));
    await assertFails(getDoc(doc(unauthed(env), 'users/u1')));
  });

  it('blocks client deletes of user docs', async () => {
    await seed(env, (db) => setDoc(doc(db, 'users/u1'), {
      name: 'Dana', email: 'd@x.com', username: '@dana', role: 'sitter',
    }));
    await assertFails(deleteDoc(doc(authed(env, 'u1'), 'users/u1')));
  });
});
