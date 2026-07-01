// Saved-card lookups for the charge pipeline. A card row is the owner's tokenized
// payment method for the active provider (Stripe pm_… / Grow token) plus the
// provider customer id. Soft-deleted cards (deleted_at set) are never charged.
import { SupabaseClient } from "@supabase/supabase-js";

export interface CardRow {
  id: string;
  provider_token: string;
  customer_id: string | null;
  brand: string;
  last4: string;
}

/** The owner's card to charge: the default if set, else the most recent active. */
export async function getDefaultCard(
  db: SupabaseClient,
  uid: string,
  provider: string,
): Promise<CardRow | null> {
  const { data } = await db
    .from("payment_methods")
    .select("id, provider_token, customer_id, brand, last4, is_default, created_at")
    .eq("user_id", uid)
    .eq("provider", provider)
    .is("deleted_at", null)
    .order("is_default", { ascending: false })
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return (data as CardRow | null) ?? null;
}

/** Does this user have at least one active card for the active provider? */
export async function hasCard(db: SupabaseClient, uid: string, provider: string): Promise<boolean> {
  const { count } = await db
    .from("payment_methods")
    .select("id", { count: "exact", head: true })
    .eq("user_id", uid)
    .eq("provider", provider)
    .is("deleted_at", null);
  return (count ?? 0) > 0;
}

/** The owner's provider customer id, if one has been created. */
export async function getCustomerId(
  db: SupabaseClient,
  uid: string,
  provider: string,
): Promise<string | null> {
  const { data } = await db
    .from("payment_customers")
    .select("customer_id")
    .eq("user_id", uid)
    .eq("provider", provider)
    .maybeSingle();
  return data?.customer_id ?? null;
}
