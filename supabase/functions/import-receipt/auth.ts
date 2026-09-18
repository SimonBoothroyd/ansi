// The receipt door's binding of the shared household gate.
//
// The gate itself — the `household_id` claim, the `IMPORT_ALLOWED_HOUSEHOLDS`
// allowlist, and the 401/403 ladder — lives in `_shared/auth.ts` and is shared
// with `import-recipe`. All that is local is the two strings that have to name
// this door: the log prefix, and the sentence a household outside the allowlist
// is shown.
//
// ONE allowlist for both doors, on purpose: it names the households that may
// spend the extraction budget, and a household allowed to photograph a recipe
// is the same household allowed to photograph its receipt.

import {
  type AuthFailure,
  type Caller,
  readCaller as readSharedCaller,
} from "../_shared/auth.ts";

export {
  allowedHouseholds,
  ALLOWLIST_ENV,
  type AuthFailure,
  type Caller,
} from "../_shared/auth.ts";

const VOICE = {
  fn: "import-receipt",
  denied: "receipt import is not enabled for this household",
};

/**
 * Reads the caller from the request's bearer token and applies the allowlist.
 * See `_shared/auth.ts` for the two gates and what each status means.
 */
export function readCaller(req: Request): Caller | AuthFailure {
  return readSharedCaller(req, VOICE);
}
