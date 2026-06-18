const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require('firebase/firestore');
const { getEnv, authed, seed, assertSucceeds, assertFails } = require('../helpers');

const openPost = (ownerId, extra = {}) => Object.assign({
  ownerId, ownerName: 'Owen', petIds: ['p1'], address: 'TLV',
  startDate: new Date(), endDate: new Date(), sittingType: 'הליכות',
  foodProvided: true, medication: false, payAmount: 50, payPer: 'hour',
  payTiming: 'perDay', interestedCount: 0, status: 'open',
}, extra);

// F-02 (IDOR), F-11 (counter abuse), F-18 (verified gate on create)
describe('posts', () => {
  let env;
  before(async () => { env = await getEnv(); });

  it('lets a verified owner create an open post with zero interest', async () => {
    const db = authed(env, 'owner1');
    await assertSucceeds(setDoc(doc(db, 'posts/post1'), openPost('owner1')));
  });

  it('blocks an UNVERIFIED user from creating a post (F-18 gate)', async () => {
    const db = authed(env, 'owner1', { verified: false });
    await assertFails(setDoc(doc(db, 'posts/post1'), openPost('owner1')));
  });

  it('blocks creating a post under someone else\'s ownerId', async () => {
    const db = authed(env, 'mallory');
    await assertFails(setDoc(doc(db, 'posts/post1'), openPost('owner1')));
  });

  it('blocks creating a post pre-seeded as approved / with fake interest', async () => {
    const db = authed(env, 'owner1');
    await assertFails(setDoc(doc(db, 'posts/post1'), openPost('owner1', { status: 'approved' })));
    await assertFails(setDoc(doc(db, 'posts/post2'), openPost('owner1', { interestedCount: 50 })));
  });

  it('lets the owner edit their own post', async () => {
    await seed(env, (db) => setDoc(doc(db, 'posts/post1'), openPost('owner1')));
    const db = authed(env, 'owner1');
    await assertSucceeds(updateDoc(doc(db, 'posts/post1'), { payAmount: 70, address: 'Haifa' }));
  });

  it('lets the owner approve their own post (open -> approved)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'posts/post1'), openPost('owner1')));
    const db = authed(env, 'owner1');
    await assertSucceeds(updateDoc(doc(db, 'posts/post1'), { status: 'approved', approvedSitterId: 'sitter1' }));
  });

  it('blocks a non-owner from editing, hijacking, or deleting a post (IDOR F-02)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'posts/post1'), openPost('owner1')));
    const db = authed(env, 'mallory');
    await assertFails(updateDoc(doc(db, 'posts/post1'), { payAmount: 1 }));
    await assertFails(updateDoc(doc(db, 'posts/post1'), { ownerId: 'mallory' }));
    await assertFails(updateDoc(doc(db, 'posts/post1'), { status: 'approved' }));
    await assertFails(deleteDoc(doc(db, 'posts/post1')));
  });

  it('lets a verified sitter bump interestedCount by exactly +1', async () => {
    await seed(env, (db) => setDoc(doc(db, 'posts/post1'), openPost('owner1', { interestedCount: 2 })));
    const db = authed(env, 'sitter1');
    await assertSucceeds(updateDoc(doc(db, 'posts/post1'), { interestedCount: 3 }));
  });

  it('blocks inflating interestedCount by more than 1 or touching other fields (F-11)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'posts/post1'), openPost('owner1', { interestedCount: 2 })));
    const db = authed(env, 'sitter1');
    await assertFails(updateDoc(doc(db, 'posts/post1'), { interestedCount: 1002 }));
    await assertFails(updateDoc(doc(db, 'posts/post1'), { interestedCount: 3, payAmount: 1 }));
  });

  it('blocks an unverified sitter from bumping interestedCount (F-18)', async () => {
    await seed(env, (db) => setDoc(doc(db, 'posts/post1'), openPost('owner1', { interestedCount: 2 })));
    const db = authed(env, 'sitter1', { verified: false });
    await assertFails(updateDoc(doc(db, 'posts/post1'), { interestedCount: 3 }));
  });

  describe('interested subcollection', () => {
    it('lets a verified sitter register their own interest doc', async () => {
      await seed(env, (db) => setDoc(doc(db, 'posts/post1'), openPost('owner1')));
      const db = authed(env, 'sitter1');
      await assertSucceeds(setDoc(doc(db, 'posts/post1/interested/sitter1'), { sitterId: 'sitter1', sitterName: 'Sam' }));
    });

    it('blocks registering interest under another sitter\'s id', async () => {
      await seed(env, (db) => setDoc(doc(db, 'posts/post1'), openPost('owner1')));
      const db = authed(env, 'sitter1');
      await assertFails(setDoc(doc(db, 'posts/post1/interested/sitter2'), { sitterId: 'sitter2', sitterName: 'Sam' }));
    });
  });
});
