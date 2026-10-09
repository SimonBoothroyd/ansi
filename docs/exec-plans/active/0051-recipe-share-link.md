# Exec plan: A recipe's share link

- **Status:** draft — rulings taken, nothing built; phase 0 (the host spike) comes first
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** Next 2 — the next idea off the backlog
- **Created:** 2026-10-09

## Goal

A recipe can be handed to someone outside the household as a link. Opening
it shows a read-only page that can be cooked from — sub-recipes nested in, the
recipe's own measures said with their real amount, macros, tappable timers and
a servings stepper — and the page carries schema.org `Recipe` JSON-LD, so a
person who also uses Ansi can paste the link into Import, and the existing
pipeline reads it (the recipe page in other apps does the same).

Nothing about a household's data model changes for the reader: no
cross-household rows, no new sync surface for them, no account.

## Rulings

Taken one at a time with the owner, 2026-10-09.

- **Live, not a snapshot.** The link always shows the recipe as it is now; a
  typo fixed after sharing reaches everyone holding the link. No stored copy.
- **A sub-recipe is a nested section.** The parent's line reads
  `200 g tahini sauce (below)` and the sauce's own ingredients and method
  follow on the same page. A link is self-contained and cookable.
- **A recipe's own measure is said both ways.** `2 blobs (30 g) miso butter`
  — the recipe's word ([ADR-0018](../../decisions/0018-a-recipe-measure-is-a-named-amount.md))
  and the amount it stands for.
- **Macros and timers, no cost.** Macros per portion, a `stub` ingredient
  excluded and the total marked partial — the same honest-numbers rule as the
  app (invariant 3). Cost is left off: it comes from the household's own
  receipts. A method's timer chips start a countdown on the page. No photo:
  recipe photos do not exist yet ([backlog](../backlog.md)).
- **Scaling, in v1.** A servings stepper on the page.
- **The scaling is the app's own Dart, compiled to JS.** `core/units` and the
  recipe `domain/` folders are pure Dart (invariant 2), so the page loads a
  `dart compile js` bundle of them rather than a TypeScript port. One source of
  truth, nothing to drift, no shared-vector file to keep.
- **One link per recipe, revocable.** Sharing again returns the same URL.
  *Stop sharing* kills it; a later share mints a fresh token.
- **An Ansi user imports it through JSON-LD only.** No *Save to Ansi* button,
  no app links, no cross-household copy — matching stays per household
  ([ADR-0004](../../decisions/0004-matching-is-online-only.md)).
- **A custom domain, served by a free Cloudflare Worker.** Not the Supabase
  Custom Domain add-on: it needs the Pro plan, about $35 a month together,
  against a free-tier budget ([ADR-0002](../../decisions/0002-stack-flutter-supabase-powersync.md)).
  A domain is about $10 a year; the Worker's free tier is 100k requests a day.

## Why there is a Worker at all

Supabase serves no browser-renderable HTML from Edge Functions on the shared
`*.supabase.co` domain unless the project has a Custom Domain (Supabase
changelog, October 2024: *"XHTML responses are only allowed with a Custom
Domain enabled"*). A share page there would not render, and Ansi's own import
refuses a non-HTML response (`supabase/functions/_shared/jsonld.ts`,
`HTML_TYPES`). **Not yet observed on our project** — this session's network
could not reach Supabase — so phase 0 proves it before anything is built on it.

## Approach

The edge function owns every decision; the Worker owns only the domain and
the header.

```
browser ──GET /r/<token>──▶ Worker (ansi domain)
                              │  forwards GET only, /r/<token> only
                              ▼
                     edge function `share-recipe`
                       service role, looks up by token
                       renders HTML + JSON-LD + the page's data
                              │  (served as text/plain on supabase.co)
                              ▼
                     Worker sets content-type: text/html, caching
```

0. **Spike the host.** Deploy a throwaway `html-probe` function and record the
   `content-type` it is served with on `*.supabase.co`. Stand the Worker up on
   `workers.dev` in front of it and confirm a browser renders it, the existing
   import's `fetchBlob` accepts it, and a WhatsApp / iMessage preview unfurls.
   **Also spike the Dart:** compile a toy `core/units` entry point with
   `dart compile js` and run it both in a browser and inside the Deno edge
   runtime (dart2js output may want a `self` preamble there). Its size, and
   whether it runs in Deno, decide phase 3's shape. Delete the probe.
1. **The share row.** Migration `0054_recipe_share`: `recipe_share (id,
   household_id, recipe_id unique, token unique, created_at)`, the token 128
   random bits, base64url. RLS: a member creates, reads and deletes their own
   household's rows; no anon policy at all. Two RPCs, `share_recipe(recipe_id)
   → token` (returns the existing one) and `unshare_recipe(recipe_id)`. pgTAP
   for both, including a member of another household being refused.
2. **The ⋯ menu.** *Share link* on the recipe page's ⋯ menu calls the RPC and
   opens the system share sheet with the URL (the clipboard on a browser
   without `navigator.share`). Once shared, the menu also offers *Stop
   sharing*. The action is online, like Import; offline it says so rather than
   queueing a link that would not work yet. Drawn first as `proposed` in
   [recipe-page.html](../../product-specs/board/recipe-page.html).
3. **The renderer, in Dart.** A new pure-Dart entry point (say
   `app/lib/features/share/domain/`) takes a recipe payload — the recipe, its
   lines, its sub-recipes, the ingredient facts the macros and units need — and
   produces the page's sections, the JSON-LD and the scaled lines for a given
   servings. It reuses `scaling.dart`, `line_display.dart`, `component_math.dart`
   and `recipe_macros.dart`; it does not re-state them. Unit tests mirror it.
   Compiled once with `dart compile js` into a bundle checked by CI.
4. **The edge function `share-recipe`.** `GET /r/<token>`: look the token up
   with the service role, read the recipe tree (soft-deleted rows excluded),
   build the payload and render the page at base servings — server-side, so the
   JSON-LD and the link preview are in the served HTML. The same bundle runs in
   the browser for the stepper, the macros at the new size and the timers. An
   unknown or revoked token is a plain 404 page. `noindex`, and a short
   `max-age` so a revoke or an edit shows within a minute. Deno tests against a
   seeded recipe, including a nested component and a recipe measure. Whether
   the Dart renders inside Deno or the HTML is templated in TS around the
   bundle's output is phase 0's answer.
5. **The Worker.** `cloudflare/share-worker/` (or similar): forwards
   `GET /r/<token>` and the bundle's path, nothing else; sets
   `content-type: text/html; charset=utf-8` and the cache header. Deployed by
   `wrangler` from CI with a `CLOUDFLARE_API_TOKEN` secret, after
   `deploy-supabase`. The domain is bought and pointed at it by the owner.
6. **Docs.** `docs/SECURITY.md` (a public, unauthenticated surface: what it
   exposes and why only by token), `docs/cloud-setup.md` (the domain, the
   Worker, the token secret), `docs/release.md` (the Worker's deploy), the
   board, `ARCHITECTURE.md`'s standing table, the roadmap.

## Acceptance criteria

- [ ] Phase 0 recorded below: the `supabase.co` content-type, the Worker
      rendering, the import accepting it, a preview unfurling, dart2js in Deno.
- [ ] A shared link renders a cookable page: nested sub-recipes, `2 blobs
      (30 g)`, macros with stubs excluded and marked partial, running timers.
- [ ] The stepper rescales lines and macros with the app's own rules — the
      same numbers the recipe page shows at that servings.
- [ ] Pasting the link into Ansi's Import reads it through JSON-LD.
- [ ] *Stop sharing* makes the link a 404 within a minute; sharing again makes
      a new URL.
- [ ] No anon RLS policy on any table; the function reads only by token.
- [ ] Tests: pgTAP on the RPCs, Dart unit tests on the renderer, Deno tests on
      the function, a simulator test on the ⋯ menu.
- [ ] Docs updated (phase 6).

## Decision log

Append-only.

- 2026-10-09 — The eight rulings above, asked one at a time.
- 2026-10-09 — The edge-function URL alone was the first host chosen; it was
  dropped on reading that `*.supabase.co` does not serve HTML without a Custom
  Domain. The Supabase add-on (~$35/month with Pro) was weighed against a free
  Worker on a ~$10/year domain; the owner chose the domain and the Worker.

## Notes / open questions

- **The domain's name** — the owner's to pick and buy. Until it exists, phase 0
  and the build run on `workers.dev`; nothing but a DNS record and the share
  URL's base changes when it lands.
- **Does a household member see the other's share?** Proposed: the ⋯ menu asks
  the RPC whether a link exists, so both see *Stop sharing* without
  `recipe_share` joining a sync stream. Revisit if that round-trip is felt.
- **A sub-recipe deleted after sharing** renders as its name only, the way the
  app treats a missing component. Confirm when building phase 3.
- **The bundle's size.** If `dart compile js` of the units core is large, the
  page renders fully server-side and the bundle loads deferred, only for the
  stepper and timers.
- **Ingredient facts become public.** The macros need per-ingredient macro and
  density rows for the lines on the page; only those rows, only those fields.

## Step-done checklist

The code landing is not the step landing. Tick these before setting Status to
done and moving this file to `completed/`.

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [ ] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator (the UI paths CI
      can't reach), and the result recorded here.
- [ ] Tech-debt rows **added** for corners knowingly cut, and **retired** (or
      narrowed) for debt this step paid off.
- [ ] New migrations or seed changes? Say in the roadmap row whether they have
      reached **cloud** yet, and append a `docs/cloud-setup.md` ledger entry
      when they do. A "pending cloud push" note nobody clears becomes a false
      claim the moment the push happens.
- [ ] `make ci` green.
