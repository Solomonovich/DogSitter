const { doc, setDoc, updateDoc, deleteDoc } = require('firebase/firestore');
const { getEnv, authed, seed, assertSucceeds, assertFails } = require('../helpers');

const review = (extra = {}) => Object.assign({
  sitterId: 'sitter1', ownerId: 'owner1', ownerName: 'Owen', postId: 'post1', rating: 5, text: 'great',
}, extra);

// F-25: review/reputation forgery
describe('reviews', () => {
  let env;
  before(async () => { env = await getEnv(); });

  it('lets the author post a 1-5 review of someone else', async () => {
    const db = authed(env, 'owner1');
    await assertSucceeds(setDoc(doc(db, 'reviews/r1'), review({ rating: 4 })));
  });

  it('blocks out-of-range ratings', async () => {
    const db = authed(env, 'owner1');
    await assertFails(setDoc(doc(db, 'reviews/r1'), review({ rating: 6 })));
    await assertFails(setDoc(doc(db, 'reviews/r2'), review({ rating: 0 })));
  });

  it('blocks self-reviews (owner == sitter)', async () => {
    const db = authed(env, 'owner1');
    await assertFails(setDoc(doc(db, 'reviews/r1'), review({ sitterId: 'owner1' })));
  });

  it('blocks posting a review under someone else\'s authorship', async () => {
    const db = authed(env, 'mallory');
    await assertFails(setDoc(doc(db, 'reviews/r1'), review()));
  });

  it('blocks editing or deleting a review', async () => {
    await seed(env, (db) => setDoc(doc(db, 'reviews/r1'), review()));
    await assertFails(updateDoc(doc(authed(env, 'owner1'), 'reviews/r1'), { rating: 1 }));
    await assertFails(deleteDoc(doc(authed(env, 'owner1'), 'reviews/r1')));
  });
});
