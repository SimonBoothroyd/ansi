// The receipt door's binding of the shared gate. The ladder is covered in
// `import-recipe/auth.test.ts`; this checks the door is bound to it (the same
// allowlist var and statuses) and that its one string is its own.

import { assert, assertEquals } from "@std/assert";
import { ALLOWLIST_ENV, type Caller, readCaller } from "./auth.ts";

function bearer(claims: Record<string, unknown>): string {
  const seg = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, "-").replace(/\//g, "_").replace(
      /=+$/,
      "",
    );
  return `${seg({ alg: "ES256", typ: "JWT" })}.${seg(claims)}.sig`;
}

const request = (auth?: string) =>
  new Request("https://fn.test", {
    method: "POST",
    headers: auth ? { Authorization: auth } : {},
  });

const HH = "11111111-2222-3333-4444-555555555555";
const OTHER = "99999999-8888-7777-6666-555555555555";

function withAllowlist<T>(value: string | undefined, fn: () => T): T {
  const before = Deno.env.get(ALLOWLIST_ENV);
  if (value === undefined) Deno.env.delete(ALLOWLIST_ENV);
  else Deno.env.set(ALLOWLIST_ENV, value);
  try {
    return fn();
  } finally {
    if (before === undefined) Deno.env.delete(ALLOWLIST_ENV);
    else Deno.env.set(ALLOWLIST_ENV, before);
  }
}

Deno.test("receipt auth — ONE allowlist, shared with the recipe door", () => {
  // Not `RECEIPT_ALLOWED_HOUSEHOLDS`: one allowlist covers both doors.
  assertEquals(ALLOWLIST_ENV, "IMPORT_ALLOWED_HOUSEHOLDS");
  withAllowlist(`${OTHER},${HH}`, () => {
    const r = readCaller(request(`Bearer ${bearer({ household_id: HH })}`));
    assert(!("error" in r));
    assertEquals((r as Caller).householdId, HH);
  });
});

Deno.test("receipt auth — a household off the allowlist is 403, in this door's words", () => {
  withAllowlist(OTHER, () => {
    const r = readCaller(request(`Bearer ${bearer({ household_id: HH })}`));
    assert("error" in r);
    assertEquals(r.status, 403);
    assertEquals(r.error, "receipt import is not enabled for this household");
    // Never echoes the household id back to an unauthorised caller.
    assert(!r.error.includes(HH));
  });
});

Deno.test("receipt auth — no household claim is 403, no token is 401", () => {
  withAllowlist(undefined, () => {
    const noClaim = readCaller(request(`Bearer ${bearer({ sub: "u" })}`));
    assert("error" in noClaim);
    assertEquals(noClaim.status, 403);
    assert(noClaim.error.includes("onboarding"));

    const noToken = readCaller(request());
    assert("error" in noToken);
    assertEquals(noToken.status, 401);
  });
});
