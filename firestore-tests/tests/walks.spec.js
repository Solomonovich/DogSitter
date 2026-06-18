const { doc, getDoc, setDoc, updateDoc, collection, query, where, getDocs } = require('firebase/firestore');
const { getEnv, authed, seed, assertSucceeds, assertFails } = require('../helpers');

const walk = (extra = {}) => Object.assign({
  chatId: 'chat1', postId: 'post1', sitterId: 'sitter1', ownerId: 'owner1',
  status: 'active', startTime: new Date(), distance: 0, duration: 0,
  startAddress: 'TLV', coordinates: [], photoURLs: [], messageId: 'm1',
}, extra);

// F-04 (walk tampering), F-14 (live GPS read leak)
describe('walks', () => {
  let env;
  before(async () => { env = await getEnv(); });

  it('lets either participant read a walk (live map still works)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'walks/w1'), walk()));
    await assertSucceeds(getDoc(doc(authed(env, 'owner1'), 'walks/w1')));
    await assertSucceeds(getDoc(doc(authed(env, 'sitter1'), 'walks/w1')));
  });

  it('blocks a stranger from reading a walk (F-14 live-GPS leak)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'walks/w1'), walk()));
    await assertFails(getDoc(doc(authed(env, 'stranger'), 'walks/w1')));
  });

  it('lets a participant run the chat-scoped hours query, blocks a bulk dump', async () => {
    await seed(env, async (db) => {
      await setDoc(doc(db, 'walks/w1'), walk({ status: 'completed', duration: 30 }));
      await setDoc(doc(db, 'walks/w2'), walk({ status: 'completed', duration: 45 }));
    });
    const ownerDb = authed(env, 'owner1');
    // The client scopes the hours query by the caller's own id (ownerId for an owner,
    // sitterId for a sitter) so the participant rule is provable for a LIST query.
    const scoped = query(collection(ownerDb, 'walks'),
      where('ownerId', '==', 'owner1'), where('chatId', '==', 'chat1'), where('status', '==', 'completed'));
    await assertSucceeds(getDocs(scoped));
    // A stranger cannot read the same chat's walks, and nobody can dump the whole collection.
    const strangerScoped = query(collection(authed(env, 'stranger'), 'walks'), where('chatId', '==', 'chat1'));
    await assertFails(getDocs(strangerScoped));
    await assertFails(getDocs(collection(authed(env, 'owner1'), 'walks')));
  });

  it('lets a verified sitter start a walk; blocks owner / unverified', async () => {
    await assertSucceeds(setDoc(doc(authed(env, 'sitter1'), 'walks/w1'), walk()));
    await assertFails(setDoc(doc(authed(env, 'owner1'), 'walks/w2'), walk()));
    await assertFails(setDoc(doc(authed(env, 'sitter1', { verified: false }), 'walks/w3'), walk()));
  });

  it('lets the assigned sitter update an active walk; blocks the owner', async () => {
    await seed(env, (db) => setDoc(doc(db, 'walks/w1'), walk()));
    await assertSucceeds(updateDoc(doc(authed(env, 'sitter1'), 'walks/w1'), { distance: 2.4, duration: 30 }));
    await assertFails(updateDoc(doc(authed(env, 'owner1'), 'walks/w1'), { duration: 9999 }));
  });

  it('freezes a completed walk against further edits (F-04)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'walks/w1'), walk({ status: 'completed' })));
    await assertFails(updateDoc(doc(authed(env, 'sitter1'), 'walks/w1'), { duration: 9999 }));
  });

  it('blocks reassigning the sitter/owner of a walk', async () => {
    await seed(env, (db) => setDoc(doc(db, 'walks/w1'), walk()));
    await assertFails(updateDoc(doc(authed(env, 'sitter1'), 'walks/w1'), { sitterId: 'mallory' }));
  });
});
