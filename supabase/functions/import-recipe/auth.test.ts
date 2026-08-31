import { assert, assertEquals } from "@std/assert";
import { ALLOWLIST_ENV, type Caller, readCaller } from "./auth.ts";

// A token in the shape the gateway hands us: three base64url segments. Only the
// payload is read here (the gateway has already verified the signature), so the
// header/signature are filler.
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

/** Runs `fn` with the allowlist set to `value` (or unset), then restores it. */
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

const asCaller = (r: Caller | { error: string; status: number }): Caller => {
  assert(!("error" in r), `expected a caller, got ${JSON.stringify(r)}`);
  return r;
};

Deno.test("readCaller — no allowlist: any onboarded household passes", () => {
  withAllowlist(undefined, () => {
    const c = asCaller(
      readCaller(request(`Bearer ${bearer({ sub: "u-1", household_id: HH })}`)),
    );
    assertEquals(c, { userId: "u-1", householdId: HH });
  });
});

Deno.test("readCaller — a blank allowlist reads as unset (local dev)", () => {
  withAllowlist("   ", () => {
    assertEquals(
      asCaller(readCaller(request(`Bearer ${bearer({ household_id: HH })}`)))
        .householdId,
      HH,
    );
  });
});

Deno.test("readCaller — allowlisted household passes", () => {
  withAllowlist(`${OTHER},${HH}`, () => {
    assertEquals(
      asCaller(readCaller(request(`Bearer ${bearer({ household_id: HH })}`)))
        .householdId,
      HH,
    );
  });
});

Deno.test("readCaller — allowlist matching ignores case and padding", () => {
  withAllowlist(`  ${HH.toUpperCase()} , ${OTHER}  `, () => {
    assertEquals(
      asCaller(readCaller(request(`Bearer ${bearer({ household_id: HH })}`)))
        .householdId,
      HH,
    );
  });
});

Deno.test("readCaller — a household NOT on the allowlist is 403", () => {
  withAllowlist(OTHER, () => {
    const r = readCaller(request(`Bearer ${bearer({ household_id: HH })}`));
    assert("error" in r);
    assertEquals(r.status, 403);
    // Never echoes the household id back to an unauthorised caller.
    assert(!r.error.includes(HH));
  });
});

Deno.test("readCaller — an allowlist that lists nothing usable denies everyone", () => {
  withAllowlist(", ,,", () => {
    const r = readCaller(request(`Bearer ${bearer({ household_id: HH })}`));
    assert("error" in r);
    assertEquals(r.status, 403);
  });
});

Deno.test("readCaller — a token with no household claim is 403 (not onboarded)", () => {
  withAllowlist(undefined, () => {
    for (const claims of [{ sub: "u" }, { household_id: 42 }, {}]) {
      const r = readCaller(request(`Bearer ${bearer(claims)}`));
      assert("error" in r, `expected a failure for ${JSON.stringify(claims)}`);
      assertEquals(r.status, 403);
    }
  });
});

Deno.test("readCaller — the household gate runs BEFORE the allowlist", () => {
  // A claimless token must not be able to probe allowlist membership.
  withAllowlist(HH, () => {
    const r = readCaller(request(`Bearer ${bearer({ sub: "u" })}`));
    assert("error" in r);
    assertEquals(r.status, 403);
    assert(r.error.includes("onboarding"));
  });
});

Deno.test("readCaller — a missing or malformed token is 401", () => {
  withAllowlist(undefined, () => {
    const cases: [string, string | undefined][] = [
      ["no header", undefined],
      ["empty bearer", "Bearer "],
      ["wrong scheme", `Basic ${bearer({ household_id: HH })}`],
      ["not three segments", "Bearer aaa.bbb"],
      ["undecodable payload", "Bearer aaa.!!!!.ccc"],
      ["payload is not an object", `Bearer aaa.${btoa('"nope"')}.ccc`],
    ];
    for (const [label, header] of cases) {
      const r = readCaller(request(header));
      assert("error" in r, `expected a failure: ${label}`);
      assertEquals(r.status, 401, label);
    }
  });
});
