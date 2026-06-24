// Verifies a Firebase ID token (RS256 JWT signed by Google's secure-token service).
// This is the auth trust boundary: the iOS app sends its Firebase ID token and we
// confirm it here before doing anything with money.
import { createRemoteJWKSet, jwtVerify } from "jose";

// Defaults to the known Firebase project; override with the FIREBASE_PROJECT_ID
// secret only if the project id ever changes. Not a secret — safe in source.
const PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID") ?? "dogapp-ee349";

// Google publishes the secure-token signing keys as a JWK set. createRemoteJWKSet
// caches them and refreshes on key rotation.
const JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);

export interface FirebaseUser {
  uid: string;
  email?: string;
  emailVerified?: boolean;
}

/** Throws if the token is missing/invalid. Returns the authenticated user on success. */
export async function verifyFirebaseToken(req: Request): Promise<FirebaseUser> {
  // Prefer a dedicated header so it never collides with Supabase's own Authorization
  // handling (functions are deployed with verify_jwt = false).
  const token =
    req.headers.get("x-firebase-token") ??
    req.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ??
    "";

  if (!token) throw new AuthError("missing Firebase ID token");
  if (!PROJECT_ID) throw new AuthError("server misconfigured: FIREBASE_PROJECT_ID unset");

  try {
    const { payload } = await jwtVerify(token, JWKS, {
      issuer: `https://securetoken.google.com/${PROJECT_ID}`,
      audience: PROJECT_ID,
    });
    if (!payload.sub) throw new AuthError("token has no subject");
    return {
      uid: payload.sub,
      email: payload.email as string | undefined,
      emailVerified: payload.email_verified as boolean | undefined,
    };
  } catch (e) {
    if (e instanceof AuthError) throw e;
    throw new AuthError(`invalid Firebase ID token: ${(e as Error).message}`);
  }
}

export class AuthError extends Error {}
