-- DogSitter payments overhaul: real rails (Stripe / Grow), platform commission,
-- Israeli VAT, refunds, manual sitter payouts, and webhook idempotency.
--
-- Money stays integer agorot (1 ILS = 100 agorot). Firestore remains the app's
-- source of truth; this schema stays the authoritative payment ledger. Everything
-- here is additive over 0001_payments.sql and safe to apply with zero behavior
-- change until PLATFORM_FEE_BPS / VAT_RATE_BPS are set and a real PAYMENT_PROVIDER
-- is selected.

-- ============================================================ transactions ===
-- A transaction now models both charges and refunds. `kind` distinguishes them;
-- `sitter_accrued_agorot` is the NET that accrues to the sitter (amount − fee).
alter table public.transactions
  add column if not exists kind                   text    not null default 'charge'
    check (kind in ('charge', 'refund')),
  add column if not exists platform_fee_agorot    integer not null default 0
    check (platform_fee_agorot >= 0),
  add column if not exists sitter_accrued_agorot   integer not null default 0,
  add column if not exists vat_agorot             integer not null default 0
    check (vat_agorot >= 0),
  add column if not exists vat_rate_bps           integer not null default 0,
  add column if not exists parent_transaction_id  uuid    references public.transactions(id),
  add column if not exists customer_ref           text,
  add column if not exists provider_payment_method text,
  -- Dunning / retry state for failed off-session charges.
  add column if not exists retry_count            integer not null default 0,
  add column if not exists next_retry_at          timestamptz,
  add column if not exists last_failure_reason    text,
  add column if not exists dunning_state          text    not null default 'none'
    check (dunning_state in ('none', 'retrying', 'failed_final'));

-- Idempotency: the old UNIQUE(walk_id) blocked refund rows (which reuse walk_id).
-- Replace it with a PARTIAL unique index so only CHARGE rows are unique per walk;
-- refund rows share the walk_id but carry kind='refund'.
alter table public.transactions drop constraint if exists transactions_walk_id_key;
create unique index if not exists transactions_walk_charge_uniq
  on public.transactions (walk_id) where kind = 'charge';

create index if not exists transactions_parent_idx
  on public.transactions (parent_transaction_id) where parent_transaction_id is not null;
create index if not exists transactions_dunning_idx
  on public.transactions (next_retry_at) where dunning_state = 'retrying';

-- ========================================================= payment_methods ===
-- Real saved cards: a provider token + the provider's customer id, brand/last4,
-- expiry, and a soft-delete marker (the charge path filters deleted_at is null).
alter table public.payment_methods
  add column if not exists provider    text not null default 'mock',
  add column if not exists customer_id text,
  add column if not exists exp_month   integer,
  add column if not exists exp_year    integer,
  add column if not exists deleted_at  timestamptz;

create index if not exists payment_methods_active_idx
  on public.payment_methods (user_id) where deleted_at is null;

-- ========================================================= payment_customers ===
-- Owner -> provider customer id mapping (one per provider). Lets us reuse a
-- Stripe/Grow customer across charges and saved cards.
create table if not exists public.payment_customers (
  user_id     text not null,
  provider    text not null,
  customer_id text not null,
  created_at  timestamptz not null default now(),
  primary key (user_id, provider)
);

-- =================================================================== payouts ===
-- Manual/admin sitter payouts. Earnings ACCRUE in balances; an admin records a
-- payout here when money is disbursed offline (PayBox Young / Bit). No KYC, no
-- automated transfer — most sitters are minors.
create table if not exists public.payouts (
  id            uuid primary key default gen_random_uuid(),
  sitter_id     text not null,
  amount_agorot bigint not null check (amount_agorot > 0),
  status        text not null default 'paid'
                  check (status in ('pending', 'paid', 'cancelled')),
  method        text not null default 'manual'
                  check (method in ('paybox', 'bit', 'manual')),
  reference     text,                -- e.g. a PayBox/Bit transfer reference
  note          text,
  created_by    text not null,       -- admin uid that recorded it
  created_at    timestamptz not null default now(),
  paid_at       timestamptz
);
create index if not exists payouts_sitter_idx on public.payouts (sitter_id);

-- ============================================================ webhook_events ===
-- Webhook idempotency log. (provider, event_id) unique => a re-delivered event
-- is a no-op.
create table if not exists public.webhook_events (
  id           uuid primary key default gen_random_uuid(),
  provider     text not null,
  event_id     text not null,
  type         text,
  payload      jsonb,
  processed_at timestamptz not null default now(),
  unique (provider, event_id)
);

-- ================================================================== receipts ===
-- Israeli receipt/invoice records with VAT breakdown. `number` is a stable,
-- sequential id (gapless-ish; accountant validates). provider_invoice_id holds
-- Grow's native invoice id when issued.
create sequence if not exists public.receipt_seq;
create table if not exists public.receipts (
  id                  uuid primary key default gen_random_uuid(),
  transaction_id      uuid not null references public.transactions(id),
  number              text not null unique
                        default lpad(nextval('public.receipt_seq')::text, 8, '0'),
  net_agorot          integer not null default 0,
  vat_agorot          integer not null default 0,
  gross_agorot        integer not null default 0,
  vat_rate_bps        integer not null default 0,
  owner_id            text,
  sitter_id           text,
  provider_invoice_id text,
  pdf_url             text,
  issued_at           timestamptz not null default now()
);
create index if not exists receipts_tx_idx on public.receipts (transaction_id);

-- ================================================================== balances ===
-- Track lifetime payouts (so "available to pay out" = sitter_accrued − paid_out)
-- and lifetime refunds to the owner.
alter table public.balances
  add column if not exists sitter_paid_out_agorot bigint not null default 0,
  add column if not exists owner_refunded_agorot  bigint not null default 0;

-- ====================================================== record_walk_charge() ===
-- Replace the 0001 version (10 args) with one that records the commission split
-- and VAT, and accrues the sitter's NET earnings. Must DROP the old signature
-- first (different arg list), then re-REVOKE/GRANT.
drop function if exists public.record_walk_charge(
  text, text, text, text, text, integer, text, text, text, date
);

create or replace function public.record_walk_charge(
  p_walk_id               text,
  p_chat_id               text,
  p_post_id               text,
  p_owner_id              text,
  p_sitter_id             text,
  p_amount_agorot         integer,
  p_currency              text,
  p_provider              text,
  p_provider_ref          text,
  p_service_day           date,
  p_platform_fee_agorot   integer default 0,
  p_sitter_accrued_agorot integer default null,   -- defaults to amount − fee
  p_vat_agorot            integer default 0,
  p_vat_rate_bps          integer default 0,
  p_customer_ref          text    default null,
  p_provider_payment_method text  default null
) returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx  public.transactions;
  v_net integer := coalesce(p_sitter_accrued_agorot, p_amount_agorot - p_platform_fee_agorot);
begin
  insert into public.transactions (
    walk_id, chat_id, post_id, owner_id, sitter_id, amount_agorot,
    currency, status, kind, provider, provider_ref, service_day, captured_at,
    platform_fee_agorot, sitter_accrued_agorot, vat_agorot, vat_rate_bps,
    customer_ref, provider_payment_method
  ) values (
    p_walk_id, p_chat_id, p_post_id, p_owner_id, p_sitter_id, p_amount_agorot,
    p_currency, 'succeeded', 'charge', p_provider, p_provider_ref, p_service_day, now(),
    p_platform_fee_agorot, v_net, p_vat_agorot, p_vat_rate_bps,
    p_customer_ref, p_provider_payment_method
  )
  returning * into v_tx;

  -- Owner is charged the gross; the sitter accrues the NET (gross − commission).
  insert into public.balances (user_id, owner_charged_agorot, sitter_accrued_agorot, currency)
    values (p_owner_id, p_amount_agorot, 0, p_currency)
    on conflict (user_id) do update
      set owner_charged_agorot = public.balances.owner_charged_agorot + excluded.owner_charged_agorot,
          updated_at = now();

  insert into public.balances (user_id, owner_charged_agorot, sitter_accrued_agorot, currency)
    values (p_sitter_id, 0, v_net, p_currency)
    on conflict (user_id) do update
      set sitter_accrued_agorot = public.balances.sitter_accrued_agorot + excluded.sitter_accrued_agorot,
          updated_at = now();

  return v_tx;
end;
$$;

-- ======================================================= settle_transaction() ===
-- Idempotently flip a pending transaction to succeeded/failed and accrue the
-- ledger ONLY on the transition INTO 'succeeded'. This is the convergence point
-- between a synchronous charge result and an async provider webhook for the same
-- charge: whichever lands first accrues; the second is a no-op.
create or replace function public.settle_transaction(
  p_walk_id      text,
  p_status       text,          -- 'succeeded' | 'failed'
  p_provider_ref text default null,
  p_failure_reason text default null
) returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx public.transactions;
begin
  select * into v_tx
    from public.transactions
   where walk_id = p_walk_id and kind = 'charge'
   for update;

  if not found then
    return null;
  end if;

  -- Already settled into this state? No-op (idempotent).
  if v_tx.status = p_status then
    return v_tx;
  end if;

  if p_status = 'succeeded' and v_tx.status <> 'succeeded' then
    update public.transactions
       set status = 'succeeded',
           provider_ref = coalesce(p_provider_ref, provider_ref),
           captured_at = now(),
           dunning_state = 'none'
     where id = v_tx.id
     returning * into v_tx;

    insert into public.balances (user_id, owner_charged_agorot, sitter_accrued_agorot, currency)
      values (v_tx.owner_id, v_tx.amount_agorot, 0, v_tx.currency)
      on conflict (user_id) do update
        set owner_charged_agorot = public.balances.owner_charged_agorot + excluded.owner_charged_agorot,
            updated_at = now();

    insert into public.balances (user_id, owner_charged_agorot, sitter_accrued_agorot, currency)
      values (v_tx.sitter_id, 0, v_tx.sitter_accrued_agorot, v_tx.currency)
      on conflict (user_id) do update
        set sitter_accrued_agorot = public.balances.sitter_accrued_agorot + excluded.sitter_accrued_agorot,
            updated_at = now();

  elsif p_status = 'failed' then
    update public.transactions
       set status = 'failed',
           last_failure_reason = coalesce(p_failure_reason, last_failure_reason)
     where id = v_tx.id
     returning * into v_tx;
  end if;

  return v_tx;
end;
$$;

-- ============================================================ record_refund() ===
-- Record a (full or partial) refund against a parent charge: insert a kind='refund'
-- row, reverse the sitter's NET proportionally, track the owner's refund total,
-- and mark the parent refunded.
create or replace function public.record_refund(
  p_parent_tx_id  uuid,
  p_amount_agorot integer,
  p_provider      text,
  p_provider_ref  text
) returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent public.transactions;
  v_refund public.transactions;
  v_sitter_reversal integer;
begin
  select * into v_parent from public.transactions where id = p_parent_tx_id for update;
  if not found then
    raise exception 'parent transaction % not found', p_parent_tx_id;
  end if;

  -- Reverse the sitter's net in proportion to the fraction refunded.
  v_sitter_reversal := case
    when v_parent.amount_agorot > 0
      then round(p_amount_agorot::numeric * v_parent.sitter_accrued_agorot / v_parent.amount_agorot)
    else 0
  end;

  insert into public.transactions (
    walk_id, chat_id, post_id, owner_id, sitter_id, amount_agorot,
    currency, status, kind, provider, provider_ref, service_day, captured_at,
    parent_transaction_id, sitter_accrued_agorot
  ) values (
    v_parent.walk_id, v_parent.chat_id, v_parent.post_id, v_parent.owner_id, v_parent.sitter_id,
    p_amount_agorot, v_parent.currency, 'succeeded', 'refund', p_provider, p_provider_ref,
    v_parent.service_day, now(), v_parent.id, -v_sitter_reversal
  )
  returning * into v_refund;

  update public.transactions set status = 'refunded' where id = v_parent.id;

  update public.balances
     set owner_refunded_agorot = owner_refunded_agorot + p_amount_agorot,
         updated_at = now()
   where user_id = v_parent.owner_id;

  update public.balances
     set sitter_accrued_agorot = sitter_accrued_agorot - v_sitter_reversal,
         updated_at = now()
   where user_id = v_parent.sitter_id;

  return v_refund;
end;
$$;

-- ============================================================ record_payout() ===
-- Record a manual sitter payout (disbursed offline). Rejects an over-payout
-- (amount must not exceed accrued − already paid out).
create or replace function public.record_payout(
  p_sitter_id     text,
  p_amount_agorot bigint,
  p_method        text,
  p_reference     text,
  p_note          text,
  p_created_by    text
) returns public.payouts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payout    public.payouts;
  v_available bigint;
begin
  select (sitter_accrued_agorot - sitter_paid_out_agorot) into v_available
    from public.balances where user_id = p_sitter_id for update;
  v_available := coalesce(v_available, 0);

  if p_amount_agorot > v_available then
    raise exception 'payout % exceeds available % for sitter %', p_amount_agorot, v_available, p_sitter_id;
  end if;

  insert into public.payouts (sitter_id, amount_agorot, status, method, reference, note, created_by, paid_at)
    values (p_sitter_id, p_amount_agorot, 'paid', p_method, p_reference, p_note, p_created_by, now())
    returning * into v_payout;

  update public.balances
     set sitter_paid_out_agorot = sitter_paid_out_agorot + p_amount_agorot,
         updated_at = now()
   where user_id = p_sitter_id;

  return v_payout;
end;
$$;

-- ===================================================================== RLS ===
-- New tables: RLS on, no permissive policy => deny-all for anon/authenticated.
-- Only the service role (the Edge Functions) reads/writes; it bypasses RLS.
alter table public.payment_customers enable row level security;
alter table public.payouts           enable row level security;
alter table public.webhook_events    enable row level security;
alter table public.receipts          enable row level security;

-- SECURITY DEFINER functions must NOT be reachable via PostgREST (the anon key
-- ships in the app). Lock EXECUTE to the service role on every money RPC.
revoke execute on function public.record_walk_charge(
  text, text, text, text, text, integer, text, text, text, date,
  integer, integer, integer, integer, text, text
) from public, anon, authenticated;
grant execute on function public.record_walk_charge(
  text, text, text, text, text, integer, text, text, text, date,
  integer, integer, integer, integer, text, text
) to service_role;

revoke execute on function public.settle_transaction(text, text, text, text) from public, anon, authenticated;
grant  execute on function public.settle_transaction(text, text, text, text) to service_role;

revoke execute on function public.record_refund(uuid, integer, text, text) from public, anon, authenticated;
grant  execute on function public.record_refund(uuid, integer, text, text) to service_role;

revoke execute on function public.record_payout(text, bigint, text, text, text, text) from public, anon, authenticated;
grant  execute on function public.record_payout(text, bigint, text, text, text, text) to service_role;
