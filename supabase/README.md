# DogSitter payments backend (Supabase)

Trusted payment compute (Edge Functions) + the authoritative ledger (Postgres).
App data stays in Firebase/Firestore; this backend reads it via the Firebase Admin
REST API and writes payment records back so the iOS app renders them through its
existing Firestore listeners.

> ⚠️ Runs on a **mock rail** — no real money moves. The only seam is
> `functions/_shared/provider.ts`. See the `payments-real-rail-deferred` memory.

## Layout
- `migrations/0001_payments.sql` — `transactions`, `payment_methods`, `balances`,
  `payment_events`, and the atomic `record_walk_charge()` function.
- `functions/charge-walk/` — charge one completed walk (idempotent on `walkId`).
- `functions/payment-methods/` — add/list a mock card.
- `functions/get-balance/` — caller's ledger totals.
- `functions/_shared/` — `firebaseAuth` (verify ID token), `firestore` (Admin REST),
  `provider` (the rail seam), `billing` (charge math), `db`, `cors`.

## One-time setup
1. Create the project (region `eu-central-1`, closest to Israel):
   `supabase projects create dogsitter-payments` (or via the dashboard / MCP).
2. Link & push the schema:
   ```
   supabase link --project-ref <ref>
   supabase db push                       # applies migrations/0001_payments.sql
   ```
3. Set secrets (the Firebase service-account JSON is the trust anchor — never ships
   in the app):
   ```
   supabase secrets set FIREBASE_PROJECT_ID=dogapp-ee349
   supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
   supabase secrets set PAYMENT_PROVIDER=mock
   ```
   (`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.)
4. Deploy the functions (no Supabase JWT gate — we verify the Firebase token
   ourselves):
   ```
   supabase functions deploy charge-walk --no-verify-jwt
   supabase functions deploy payment-methods --no-verify-jwt
   supabase functions deploy get-balance --no-verify-jwt
   ```
5. Put the functions base URL + anon key into the iOS app
   (`Sources/Services/PaymentService.swift` → `PaymentConfig`):
   - URL:  `https://<ref>.supabase.co/functions/v1`
   - anon key: from `supabase projects api-keys` (public; safe to ship).

## Local dev
```
supabase start
supabase db reset                         # apply schema to the local db
supabase functions serve --no-verify-jwt  # needs FIREBASE_* in supabase/.env
```
Call with a real Firebase ID token (grab one from a signed-in simulator):
```
curl -i -X POST http://localhost:54321/functions/v1/charge-walk \
  -H "apikey: <anon>" -H "x-firebase-token: <firebase-id-token>" \
  -H "content-type: application/json" -d '{"walkId":"<walkId>"}'
```
A second call with the same `walkId` must return `"idempotent": true` and not
double-charge.
