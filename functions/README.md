# DogSitter Cloud Functions — DRAFT

> 🚧 **This directory is a scaffold and is NOT deployed.** Cloud Functions require the
> Firebase **Blaze** (pay-as-you-go) plan. Adopt it only after deciding on Blaze.

These functions close the findings that Firestore Security Rules alone cannot enforce.
The rules (see `../firestore.rules`) already block the client from doing the unsafe
thing; these functions provide the trusted path to do the *safe* thing.

| Function | Finding | What it does |
|----------|---------|--------------|
| `signCloudinaryUpload` | F-13, F-16 | Vends a short-lived **signed** Cloudinary upload signature to an authenticated user, replacing the unsigned `upload_preset` embedded in the app. |
| `approveBooking` | F-06 | Server-trusted booking approval + payment-confirmation message. A sitter can no longer self-approve or forge the "payment passed" banner. *(TODO: integrate a real payment capture/webhook.)* |
| `onReviewWrite` | F-01, F-25 | Recomputes `averageRating` / `totalReviews` from `reviews`. Clients are blocked from writing reputation by the rules; only this path may. |
| `getContactInfo` | F-09, F-12 | Releases a counterpart's `phone`/`address` only when an **approved** booking exists between the two users. Pairs with moving contact fields out of the publicly-readable user document. |

Still TODO (tracked for when Blaze is adopted): per-user message **rate limiting** (F-22)
and enabling **App Check enforcement** for Firestore/Auth/Storage (F-17).

## Configuration

```sh
# Cloudinary signing secrets (never commit these):
firebase functions:secrets:set CLOUDINARY_API_KEY
firebase functions:secrets:set CLOUDINARY_API_SECRET
```

## Develop / test

```sh
cd functions
npm test            # pure unit tests (node --test, no install needed) — signature logic
npm ci && npm run build     # type-check / compile (needs Blaze deps installed)
npm run serve       # run in the Functions emulator (needs the Firebase CLI)
```

The signature algorithm is unit-tested in `test/cloudinarySignature.test.js` and runs in CI.
Full emulator-based function tests come with the Blaze adoption.

## Client wiring (future)

- Replace `CloudinaryHelper`'s unsigned upload with: call `signCloudinaryUpload`,
  then POST to Cloudinary with `{ api_key, timestamp, signature, folder, public_id }`.
- Replace `AppState.approveChat` with a call to `approveBooking`.
- Replace the chat profile's direct `users/{id}` read of `phone`/`address` with
  `getContactInfo`, and tighten the `users` read rule once contact fields are split out.
