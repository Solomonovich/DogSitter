const { doc, getDoc, setDoc, updateDoc, collection, query, where, getDocs } = require('firebase/firestore');
const { getEnv, authed, seed, assertSucceeds, assertFails } = require('../helpers');

const chat = (extra = {}) => Object.assign({
  postId: 'post1', ownerId: 'owner1', sitterId: 'sitter1',
  ownerName: 'Owen', sitterName: 'Sam', approved: false, archived: false,
}, extra);

// F-03 (private chat IDOR), F-06 (forged approval)
describe('chats', () => {
  let env;
  before(async () => { env = await getEnv(); });

  it('lets participants read their chat; blocks a stranger (F-03)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'chats/c1'), chat()));
    await assertSucceeds(getDoc(doc(authed(env, 'owner1'), 'chats/c1')));
    await assertSucceeds(getDoc(doc(authed(env, 'sitter1'), 'chats/c1')));
    await assertFails(getDoc(doc(authed(env, 'stranger'), 'chats/c1')));
  });

  it('lets a user list their own chats, blocks a collection-wide dump', async () => {
    await seed(env, (db) => setDoc(doc(db, 'chats/c1'), chat()));
    const ownerScoped = query(collection(authed(env, 'owner1'), 'chats'), where('ownerId', '==', 'owner1'), where('archived', '==', false));
    await assertSucceeds(getDocs(ownerScoped));
    await assertFails(getDocs(collection(authed(env, 'stranger'), 'chats')));
  });

  it('lets a sitter create an unapproved chat; blocks pre-approved creation', async () => {
    await assertSucceeds(setDoc(doc(authed(env, 'sitter1'), 'chats/c1'), chat()));
    await assertFails(setDoc(doc(authed(env, 'sitter1'), 'chats/c2'), chat({ approved: true })));
  });

  it('lets the OWNER approve a chat; blocks a sitter self-approving (F-06)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'chats/c1'), chat()));
    await assertSucceeds(updateDoc(doc(authed(env, 'owner1'), 'chats/c1'), { approved: true }));
  });

  it('blocks a sitter from self-approving (F-06)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'chats/c1'), chat()));
    await assertFails(updateDoc(doc(authed(env, 'sitter1'), 'chats/c1'), { approved: true }));
  });

  it('lets participants update preview/archived fields', async () => {
    await seed(env, (db) => setDoc(doc(db, 'chats/c1'), chat()));
    await assertSucceeds(updateDoc(doc(authed(env, 'sitter1'), 'chats/c1'), { lastMessage: 'hi', archived: true }));
  });

  it('blocks tampering with participant ids', async () => {
    await seed(env, (db) => setDoc(doc(db, 'chats/c1'), chat()));
    await assertFails(updateDoc(doc(authed(env, 'owner1'), 'chats/c1'), { sitterId: 'mallory' }));
  });
});
