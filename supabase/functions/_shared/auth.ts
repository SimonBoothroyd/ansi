// Who may spend the extraction budget; shared by both import doors.
//
// This module has zero imports, so testing auth does not pull in a `live.ts`
// module graph (the Postgres driver, a provider adapter).
//
// Two gates, in order:
//   1. the `household_id` claim the `add_household_claim` hook (migration 0007)
//      stamps into the caller's JWT. The Supabase gateway verifies the
//      signature first (`verify_jwt = true`); this file only decodes verified
//      claims. It authorises, it never authenticates.
//   2. an optional household allowlist, `IMPORT_ALLOWED_HOUSEHOLDS`, because
//      these functions spend money per call. Unset (local dev) ⇒ every
//      onboarded household is allowed. One allowlist covers both doors.

/** The env var holding a comma-separated list of household UUIDs. */
export const ALLOWLIST_ENV = "IMPORT_ALLOWED_HOUSEHOLDS";

export interface Caller {
  userId: string;
  householdId: string;
}

export interface AuthFailure {
  error: string;
  status: number;
}

/** What each door calls itself, and how it says "not for you". */
export interface AuthVoice {
  /** The function's own name, for the log line ("import-recipe"). */
  fn: string;
  /** The 403 a non-allowlisted household is shown. Never echoes the id. */
  denied: string;
}

/** base64url JSON segment → object (UTF-8 safe; tolerates missing padding). */
function decodeSegment(seg: string): Record<string, unknown> | null {
  try {
    const b64 = seg.replace(/-/g, "+").replace(/_/g, "/").padEnd(
      Math.ceil(seg.length / 4) * 4,
      "=",
    );
    const bin = atob(b64);
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    const parsed = JSON.parse(new TextDecoder().decode(bytes));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return null;
    }
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

/**
 * The parsed {@link ALLOWLIST_ENV} value, or `null` when the var is unset or
 * blank (no allowlist). A var that is set but lists nothing usable yields an
 * empty set, which denies everyone.
 */
export function allowedHouseholds(): Set<string> | null {
  const raw = Deno.env.get(ALLOWLIST_ENV);
  if (raw === undefined || raw.trim() === "") return null;
  return new Set(
    raw.split(",").map((s) => s.trim().toLowerCase()).filter((s) => s !== ""),
  );
}

/**
 * Reads the caller from the request's bearer token and applies the allowlist.
 *
 * 401 — no bearer token, or a token that is not three decodable segments.
 * 403 — a valid token with no `household_id` claim (not onboarded), or a
 *       household that is not on the allowlist when one is configured.
 */
export function readCaller(
  req: Request,
  voice: AuthVoice,
): Caller | AuthFailure {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (!token) return { error: "missing bearer token", status: 401 };
  const parts = token.split(".");
  const claims = parts.length === 3 ? decodeSegment(parts[1]) : null;
  if (!claims) return { error: "malformed bearer token", status: 401 };
  const householdId = typeof claims.household_id === "string"
    ? claims.household_id
    : "";
  if (!householdId) {
    return {
      error: "no household on this account — finish onboarding first",
      status: 403,
    };
  }
  const allowed = allowedHouseholds();
  if (allowed && !allowed.has(householdId.trim().toLowerCase())) {
    // Does not echo the household id back to the client.
    console.error(`${voice.fn}: household not allowlisted: ${householdId}`);
    return { error: voice.denied, status: 403 };
  }
  return { userId: String(claims.sub ?? ""), householdId };
}
