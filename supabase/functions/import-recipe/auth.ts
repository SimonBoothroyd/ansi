// The recipe door's binding of the shared household gate (`_shared/auth.ts`).
// Local are the log prefix and the sentence a household outside the allowlist
// is shown.

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
  fn: "import-recipe",
  denied: "recipe import is not enabled for this household",
};

/**
 * Reads the caller from the request's bearer token and applies the allowlist.
 * See `_shared/auth.ts` for the two gates and what each status means.
 */
export function readCaller(req: Request): Caller | AuthFailure {
  return readSharedCaller(req, VOICE);
}
