# Exec plan: A recipe's share link

- **Status:** active — shipped in `v0.28.0` and live on `getansi.app` (migration `0054`, `share-recipe` and the `ansi-share` Worker on cloud since 2026-10-10; the owner opened a shared link on a phone). One item stays open: a simulator run of the ⋯ menu's *Share link* and *Stop sharing*
- **Owner:** Simon (design and rulings), agents in lanes
- **Roadmap step:** Shipped `v0.28.0`; its simulator smoke is Next 2
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
1. **The share row — done.** Migration `0054_recipe_share`: `recipe_share
   (id, household_id, recipe_id, token unique, created_at, deleted_at)`, one
   live row per recipe (a partial unique index), the token 128 random bits,
   base64url. Members only READ it; `share_recipe(recipe_id) → token` (the
   live one, or a fresh one) and `unshare_recipe(recipe_id) → boolean` are the
   only writers, `security definer`, each checking the recipe is the caller's
   own. No anon grant at all. Not synced. pgTAP in `recipe_share.sql`, and a
   row in `rls_household_isolation.sql`.
2. **The ⋯ menu — landed.** *Share link* on the recipe page's ⋯ menu calls
   `share_recipe` and hands `https://getansi.app/r/<token>` and the title to
   the share sheet (`share_plus`); on the web, where the plugin would fall
   back to a `mailto:`, it copies the link and says **Link copied.** *Stop
   sharing* appears only while the server says a link stands, asks first,
   and calls `unshare_recipe`. Online, through the one write door: offline
   says "Couldn't share this recipe." and hands nothing over. **Hidden unless
   the build carries `SHARE_BASE_URL`**, so no shipped build offers a link
   before phase 5 makes it work. `features/share`, drawn in
   [recipe-page.html](../../product-specs/board/recipe-page.html).
3. **The renderer — landed.** `features/share/page/`, pure Dart compiled
   to one JS bundle by `make share-bundle`: `ShareTree.fromPayload` reads the
   database's own rows, `renderSharePage` writes the whole document (preview
   tags, JSON-LD, the body, the embedded payload, the script tag),
   `renderShareBody` the part the stepper re-renders, and the bundle's entry
   exports `ansiSharePage(payloadJson, url, bundleUrl)` for the server and
   wires the stepper and timers in a browser. **The row rules moved into
   `recipes/domain/recipe_rows.dart`**, which the app's repository now reads
   through too, so a row cannot be read one way in the app and another on
   the page. The payload contract is `test/features/share/testdata/
   share_payload.json`. CI compiles the bundle and renders that fixture in
   Deno.
4. **The edge function — landed.** `supabase/functions/share-recipe`,
   deployed with no JWT check. `GET r/<token>` runs one query as service role
   (`payload.ts`: a live share of a live recipe, the sub-recipes it reaches
   inside that household, as the recipe page's rows) and renders it with the
   committed bundle; `GET r/share.js?v=<hash>` serves the bundle itself, so
   one Worker route covers both. 404 for a revoked, deleted or unknown token
   and for a token of the wrong shape (refused before the database); 405 for
   anything but GET and HEAD; a generic 500 page with the detail logged.
   `noindex`, a 60-second cache, and a content-security policy that runs only
   the page's own bundle. `SHARE_BASE_URL` (optional secret) names the
   canonical link. `make share-bundle` writes the bundle beside the function;
   the app's CI fails when the committed copy is stale.
5. **The Worker — live on `getansi.app` from `v0.28.0`.** `cloudflare/share-worker`:
   forwards `GET`/`HEAD` on `/r/<token>` and `/r/share.js` and nothing else,
   passes on none of the visitor's headers, follows no redirect, hides an
   origin error, and sets the page's type and security headers itself.
   `deploy-supabase` step 3b deploys it with `wrangler` (pinned) when the
   `CLOUDFLARE_API_TOKEN` secret and `CLOUDFLARE_ACCOUNT_ID` variable exist,
   passing the function's URL from the project ref, and claims `getansi.app`
   as its custom domain. The `SHARE_BASE_URL` repository variable turns the
   app's Share link on in release builds and sets the function's secret to
   match — set last, once the host answers.
6. **Docs — landed with each phase.** `docs/SECURITY.md`, `docs/cloud-setup.md`
   (§3b the function, §3d the share host, step by step), `docs/release.md`
   (§4.1's optional secrets), the board's recipe page, `ARCHITECTURE.md`, the
   roadmap, and a README beside the feature, the function and the Worker.

## Acceptance criteria

- [x] Phase 0 recorded below: the bundle's size, and whether dart2js output
      runs in the Deno edge runtime.
- [x] On `getansi.app`: a browser renders the page, Import accepts it, a
      WhatsApp / iMessage preview unfurls. *Locally first, through the
      bundled Worker in front of the function and a migrated Postgres; then
      on cloud from `v0.28.0`, where the owner shared a recipe from the app
      and opened the link on a phone (2026-10-10).*
- [x] A shared link renders a cookable page: nested sub-recipes, `2 blob
      (30 g)`, macros by the app's rule (no total while a line is excluded),
      running timers.
- [x] The stepper rescales lines and method chips with the app's own rules;
      macros stay per serving, as the recipe page's panel does.
- [x] Pasting the link into Ansi's Import reads it through JSON-LD — by the
      importer's own parser, locally.
- [x] *Stop sharing* makes the link a 404 within a minute; sharing again makes
      a new URL — by pgTAP, the function's tests and its 60-second cache.
      *Not yet watched on a phone.*
- [x] No anon RLS policy on any table; the function reads only by token.
- [ ] Tests: pgTAP on the RPCs, Dart unit tests on the renderer, Deno tests on
      the function and the Worker — all in. *The ⋯ menu has widget tests, not
      a simulator test: no simulator was available to the session that built
      it. That run is the roadmap's Next 2.*
- [x] Docs updated (phase 6).

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
- 2026-10-09 — Phase 1: **members cannot write a share row.** The plan first
  had RLS letting a member create their own rows; but a client-written row
  can carry its own household id beside ANOTHER household's recipe id, and
  the public page would publish that recipe. So the table grants members
  SELECT only, and two `security definer` functions mint and revoke, each
  checking ownership first. The same move stops a client choosing a
  guessable token.
- 2026-10-09 — Phase 1: **a revoke is soft** (`deleted_at`), as every delete
  here is; the live-link rule is a partial unique index, and a token is
  unique across revoked rows too, so it is never reissued.
- 2026-10-09 — Phase 2: the owner chose the **system share sheet** over
  copy-only, accepting a native plugin (`share_plus`) whose Android and iOS
  builds cannot be compiled in the session that wrote it.
- 2026-10-09 — Phase 2: the menu item is **gated on `SHARE_BASE_URL`**. A
  link handed out before the page exists is a dead link in somebody's chat;
  the release workflow gains the define in phase 5, with the Worker.
- 2026-10-09 — Phase 3: **the payload is rows, not a shape of its own.** The
  edge function selects the recipe page's own columns and aliases as JSON;
  the renderer reads them through the same functions the app's SQLite
  repository does (`recipe_rows.dart`, extracted from it). The two stores
  differ only in representation — 0/1 or true, jsonb as text or as an
  object, a `numeric` as a number or as text — and those are read in one
  place.
- 2026-10-09 — Phase 3: **a sub-recipe is drawn as written**, at its own
  yield. The parent's line says how much of it the scaled dish needs (`4 blob
  (60 g)`); the nested section does not rescale with the parent.
- 2026-10-09 — Phase 3: **no stub wording on a public page.** When the walk
  leaves no total the page says some ingredients have no nutrition data yet,
  not which are stubs; the household's bookkeeping is not a stranger's.
- 2026-10-09 — Phase 3: the bundle is **159 KB, 49 KB gzipped** at `-O4`;
  rendered in Deno 2.9.6 and driven in Chromium (stepper, a timer through a
  rescale), with no script errors. The page loads its three faces from Google
  Fonts, as the design board does.
- 2026-10-09 — Phase 4: **the bundle is committed beside the function**, as
  two generated files: `share_page.js`, imported for its effect so the
  deploy ships it and evaluation needs no `eval`, and `share_page_source.ts`,
  the same source as a string to serve — a deployed function is modules, not
  files it can read. The backend CI has no Flutter and the function's tests
  need the bundle, so building it at deploy time was not the simpler road;
  the app CI's freshness check is the `docs/generated` pattern. dart2js
  output is byte-identical across builds on one SDK, which that check rests
  on.
- 2026-10-09 — Phase 4: **the bundle is served by the function** at
  `r/share.js?v=<hash>`, not from the Worker or Pages, so one route serves
  the page and its script and the hash a page names is the bundle that
  rendered it.
- 2026-10-09 — Phase 4 verified: the handler's tests over the real bundle;
  the query against Postgres 16 with every migration (rows that render the
  fixture's page, 346 kcal included; a revoked token, a deleted recipe and an
  unknown token answer nothing); and the function served locally through
  `live.ts` and driven in Chromium under its own content-security policy,
  with no script errors. **Not yet on cloud**, and not reachable as a page
  there until the Worker stands in front of it.
- 2026-10-09 — Phase 5: **the Worker sets the headers rather than passing
  them on.** Whatever the gateway does to HTML on its shared domain — a
  rewrite to `text/plain`, its own sandboxing policy — the Worker answers
  with the page's real type and the function's own policy, and copies only
  the cache header. A test stands an origin in that behaves that way.
- 2026-10-09 — Phase 5: **the Worker deploys inside `deploy-supabase`**, as
  step 3b after the function, and skips with a notice when Cloudflare is not
  configured; the function's URL is built there from the project ref, so it
  is never committed. The Share link's switch is a repository **variable**,
  `SHARE_BASE_URL`, read by every release build and by the deploy, so turning
  it on is one command after the host has been checked.
- 2026-10-09 — Phase 5 verified locally: `wrangler@4.135.0 deploy --dry-run`
  accepts the config and bundles the Worker (3.4 KiB); that bundle, run in
  Deno in front of the served function and a migrated Postgres, served the
  page (200, `text/html`, the policy), the bundle (immutable), a revoked
  token and the bare host (404), drove cleanly in Chromium, and fed Import's
  JSON-LD reader the whole recipe. Cloudflare itself was not reachable from
  the session.
- 2026-10-09 — Phase 1 was verified on Postgres **16** with a stand-in for
  Supabase's roles and `auth` schema (every migration and seed, all 24 pgTAP
  files green); the container images for the real local stack could not be
  pulled here. CI's `migrations` job runs it on the real stack.
- 2026-10-10 — **On cloud, `v0.28.0`.** `getansi.app` turned out to be
  registered with **Cloudflare Registrar** in the same account, so it was a
  Cloudflare zone already: no nameserver move, and the Worker's custom domain
  owns the bare host. Cloudflare's token page did not list the zone under
  *Specific zone*; *All zones from an account* did. The first two
  `deploy-supabase` runs failed before the share steps: an invalid
  `SUPABASE_ACCESS_TOKEN` (replaced with a new `sbp_` personal access token,
  not a project key), then one scoped too narrowly. The third applied `0054`
  and deployed `share-recipe` and the Worker; `SHARE_BASE_URL` was set and a
  fourth run gave the function its secret. The tag was made from GitHub's
  Releases page, since the session could not push tags; the release was the
  first build of `share_plus` for Android and iOS, and it was green. The
  owner shared a recipe from the app and opened it on a phone. Runs:
  `cloud-setup.md`'s ledger, 2026-10-10.

## Notes / open questions

- **Where `getansi.app`'s DNS lives — settled.** It was bought through
  Cloudflare Registrar, so its DNS was already a Cloudflare zone and no
  nameservers moved (decision log, 2026-10-10).
- **The rest of `getansi.app`.** The share page needs only `/r/*`. The root
  could later redirect to, or serve, the web app now on GitHub Pages — not in
  this plan.
- **Does a household member see the other's share?** Proposed: the ⋯ menu asks
  the RPC whether a link exists, so both see *Stop sharing* without
  `recipe_share` joining a sync stream. Revisit if that round-trip is felt.
- **A sub-recipe deleted after sharing** renders as its name only, the way the
  app treats a missing component: its row is absent from the payload, so the
  line has no target and links nowhere.
- **A board page for the public page.** The board draws the app's screens;
  the share page is a web page outside the app. Phase 6 decides whether it
  gets a file of its own.
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

- [x] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [x] `ARCHITECTURE.md`'s standing table matches reality for every area touched.
- [x] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator (the UI paths CI
      can't reach), and the result recorded here.
- [ ] Tech-debt rows **added** for corners knowingly cut, and **retired** (or
      narrowed) for debt this step paid off.
- [x] New migrations or seed changes? Say in the roadmap row whether they have
      reached **cloud** yet, and append a `docs/cloud-setup.md` ledger entry
      when they do. A "pending cloud push" note nobody clears becomes a false
      claim the moment the push happens.
- [ ] `make ci` green.
