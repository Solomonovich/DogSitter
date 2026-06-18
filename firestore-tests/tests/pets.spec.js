const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require('firebase/firestore');
const { getEnv, authed, seed, assertSucceeds, assertFails } = require('../helpers');

// F-10: IDOR + mass-assignment on pets
describe('pets', () => {
  let env;
  before(async () => { env = await getEnv(); });

  it('lets an owner create a pet they own', async () => {
    const db = authed(env, 'owner1');
    await assertSucceeds(setDoc(doc(db, 'pets/p1'), { ownerId: 'owner1', name: 'Rex' }));
  });

  it('blocks creating a pet owned by someone else', async () => {
    const db = authed(env, 'mallory');
    await assertFails(setDoc(doc(db, 'pets/p1'), { ownerId: 'owner1', name: 'Rex' }));
  });

  it('blocks a non-owner from updating or deleting a pet', async () => {
    await seed(env, (db) => setDoc(doc(db, 'pets/p1'), { ownerId: 'owner1', name: 'Rex' }));
    const db = authed(env, 'mallory');
    await assertFails(updateDoc(doc(db, 'pets/p1'), { ownerId: 'mallory' }));
    await assertFails(deleteDoc(doc(db, 'pets/p1')));
  });

  it('lets the owner update their own pet but not reassign ownerId', async () => {
    await seed(env, (db) => setDoc(doc(db, 'pets/p1'), { ownerId: 'owner1', name: 'Rex' }));
    const db = authed(env, 'owner1');
    await assertSucceeds(updateDoc(doc(db, 'pets/p1'), { name: 'Rexy' }));
    await assertFails(updateDoc(doc(db, 'pets/p1'), { ownerId: 'someoneElse' }));
  });

  it('lets any signed-in user read pets (needed to show pets in chat/posts)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'pets/p1'), { ownerId: 'owner1', name: 'Rex' }));
    await assertSucceeds(getDoc(doc(authed(env, 'sitter1'), 'pets/p1')));
  });
});
