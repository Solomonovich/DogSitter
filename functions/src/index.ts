// DogSitter Cloud Functions — DRAFT (requires the Firebase Blaze plan).
// These functions close the findings that Firestore Security Rules alone cannot:
// signed Cloudinary uploads, server-trusted payment/approval, reputation
// aggregation, and approved-only contact-info vending. They are NOT wired into
// the client yet and are NOT deployed.
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';
import { signParams } from './cloudinarySignature';

admin.initializeApp();
const db = admin.firestore();

// F-13 / F-16: vend a short-lived *signed* Cloudinary upload signature to an
// authenticated user, replacing the unsigned upload_preset embedded in the app.
// Configure CLOUDINARY_API_KEY / CLOUDINARY_API_SECRET as function secrets.
export const signCloudinaryUpload = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');

  const apiKey = process.env.CLOUDINARY_API_KEY;
  const apiSecret = process.env.CLOUDINARY_API_SECRET;
  if (!apiKey || !apiSecret) {
    throw new HttpsError('failed-precondition', 'Cloudinary signing is not configured.');
  }

  const folder = String(request.data?.folder ?? '');
  const publicId = String(request.data?.publicId ?? '');
  const timestamp = Math.floor(Date.now() / 1000);

  const signature = signParams({ folder, public_id: publicId, timestamp }, apiSecret);
  return { signature, timestamp, apiKey, folder, publicId };
});

// F-06: server-trusted booking approval + payment confirmation. Replaces the
// client-side approveChat path so a sitter can never self-approve or forge the
// "payment passed" banner. TODO: gate on a real payment capture/webhook.
export const approveBooking = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const chatId = String(request.data?.chatId ?? '');
  const postId = String(request.data?.postId ?? '');
  if (!chatId || !postId) throw new HttpsError('invalid-argument', 'chatId and postId are required.');

  const [chatSnap, postSnap] = await Promise.all([
    db.doc(`chats/${chatId}`).get(),
    db.doc(`posts/${postId}`).get(),
  ]);
  if (!postSnap.exists || postSnap.get('ownerId') !== uid) {
    throw new HttpsError('permission-denied', 'Only the post owner may approve.');
  }

  const sitterId = (chatSnap.get('sitterId') as string) ?? '';
  // TODO: verify payment was captured before flipping to approved.
  await db.doc(`chats/${chatId}`).update({ approved: true });
  await db.doc(`posts/${postId}`).update({ status: 'approved', approvedSitterId: sitterId });
  await db.collection(`chats/${chatId}/messages`).add({
    senderId: 'system',
    senderName: 'System',
    text: 'התשלום עבר בהצלחה ✓',
    type: 'payment',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

// F-01 / F-25: recompute sitter reputation from reviews. Clients are blocked from
// writing averageRating/totalReviews by the rules; only this trusted path may.
export const onReviewWrite = onDocumentWritten('reviews/{reviewId}', async (event) => {
  const after = event.data?.after?.data();
  const before = event.data?.before?.data();
  const sitterId = (after?.sitterId ?? before?.sitterId) as string | undefined;
  if (!sitterId) return;

  const snap = await db.collection('reviews').where('sitterId', '==', sitterId).get();
  let total = 0;
  let sum = 0;
  snap.forEach((d) => {
    const r = d.get('rating');
    if (typeof r === 'number') {
      total += 1;
      sum += r;
    }
  });
  const averageRating = total ? sum / total : 0;
  await db.doc(`users/${sitterId}`).set({ averageRating, totalReviews: total }, { merge: true });
});

// F-09 / F-12: release a counterpart's phone/address ONLY when an approved booking
// exists between the two users. Pairs with splitting contact fields out of the
// publicly-readable user document (future client change).
export const getContactInfo = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const otherUid = String(request.data?.userId ?? '');
  if (!otherUid) throw new HttpsError('invalid-argument', 'userId is required.');

  const [asOwner, asSitter] = await Promise.all([
    db.collection('chats').where('ownerId', '==', uid).where('sitterId', '==', otherUid).where('approved', '==', true).limit(1).get(),
    db.collection('chats').where('ownerId', '==', otherUid).where('sitterId', '==', uid).where('approved', '==', true).limit(1).get(),
  ]);
  if (asOwner.empty && asSitter.empty) {
    throw new HttpsError('permission-denied', 'No approved booking with this user.');
  }

  const userSnap = await db.doc(`users/${otherUid}`).get();
  return { phone: userSnap.get('phone') ?? null, address: userSnap.get('address') ?? null };
});
