// Minimal Firestore Admin client over the REST API. The Edge Function is trusted
// server code, so it uses a Firebase service account to read the source-of-truth
// docs (walk/chat/post) and to write back the payment doc + chat message.
//
// We use REST (not firebase-admin) to keep the edge runtime light. Auth is a
// short-lived OAuth2 access token minted from the service-account key.
import { importPKCS8, SignJWT } from "jose";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

function serviceAccount(): ServiceAccount {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT unset");
  return JSON.parse(raw);
}

function projectId(): string {
  return Deno.env.get("FIREBASE_PROJECT_ID") ?? serviceAccount().project_id;
}

// ---- OAuth2 access token (cached until shortly before expiry) -------------------
let cachedToken: { token: string; exp: number } | null = null;

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.token;

  const sa = serviceAccount();
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/datastore" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`oauth token request failed: ${res.status} ${await res.text()}`);
  const j = await res.json();
  cachedToken = { token: j.access_token, exp: now + (j.expires_in ?? 3600) };
  return cachedToken.token;
}

const BASE = () =>
  `https://firestore.googleapis.com/v1/projects/${projectId()}/databases/(default)/documents`;

// ---- value <-> typed-JSON conversion --------------------------------------------
// Firestore REST wraps every value in a type tag, e.g. { stringValue: "x" }.
type FsValue = Record<string, unknown>;

function decodeValue(v: FsValue): unknown {
  if (v == null) return null;
  if ("nullValue" in v) return null;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("timestampValue" in v) return v.timestampValue; // ISO-8601 string
  if ("arrayValue" in v) {
    const vals = (v.arrayValue as { values?: FsValue[] }).values ?? [];
    return vals.map(decodeValue);
  }
  if ("mapValue" in v) {
    return decodeFields((v.mapValue as { fields?: Record<string, FsValue> }).fields ?? {});
  }
  return null;
}

export function decodeFields(fields: Record<string, FsValue>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fields)) out[k] = decodeValue(v);
  return out;
}

function encodeValue(v: unknown): FsValue {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === "string") return { stringValue: v };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") {
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  }
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(encodeValue) } };
  if (typeof v === "object") return { mapValue: { fields: encodeFields(v as Record<string, unknown>) } };
  return { nullValue: null };
}

export function encodeFields(obj: Record<string, unknown>): Record<string, FsValue> {
  const out: Record<string, FsValue> = {};
  for (const [k, v] of Object.entries(obj)) out[k] = encodeValue(v);
  return out;
}

/** A server timestamp sentinel for writes (encoded as the current time). */
export const serverTimestamp = () => new Date();

// ---- operations -----------------------------------------------------------------
export async function getDoc(path: string): Promise<Record<string, unknown> | null> {
  const token = await accessToken();
  const res = await fetch(`${BASE()}/${path}`, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`firestore get ${path} failed: ${res.status} ${await res.text()}`);
  const doc = await res.json();
  return decodeFields(doc.fields ?? {});
}

/** Create a document with a known id (used for payments/{transactionId}). */
export async function createDoc(
  collectionPath: string,
  docId: string,
  data: Record<string, unknown>,
): Promise<void> {
  const token = await accessToken();
  const res = await fetch(
    `${BASE()}/${collectionPath}?documentId=${encodeURIComponent(docId)}`,
    {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ fields: encodeFields(data) }),
    },
  );
  if (!res.ok) throw new Error(`firestore create ${collectionPath} failed: ${res.status} ${await res.text()}`);
}

/** Add a document with an auto-generated id (used for chat messages). */
export async function addDoc(
  collectionPath: string,
  data: Record<string, unknown>,
): Promise<void> {
  const token = await accessToken();
  const res = await fetch(`${BASE()}/${collectionPath}`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ fields: encodeFields(data) }),
  });
  if (!res.ok) throw new Error(`firestore add ${collectionPath} failed: ${res.status} ${await res.text()}`);
}

/** Patch specific fields on an existing document. */
export async function patchDoc(
  path: string,
  data: Record<string, unknown>,
): Promise<void> {
  const token = await accessToken();
  const mask = Object.keys(data)
    .map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`)
    .join("&");
  const res = await fetch(`${BASE()}/${path}?${mask}`, {
    method: "PATCH",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ fields: encodeFields(data) }),
  });
  if (!res.ok) throw new Error(`firestore patch ${path} failed: ${res.status} ${await res.text()}`);
}
