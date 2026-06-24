// Service-role Supabase client for the Edge Functions. The service role bypasses
// RLS — these functions are the only writers of the payment ledger.
import { createClient, SupabaseClient } from "@supabase/supabase-js";

export function serviceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")!;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}
