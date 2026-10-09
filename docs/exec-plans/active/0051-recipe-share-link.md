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
- **Macros and timers, no cost.** Macros per portion, by the app's own rule
  (invariant 3): a stub, an unconvertible line or a bare count leaves **no
  total at all** (`perServing` is null), and the page names the lines that
  cost it, as the recipe page does. Cost is left off: it comes from the household's own
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
  The domain is **`getansi.app`**, held by the owner; a link reads
  `https://getansi.app/r/<token>`. `.app` is HSTS-preloaded, so it is HTTPS
  only — which the Worker gives for free. The Worker's free tier is 100k
  requests a day.

## Why there is a Worker at all

Supabase serves no browser-renderable HTML from Edge Functions on the shared
`*.supabase.co` domain unless the project has a Custom Domain (Supabase
changelog, October 2024: *"XHTML responses are only allowed with a Custom
Domain enabled"*). A share page there would not render, and Ansi's own import
refuses a non-HTML response (`supabase/functions/_shared/jsonld.ts`,
`HTML_TYPES`). It was never observed on our project, and it no longer needs
to be: the Worker sets the header whatever Supabase sends, so the design holds
either way.

## Approach

The edge function owns every decision; the Worker owns only the domain and
the header.

```
browser ──GET /r/<token>──▶ Worker (getansi.app)
                              │  forwards GET only, /r/<token> only
                              ▼
                     edge function `share-recipe`
                       service role, looks up by token
                       renders HTML + JSON-LD + the page's data
                              │  (served as text/plain on supabase.co)
                              ▼
                     Worker sets content-type: text/html, caching
```

0. **Spike the Dart.** Compile a toy `core/units` entry point with
   `dart compile js` and run it both in a browser and inside the Deno edge
   runtime (dart2js output may want a `self` preamble there). Its size, and
   whether it runs in Deno, decide phase 3's shape. Local only: the Dart SDK
   and the Supabase CLI's local stack, no cloud. The host is proven by the
   real thing in phase 5 — a browser renders `getansi.app/r/<token>`, Import
   accepts it, a WhatsApp / iMessage preview unfurls.
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
   seeded recipe, including a nested component and a recipe measure. Phase 0
   settled the shape: the same compiled Dart renders the page inside the
   function and runs the stepper in the browser.
5. **The Worker.** `cloudflare/share-worker/` (or similar): forwards
   `GET /r/<token>` and the bundle's path, nothing else; sets
   `content-type: text/html; charset=utf-8` and the cache header. Deployed by
   `wrangler` from CI with a `CLOUDFLARE_API_TOKEN` secret, after
   `deploy-supabase`. `getansi.app` is routed to it as a Worker custom domain
   (the zone must be on the owner's Cloudflare account).
6. **Docs.** `docs/SECURITY.md` (a public, unauthenticated surface: what it
   exposes and why only by token), `docs/cloud-setup.md` (the domain, the
   Worker, the token secret), `docs/release.md` (the Worker's deploy), the
   board, `ARCHITECTURE.md`'s standing table, the roadmap.

## Acceptance criteria

- [ ] Phase 0 recorded below: the bundle's size, and whether dart2js output
      runs in the Deno edge runtime.
- [ ] On `getansi.app`: a browser renders the page, Import accepts it, a
      WhatsApp / iMessage preview unfurls.
- [ ] A shared link renders a cookable page: nested sub-recipes, `2 blobs
      (30 g)`, macros by the app's rule (no total while a line is excluded),
      running timers.
- [ ] The stepper rescales lines and macros with the app's own rules — the
      same numbers the recipe page shows at that servings.
- [ ] Pasting the link into Ansi's Import reads it through JSON-LD.
- [ ] *Stop sharing* makes the link a 404 within a minute; sharing again makes
      a new URL.
- [ ] No anon RLS policy on any table; the function reads only by token.
- [ ] Tests: pgTAP on the RPCs, Dart unit tests on the renderer, Deno tests on
      the function, a simulator test on the ⋯ menu.
- [ ] Docs updated (phase 6).

## Phase 0 — the Dart spike (2026-10-09)

A scratch package linked `app/lib` and compiled one entry point that takes a
JSON payload, scales with `scaleGroups`, prints lines with `amountOfLine` and
totals with `summarizeRecipeMacros` — the app's code unmodified, needing only
`meta` and `freezed_annotation`. Dart SDK 3.13.5.

- **Size:** 99 KB raw, **30 KB gzipped** at `-O4` (102 KB / 31 KB at `-O2`).
  Small enough to load with the page; no deferral needed.
- **Runs unmodified** in Deno 2.9.6 — evaluated as a script and as a static
  `import`, as an edge function bundles it — and in Chromium. Node needs a
  one-line `self = globalThis` shim. **Not run in Supabase's own edge
  runtime**: its image could not be pulled here (Docker Hub 429, the ECR
  mirror refused). Deno 2 stands in; the first deploy confirms.
- **Speed:** about 0.14 ms a render in Chromium (1,000 in 143 ms).
- **Numbers check by hand:** 400 g udon at 130 kcal/100 g plus 1 tbsp soy at
  density 1.2 and 53 kcal/100 g, over 2 servings, is 265 kcal a serving; the
  bundle says 265, and rescaling leaves it, as a per-serving figure should.
- **What it found:** a measured component line did not scale (fixed; see the
  notes),
  and the plan's "partial total" was wrong — the app shows none.

## Decision log

Append-only.

- 2026-10-09 — The eight rulings above, asked one at a time.
- 2026-10-09 — The edge-function URL alone was the first host chosen; it was
  dropped on reading that `*.supabase.co` does not serve HTML without a Custom
  Domain. The Supabase add-on (~$35/month with Pro) was weighed against a free
  Worker on a ~$10/year domain; the owner chose the domain and the Worker.
- 2026-10-09 — The domain is `getansi.app`, already held by the owner.
- 2026-10-09 — The `supabase.co` HTML probe is dropped from phase 0: the Worker
  overrides the header whatever Supabase sends, so its answer changes nothing.
- 2026-10-09 — Phase 0 ran: one Dart renderer for server and browser.

## Notes / open questions

- **Where `getansi.app`'s DNS lives.** If it was not bought through Cloudflare,
  its nameservers move to Cloudflare first (a free zone) so the Worker can
  answer on it. Phase 0 can run on `workers.dev` meanwhile; only the share
  URL's base changes.
- **The rest of `getansi.app`.** The share page needs only `/r/*`. The root
  could later redirect to, or serve, the web app now on GitHub Pages — not in
  this plan.
- **Does a household member see the other's share?** Proposed: the ⋯ menu asks
  the RPC whether a link exists, so both see *Stop sharing* without
  `recipe_share` joining a sync stream. Revisit if that round-trip is felt.
- **A sub-recipe deleted after sharing** renders as its name only, the way the
  app treats a missing component. Confirm when building phase 3.
- **A measured component line did not scale — fixed ahead of this plan.**
  Phase 0 found `2 blob miso butter` stayed `2 blob` at any servings:
  `scaleLineItem` went through `LineItem.asQuantity`, null on a line said in a
  recipe measure. The recipe page's stepper had the same gap (a widget test
  reproduced it: `4 blob` at 8 servings stayed `4 blob` at 10). Now the count
  scales; `scaling_test.dart` and `recipe_component_screens_test.dart` hold it.
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
