const { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, getDocs } = require('firebase/firestore');
const { getEnv, authed, seed, assertSucceeds, assertFails } = require('../helpers');

const chat = { postId: 'post1', ownerId: 'owner1', sitterId: 'sitter1', ownerName: 'Owen', sitterName: 'Sam', approved: false, archived: false };
const seedChat = (env) => seed(env, (db) => setDoc(doc(db, 'chats/c1'), chat));

// F-07 (sender spoof), F-06 (forged payment banner), F-03 (read), F-08 (delete own)
describe('chat messages', () => {
  let env;
  before(async () => { env = await getEnv(); });
  beforeEach(async () => { await seedChat(env); });

  it('lets a participant send a message with their own senderId', async () => {
    const db = authed(env, 'sitter1');
    await assertSucceeds(setDoc(doc(db, 'chats/c1/messages/m1'), { senderId: 'sitter1', senderName: 'Sam', text: 'hi', type: 'text' }));
  });

  it('blocks spoofing senderId (impersonation, F-07)', async () => {
    const db = authed(env, 'sitter1');
    await assertFails(setDoc(doc(db, 'chats/c1/messages/m1'), { senderId: 'owner1', senderName: 'Owen', text: 'fake', type: 'text' }));
  });

  it('blocks a non-participant from sending into the chat (F-03)', async () => {
    const db = authed(env, 'stranger');
    await assertFails(setDoc(doc(db, 'chats/c1/messages/m1'), { senderId: 'stranger', senderName: 'X', text: 'hi', type: 'text' }));
  });

  it('blocks even the OWNER from writing a "payment" banner (backend-only now, F-06 resolved)', async () => {
    const db = authed(env, 'owner1');
    await assertFails(setDoc(doc(db, 'chats/c1/messages/m1'), { senderId: 'owner1', senderName: 'Owen', text: 'paid ✓', type: 'payment' }));
  });

  it('blocks a sitter forging a "payment" banner (F-06)', async () => {
    const db = authed(env, 'sitter1');
    await assertFails(setDoc(doc(db, 'chats/c1/messages/m1'), { senderId: 'sitter1', senderName: 'Sam', text: 'paid ✓', type: 'payment' }));
  });

  it('blocks the legacy "system" sender (cannot equal auth.uid)', async () => {
    const db = authed(env, 'owner1');
    await assertFails(setDoc(doc(db, 'chats/c1/messages/m1'), { senderId: 'system', senderName: 'System', text: 'paid ✓', type: 'payment' }));
  });

  it('lets participants read messages, blocks strangers (F-03)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'chats/c1/messages/m1'), { senderId: 'sitter1', senderName: 'Sam', text: 'hi', type: 'text' }));
    await assertSucceeds(getDocs(collection(authed(env, 'owner1'), 'chats/c1/messages')));
    await assertFails(getDocs(collection(authed(env, 'stranger'), 'chats/c1/messages')));
  });

  it('lets a user delete only their own message (F-08)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'chats/c1/messages/m1'), { senderId: 'sitter1', senderName: 'Sam', text: 'hi', type: 'text' }));
    await assertFails(deleteDoc(doc(authed(env, 'owner1'), 'chats/c1/messages/m1')));
    await assertSucceeds(deleteDoc(doc(authed(env, 'sitter1'), 'chats/c1/messages/m1')));
  });

  it('blocks editing a message after the fact', async () => {
    await seed(env, (db) => setDoc(doc(db, 'chats/c1/messages/m1'), { senderId: 'sitter1', senderName: 'Sam', text: 'hi', type: 'text' }));
    await assertFails(updateDoc(doc(authed(env, 'sitter1'), 'chats/c1/messages/m1'), { text: 'edited' }));
  });
});
