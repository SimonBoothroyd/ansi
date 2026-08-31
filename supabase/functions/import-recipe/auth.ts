// Who is allowed to spend our extraction budget.
//
// Split out of `live.ts` deliberately: `live.ts` imports the Postgres driver and
// the provider adapter, so a test that touched it would pull the whole live
// module graph (and a remote `deno.land/x` dependency) into `deno test`. Auth is
// the highest-value seam to test, so it lives in a module with ZERO imports.
//
// Two gates, in order:
//   1. the `household_id` claim the `add_household_claim` hook (migration 0007)
//      stamps into the caller's JWT. The Supabase edge gateway verifies the
//      signature before the function runs (`verify_jwt = true`), so we only
//      decode already-verified claims here — never trust this file to
//      authenticate, only to authorise.
//   2. an optional household ALLOWLIST from the environment. This function
//      spends real money per call, so on a deployed project it is restricted to
//      the households named in `IMPORT_ALLOWED_HOUSEHOLDS`. Unset (the local
//      dev default) ⇒ every onboarded household passes gate 1 and is allowed.

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

/** base64url JSON segment → object (UTF-8 safe; tolerant of missing padding). */
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
 * The parsed {@link ALLOWLIST_ENV} value, or `null` when the var is unset/blank
 * (⇒ no allowlist, local-dev behaviour). A var that IS set but lists nothing
 * usable yields an empty set — i.e. it denies everyone, which is the safe read
 * of "someone tried to configure an allowlist".
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
export function readCaller(req: Request): Caller | AuthFailure {
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
    // Deliberately does not echo the household id back to the client.
    console.error(`import-recipe: household not allowlisted: ${householdId}`);
    return {
      error: "recipe import is not enabled for this household",
      status: 403,
    };
  }
  return { userId: String(claims.sub ?? ""), householdId };
}
