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

/** "₪12.50" style formatting for chat messages written back to Firestore. */
export function formatIls(agorot: number): string {
  return `₪${(agorot / 100).toLocaleString("he-IL", {
    minimumFractionDigits: agorot % 100 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  })}`;
}
