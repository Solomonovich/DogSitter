# DogSitter payments backend (Supabase)

Trusted payment compute (Edge Functions) + the authoritative ledger (Postgres).
App data stays in Firebase/Firestore; this backend reads it via the Firebase Admin
REST API and writes payment records back so the iOS app renders them through its
existing Firestore listeners. Money is integer **agorot** (1 ₪ = 100 agorot).

## Rails — "flip a switch"
`functions/_shared/provider.ts` is the only thing that moves money. `getProvider()`
selects the rail from the `PAYMENT_PROVIDER` secret:
- `stripe` — Stripe (cards, Apple Pay, off-session charges, refunds, webhooks). ✅ implemented.
- `grow`   — Grow by Meshulam (Israeli: cards + Bit, hosted page, IPN). 🚧 skeleton (Phase 3).
- `mock`   — sandbox; instant success, no real money. **Current default.**

Switching rails = change `PAYMENT_PROVIDER` only. Nothing else changes.

## Layout
- `migrations/0001_payments.sql` — base ledger.
- `migrations/0002_payments_overhaul.sql` — commission/VAT, dunning, real-card columns,
  `payment_customers`, `payouts`, `webhook_events`, `receipts`; updated `record_walk_charge`
  + new `settle_transaction` / `record_refund` / `record_payout` RPCs.
- `functions/_shared/` — `provider.ts` (+ `providers/{stripe,grow,mock}.ts`), `charge.ts`
  (the shared charge pipeline: card-on-file, dunning, receipts), `cards.ts`, `billing.ts`
  (fee split + VAT), `firestore.ts` (Admin REST), `firebaseAuth.ts` (+ `isAdmin`), `db.ts`, `cors.ts`.
- Functions: `charge-walk`, `charge-stay`, `payment-config`, `setup-card`, `finalize-card`,
  `payment-methods`, `get-balance`, `stripe-webhook`, `refund`, `record-payout`, `get-payouts`,
  `receipts`, `retry-charges`.

## Secrets
```
# Shared
supabase secrets set PAYMENT_PROVIDER=mock          # mock | stripe | grow
supabase secrets set PLATFORM_FEE_BPS=0             # e.g. 1000 = 10% commission
supabase secrets set VAT_RATE_BPS=0                 # Israel: 1800 = 18%
supabase secrets set VAT_INCLUSIVE=true
supabase secrets set ADMIN_UIDS=<firebase-uid>,...  # who may refund / record payouts
supabase secrets set CRON_SECRET=<random>           # protects retry-charges
supabase secrets set FIREBASE_PROJECT_ID=dogapp-ee349
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"

# Stripe (when PAYMENT_PROVIDER=stripe)
supabase secrets set STRIPE_SECRET_KEY=sk_test_...
supabase secrets set STRIPE_PUBLISHABLE_KEY=pk_test_...      # public; served to the app
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
supabase secrets set STRIPE_APPLE_PAY_MERCHANT_ID=merchant.com.shaqed.dogsitter   # optional

# Grow (when PAYMENT_PROVIDER=grow) — Phase 3
supabase secrets set GROW_USER_ID=... GROW_PAGE_CODE=... GROW_API_KEY=... \
  GROW_SECRET=... GROW_WEBHOOK_SECRET=... GROW_BASE_URL=https://sandbox.meshulam.co.il
```
`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

## Deploy (redeploy ALL — closes repo↔prod drift)
```
supabase link --project-ref szxldlkbxkepydjincgk
supabase db push                                    # applies migrations
for fn in charge-walk charge-stay payment-config setup-card finalize-card \
          payment-methods get-balance stripe-webhook refund record-payout \
          get-payouts receipts retry-charges; do
  supabase functions deploy "$fn" --no-verify-jwt
done
```
Then point Stripe's webhook at `https://szxldlkbxkepydjincgk.supabase.co/functions/v1/stripe-webhook`
(events: `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`,
`charge.dispute.created`, `setup_intent.succeeded`) and copy its signing secret into
`STRIPE_WEBHOOK_SECRET`.

The iOS app already has the functions base URL + anon key in
`Sources/Services/PaymentService.swift` → `PaymentConfig`. It learns the active rail +
Stripe publishable key from `GET /payment-config` at launch.

## Cron (dunning)
Schedule `retry-charges` (e.g. hourly) via pg_cron + pg_net, sending the `x-cron-secret`
header = `CRON_SECRET`. It re-attempts failed off-session charges with backoff and
escalates to `failed_final` after 4 tries.

## Go-live checklist
1. Stripe account in **test mode**; set Stripe secrets; `PAYMENT_PROVIDER=stripe`.
2. Set `PLATFORM_FEE_BPS` (commission) and `VAT_RATE_BPS=1800` once an accountant confirms
   the VAT treatment (platform commission vs. minor sitters).
3. Exercise the full flow (add card → approve booking → walk → charge → receipt → refund).
4. ⚠️ **Minor sitters**: payouts are manual via PayBox Young / Bit and need legal/parental-
   consent + tax review before real money moves. There is no automated KYC payout by design.
5. Switch Stripe to live keys.
```
curl -i -X POST https://<ref>.supabase.co/functions/v1/charge-walk \
  -H "apikey: <anon>" -H "x-firebase-token: <id-token>" \
  -H "content-type: application/json" -d '{"walkId":"<walkId>"}'
```
A second call with the same `walkId` must return `"idempotent": true`.
