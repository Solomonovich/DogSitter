// Billing rules. Money is integer agorot (1 ILS = 100 agorot).
//
//  - Walking posts: a flat price PER COMPLETED WALK (post.payAmount).
//  - Overnight posts: a per-night price × nights, charged once at end of stay.

/** Walking: flat charge for one completed walk. */
export function computeWalkChargeAgorot(payAmount: number): number {
  if (!(payAmount > 0)) return 0;
  return Math.round(payAmount * 100);
}

/** Overnight: per-night rate × number of nights. */
export function computeStayChargeAgorot(perNightAmount: number, nights: number): number {
  if (!(perNightAmount > 0) || nights < 1) return 0;
  return Math.round(perNightAmount * 100) * nights;
}

/** Booked nights between two ISO timestamps (start → end), minimum 1. */
export function computeNights(startISO: string | undefined, endISO: string | undefined): number {
  if (!startISO || !endISO) return 1;
  const ms = new Date(endISO).getTime() - new Date(startISO).getTime();
  return Math.max(1, Math.round(ms / 86_400_000));
}

/** A post's type, with the same migration fallback as the iOS `mappedPostType`. */
export function mappedPostType(post: Record<string, unknown>): "walking" | "overnight" {
  const raw = String(post.postType ?? "");
  if (raw === "walking" || raw === "overnight") return raw;
  return post.sittingType === "הליכות" ? "walking" : "overnight";
}

/** The walk/stay's calendar day in Israel time, YYYY-MM-DD. */
export function serviceDayString(endTimeISO: string | undefined): string {
  const d = endTimeISO ? new Date(endTimeISO) : new Date();
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jerusalem",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

// ----------------------------------------------------------------- commission ---
// The platform's marketplace take-rate, in basis points (PLATFORM_FEE_BPS, e.g.
// 1000 = 10%). Defaults to 0 => no fee, the sitter accrues the full amount.
function platformFeeBps(): number {
  return Number(Deno.env.get("PLATFORM_FEE_BPS") ?? 0) || 0;
}

/** Split a gross charge into the platform fee and the sitter's NET earnings. */
export function computeFeeSplit(amountAgorot: number): {
  platformFeeAgorot: number;
  sitterAccruedAgorot: number;
} {
  const fee = Math.round((amountAgorot * platformFeeBps()) / 10_000);
  const platformFeeAgorot = Math.max(0, Math.min(fee, amountAgorot));
  return { platformFeeAgorot, sitterAccruedAgorot: amountAgorot - platformFeeAgorot };
}

// ------------------------------------------------------------------------- VAT ---
// Israeli VAT, in basis points (VAT_RATE_BPS, e.g. 1800 = 18%). VAT_INCLUSIVE
// (default true) means the displayed price already includes VAT, so we back it
// out of the gross; exclusive would add it on top. Defaults to 0 => no VAT line.
function vatRateBps(): number {
  return Number(Deno.env.get("VAT_RATE_BPS") ?? 0) || 0;
}
function vatInclusive(): boolean {
  return (Deno.env.get("VAT_INCLUSIVE") ?? "true") !== "false";
}

/** The VAT portion of a gross charge and the rate used (for receipts/audit). */
export function computeVat(grossAgorot: number): { vatAgorot: number; vatRateBps: number } {
  const rate = vatRateBps();
  if (rate <= 0) return { vatAgorot: 0, vatRateBps: 0 };
  const vat = vatInclusive()
    ? Math.round((grossAgorot * rate) / (10_000 + rate))
    : Math.round((grossAgorot * rate) / 10_000);
  return { vatAgorot: vat, vatRateBps: rate };
}

/** "₪12.50" style formatting for chat messages written back to Firestore. */
export function formatIls(agorot: number): string {
  return `₪${(agorot / 100).toLocaleString("he-IL", {
    minimumFractionDigits: agorot % 100 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  })}`;
}
