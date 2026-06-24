-- DogSitter payments ledger.
--
-- Money is stored as INTEGER agorot (1 ILS = 100 agorot) to avoid floating-point
-- drift. Firestore remains the app's source of truth for walks/posts/chats; this
-- schema is the authoritative *payment* ledger and the idempotency guard.
--
-- Collect-only model: the platform "collects" per charge and the sitter's earnings
-- only ACCRUE here (sitter_accrued_agorot). There are no payouts yet.

-- ----------------------------------------------------------------- transactions ---
-- One row per processed walk charge. UNIQUE(walk_id) makes charging idempotent: a
-- retry / double "stop walk" can never double-charge.
create table if not exists public.transactions (
  id             uuid primary key default gen_random_uuid(),
  walk_id        text not null unique,
  chat_id        text not null,
  post_id        text not null,
  owner_id       text not null,
  sitter_id      text not null,
  amount_agorot  integer not null check (amount_agorot >= 0),
  currency       text not null default 'ILS',
  status         text not null default 'pending'
                   check (status in ('pending', 'succeeded', 'failed', 'refunded')),
  provider       text not null default 'mock',
  provider_ref   text,
  service_day    date not null,            -- walk's calendar day (Asia/Jerusalem); day-rate billing key
  created_at     timestamptz not null default now(),
  captured_at    timestamptz
);

create index if not exists transactions_chat_day_idx
  on public.transactions (chat_id, service_day) where amount_agorot > 0;
create index if not exists transactions_owner_idx  on public.transactions (owner_id);
create index if not exists transactions_sitter_idx on public.transactions (sitter_id);

-- -------------------------------------------------------------- payment_methods ---
-- Mock/sandbox cards only. NEVER store a real PAN here — when the real rail lands,
-- card capture moves to the provider SDK and we keep only brand + last4 + a token.
create table if not exists public.payment_methods (
  id             uuid primary key default gen_random_uuid(),
  user_id        text not null,
  brand          text not null default 'mock',
  last4          text not null,
  provider_token text not null,            -- opaque token from the provider (mock for now)
  is_default     boolean not null default false,
  created_at     timestamptz not null default now()
);
create index if not exists payment_methods_user_idx on public.payment_methods (user_id);

-- --------------------------------------------------------------------- balances ---
-- Per-user running totals. owner_charged = lifetime charged to this owner;
-- sitter_accrued = lifetime earned (not yet paid out — collect-only).
create table if not exists public.balances (
  user_id               text primary key,
  owner_charged_agorot  bigint not null default 0,
  sitter_accrued_agorot bigint not null default 0,
  currency              text not null default 'ILS',
  updated_at            timestamptz not null default now()
);

-- --------------------------------------------------------------- payment_events ---
-- Append-only audit log (charge attempts, provider responses, future webhooks).
create table if not exists public.payment_events (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null,               -- e.g. 'charge_attempt', 'charge_succeeded', 'charge_failed'
  walk_id     text,
  actor_uid   text,
  payload     jsonb,
  created_at  timestamptz not null default now()
);
create index if not exists payment_events_walk_idx on public.payment_events (walk_id);

-- ---------------------------------------------------------- record_walk_charge() ---
-- Atomically insert a succeeded transaction AND accrue both sides of the ledger in a
-- single DB transaction, so a partial write can never leave the ledger inconsistent.
-- Returns the inserted transaction row.
create or replace function public.record_walk_charge(
  p_walk_id       text,
  p_chat_id       text,
  p_post_id       text,
  p_owner_id      text,
  p_sitter_id     text,
  p_amount_agorot integer,
  p_currency      text,
  p_provider      text,
  p_provider_ref  text,
  p_service_day   date
) returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx public.transactions;
begin
  insert into public.transactions (
    walk_id, chat_id, post_id, owner_id, sitter_id, amount_agorot,
    currency, status, provider, provider_ref, service_day, captured_at
  ) values (
    p_walk_id, p_chat_id, p_post_id, p_owner_id, p_sitter_id, p_amount_agorot,
    p_currency, 'succeeded', p_provider, p_provider_ref, p_service_day, now()
  )
  returning * into v_tx;

  -- Collect-only: accrue charge to the owner and earnings to the sitter.
  insert into public.balances (user_id, owner_charged_agorot, sitter_accrued_agorot, currency)
    values (p_owner_id, p_amount_agorot, 0, p_currency)
    on conflict (user_id) do update
      set owner_charged_agorot = public.balances.owner_charged_agorot + excluded.owner_charged_agorot,
          updated_at = now();

  insert into public.balances (user_id, owner_charged_agorot, sitter_accrued_agorot, currency)
    values (p_sitter_id, 0, p_amount_agorot, p_currency)
    on conflict (user_id) do update
      set sitter_accrued_agorot = public.balances.sitter_accrued_agorot + excluded.sitter_accrued_agorot,
          updated_at = now();

  return v_tx;
end;
$$;

-- Lock everything down: only the service role (the Edge Functions) touches these
-- tables. RLS on with no permissive policy = deny for anon/authenticated; the
-- service role bypasses RLS.
alter table public.transactions    enable row level security;
alter table public.payment_methods enable row level security;
alter table public.balances        enable row level security;
alter table public.payment_events  enable row level security;

-- record_walk_charge is SECURITY DEFINER, so it must NOT be reachable via the public
-- REST API (PostgREST exposes functions to anon/authenticated by default, and the
-- anon key ships in the app). Restrict EXECUTE to the service role — the only caller
-- is the charge-walk Edge Function using the service-role key.
revoke execute on function public.record_walk_charge(
  text, text, text, text, text, integer, text, text, text, date
) from public, anon, authenticated;

grant execute on function public.record_walk_charge(
  text, text, text, text, text, integer, text, text, text, date
) to service_role;
