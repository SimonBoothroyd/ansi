# Exec plan: Polish pass — ten owner-raised fronts, run as parallel lanes

- **Status:** active — build phase (2026-09-02). All seven board sections
  signed off; six build lanes running in worktrees (search · piece · nav
  shell · library · week · editor); errors staged after library/week land.
  Quickfix lane already on main.
- **Owner:** Simon (design partner, rules on every decision) + Claude (orchestrator; lanes are sub-agents)
- **Roadmap step:** post-8.6 polish; absorbs row 8.7 (piece↔measure) and adds rows for the rest
- **Created:** 2026-09-02

## Goal

The app is feature-complete on paper and rough in the hand. The owner raised ten
fronts on 2026-09-02, from a real-device field test. Each is tackled by one lane;
the lanes run in parallel; **every design goes through the design board and gets
an owner sign-off before it is built**. The board is kept current by the
orchestrator: lanes draft fragments in scratch, the orchestrator merges them into
`docs/product-specs/design-board.html` as *proposed* sections, the owner rules,
the sections lock.

Observable done: each front below is either shipped (board locked, roadmap row,
tests, sim scenario where a feature) or deliberately deferred in the tracker.

## The ten fronts → lanes

| # | Owner's front | Lane | Kind | Design needed? |
|---|---|---|---|---|
| 1 | Search/matching is inconsistent ("almonds"/"almond"/"almnd") | **search** | audit + contract | contract doc; a small board frame if a "did you mean" band is proposed |
| 2 | `piece` vs specific measures (avocado) — piece is a fallback | **piece** | rule design (= roadmap 8.7) | yes — review card + chip row |
| 3 | The tab bar is janky (one bar per tab, sliding transitions) | **nav** | architecture | yes — "Navigation · v2" |
| 4 | Library unfit: no rename/collapse/search; `+` overloaded; multi-open pages | **library** (+ nav for the guard) | redesign | yes — "Library · v2" |
| 5 | Tapping a recipe on Week/Cook does nothing | **quickfix** | bug | no |
| 6 | Errors are swallowed silently | **errors** | audit + posture | yes — one section: toast / banner / sync health |
| 7 | Android swipe-right minimises instead of going back | **nav** | architecture | folded into "Navigation · v2" |
| 8 | Closing the import modal leaves the `+` popover open | **quickfix** | bug | no |
| 9 | Week plan redesign — presentation vs edit, macros, multi-week (design for, defer) | **week** | redesign | yes — "Week · v2" |
| 10 | Recipe editor with chips; substitutions (meatballs over sausages) | **editor** | redesign | yes — "Recipe editor · v2" |

Lane outputs land in the session scratchpad (`lanes/<lane>-*.{md,html}`) and are
merged here and into the board by the orchestrator. Design lanes do not touch
the repo; the quickfix lane works in an isolated worktree and lands three
separate commits (A: week/cook tap → recipe; B: guarded `pushOnce` + a
structural test; C: popovers close before pushing).

## Acceptance criteria

- [ ] Every design front has a board section, owner-ruled (D-numbers recorded
      below), and locked before its build lane starts.
- [ ] Search: one tiered contract shared by the ingredient picker, the recipe
      picker and the line-target picker; guard values chosen against the real
      vocab with numbers, not opinions; shared vectors pin Dart and TS.
- [ ] Every code change lands with a test; `make ci` green; `make test-sim`
      re-driven for the tab shell, the Library, the Week screen.
- [ ] Docs updated in the same PRs: product-spec §5, roadmap rows, tracker rows
      added and retired.

## Approach

1. **Triage** (done 2026-09-02, orchestrator): read the map, the board, the
   router, the search code, the library and week views; established the causes
   of 5, 8, the multi-open pages, and the sliding bar (each screen owns its own
   bar and tabs switch by page replacement).
2. **Fan-out** (2026-09-02): seven design/research lanes + one code lane, all
   parallel. Each design lane returns decisions (options + one recommendation),
   a board fragment reusing the board's own CSS, and an implementation sketch.
3. **Merge + consult**: the orchestrator merges fragments into the board as
   proposed sections, reconciles cross-lane seams (nav ↔ library header; errors ↔
   the account surface; week ↔ the recipe tap), and puts the decisions to the
   owner in one pass.
4. **Rulings → build lanes**: each locked section becomes a build lane
   (worktree, tests, its own commits), in dependency order: nav shell first (the
   Library and Week screens sit inside it), then library / week / editor /
   piece / search / errors sweep.
5. **Close-out**: roadmap rows, QUALITY grades, tracker reconciliation, sim
   scenarios, board tags flipped to locked · shipped.

## Lane outputs (design phase) — merged into the board as proposed sections

Each lane returned a decision set (options + one recommendation), a board
fragment (merged, `<!-- lane:<name>:start/end -->` markers in the board) and an
implementation sketch. The full decision sets live in the session scratchpad
until the owner rules; the rulings are recorded here.

| Lane | Board section | Recommendation in one line | Owner rules on |
|---|---|---|---|
| search | "Search & matching · v1" | One `searchRank` with three tiers (exact → every-token prefix, raw or singular → typo-tolerant, per-token guard: min length 5 alone / 3 beside a spelled neighbour, OSA distance, floor 0.75), shared by all three pickers; typo hits in a labelled "did you mean" band, never mixed in; the server matcher unchanged; diacritics folded at the root. Measured on the real 308-row vocab: 29/30 hand typos found (was 2/30), 19/19 must-stay-quiet probes silent. | D1 single-word typo tolerance · D2 band vs mixed · D3 recipe pickers get all tiers · D4 server unchanged · D5 fold diacritics · D6 import seam tiers 0/1 only |
| piece | "Piece → measure · 8.7" | Resolve a `piece` line at review, visibly (`1 avocado · 201 g · inferred`, one-tap revert, never blocks Save): printed size word → self-named measure (medium tie-break) → sole measure → otherwise decline. `piece` demoted below measures everywhere, never hidden. Import resolves; the editor only pre-selects. Review-only mark, no migration, no backfill. Macros say "1 line needs a weight". | D1 depth (coupled with D5) · D2 no-size-word tie-break · D3 demote vs hide · D4 editor leg · D6 wording |
| library | "Library · v2" | `＋` = New recipe · Import only; a `⋯` beside it holds Ingredients (badge + dot while stubs exist) · New book · Reorder · Sign out. Pinned top search replaces the tree with flat rows carrying Book · Section (titles only). Books fold from a chevron, per device. Book `⋯`: rename · new section · move · delete (refused with a count + "Move them to…"; last book refused). Row gains a ★ that only reports. Zero migrations. | D1 `/account` now or later · D2 ingredient search later · D4 "Move them to…" in scope, detail screen deferred · D6 the ★ |
| week | "Week · v2" | One screen, presentation resting, `Edit`/`Done` in the header; tap = recipe in read, entry sheet in edit. Header title is the week (`‹ This week · 31 Aug ›`, menu with copy-last-week); chevrons designed, build deferred. Day cards gain cook markers (read back from `buildCookPlan`) and a four-cell macro line; a week band closes the list. Macro rule at every scope: sum what resolved, state the denominator, name every exclusion; nothing resolved ⇒ no number. Empty week is a normal state (the blank page goes). Lens dims instead of filtering. | D1 one screen · D3 Cook/Shop follow the viewed week (+ `shopping_list_entry.week_start_date`) · D4 partial-with-denominator vs blank · D5b the "never swap the screen out" house rule · D8 dim vs filter |
| nav | "Navigation · v2" | Four tabs become `StatefulShellRoute` branches under ONE persistent bar in a shell; the tab switch is a 120 ms opacity-only cross-fade of the content (bar held still; the selected item's own colour tick is the visible motion — today the label never highlights, a bug). Pushed pages (`/recipes/*`, `/import`, `/ingredients*`) stay top-level and cover the bar, keeping each platform's native push (Cupertino slide + edge-swipe-back on iOS, predictive back on Android once the manifest flag lands). Three post-action `context.go` calls flatten the stack and kill back on those pages; they become replacements. Sheets and dialogs must use the root navigator under a shell. Tab state is preserved. | D3 back on a non-Library tab → Library then exit (Android convention) vs keep exiting · D5 guard semantics (the shipped same-location dedupe vs a 400 ms latch that also drops a different target) · D6 a shared menu-item helper vs the shipped per-item hide |
| errors | "Errors & sync health · v1" | 83 error paths, 11 honest; 37 of 38 UI writes have no failure surface; nothing reads PowerSync's status. Posture: a toast reports an act (failed write, with Retry), a banner reports a state (sync stalled past a threshold; an upload refused and dropped — today silently discarded beside a "never let it be silent" comment); offline-and-queued is never either. Every widget write goes through one `ref.write(context, what, action)` helper held by a structural test; one shared error state with a mapped reason and Retry; four load-bearing `?? const []` sites (incl. the one that turns a delete refusal into a delete) become real error states; a rate-limited "Something went wrong · Copy details" toast behind a `CrashSink` seam, no vendor. Sync health as a quiet line in the Library `⋯` menu. | D1 the rule · D2 the words · D3 the stall threshold (5 min?) and whether `/account` is built now · D4 test-only vs custom_lint · D6 which four providers |
| editor | "Recipe editor · v2 (chips)" | Step cards; a chip is a highlighted word inside a real editable sentence (a custom controller's `buildTextSpan`, Forui's managed control takes it). `@` or `＋ ingredient` opens a picker over this recipe's own lines with a footer that adds a line and the chip in one act. Timers from a stepper sheet, never parsed. Convert-to-plain-text is the one-way exit. The editor writes `methodSteps` for every recipe. Substitution: the identity cell becomes tappable (keeps the line id) and the chip's printed word is retired for the new name, flagged and revertible. | D1 inline chips vs chip tray · D3 relabel on substitution vs keep the printed word · D2 footer add-line welcome |

Found in passing (owed a tracker row or a fix): the library tree query drops
`favorite` (same class as the 8.6 yield miss); the two recipe-title searches
use different code; `noneDedupeKey` on the server has no caller; the import
re-match seam cannot see aliases.

## Decision log

Append-only.

- 2026-09-02 — Lanes are parallel but the board is serial: only the
  orchestrator edits `design-board.html`; lanes draft fragments in scratch.
  Why: one file, eight writers, no merge tool — and the owner reviews one board.
- 2026-09-02 — The quickfix lane starts before any sign-off. Why: items 5 and 8
  and the double-push are unambiguous bugs with no design choice in them; they
  are reversible and the owner asked for parallelism.
- 2026-09-02 — Item 7 (back gesture) is folded into the nav lane rather than
  fixed in isolation. Why: on a tab root there is no history to go back to; the
  answer depends on the tab-shell decision (D3 in the nav lane).
- 2026-09-02 — **Quickfix lane landed on main** (rebased from its worktree):
  `74c233b` Week dish rows and Cook cards open their recipe · `90741d5`
  `context.pushOnce`/`goOnce` in `shared/guarded_navigation.dart` (same-location
  dedupe against the router's top location, which go_router 16 writes
  synchronously) + a structural test that fails on any bare tap-driven
  `context.push`/`go` under presentation or shared, with the three post-action
  `go` calls named as exceptions · `2db7cd2` every `FPopoverMenu` moves to
  `menuBuilder` and hides itself before it navigates, opens a dialog or writes
  · `0294a9e` the 8.6 tap sites the rebase surfaced (line-target picker,
  Used-in rows, sub-recipe chip, set-yield doors) swept into the guard. The
  Cook card's title tap rides a new optional `onTitleTap` on the shared card so
  component cards open their sub-recipe too. `make analyze` clean, 1031 host
  tests green. **Not yet run:** `make test-sim` — deferred to the nav-shell
  landing so the tab paths are re-driven once, not twice.
- 2026-09-02 — The nav lane's D5 recommends a stricter guard (a 400 ms latch
  that also drops a *different* target mid-transition) than the shipped
  same-location dedupe, and a shared menu-item helper (D6) over the shipped
  per-item hide. Both are put to the owner as choices; the shipped forms are
  the floor either way.
- 2026-09-02 — The launcher-icon working-tree changes (`flutter_launcher_icons`,
  the mipmap/appiconset PNGs, `pubspec.yaml`) are untouched by every lane. Why:
  they predate this pass and belong to the owner; confirmed with the owner
  before anything lands over them.

## Notes / open questions

Owner answers, 2026-09-02 (the first consult):

- The dangling "1." was a typo — ten fronts, not eleven.
- Item 7 (swipe minimises the app): the owner cannot reproduce it and thinks
  it was misremembered. Kept as a *rule* in the nav design (what back does on
  each screen state), not chased as a bug.
- Item 3: "swiping" meant the sliding page transition seen when tapping a tab,
  not a swipe between tabs. The bar: "some kind of animation is nice, but it
  needs to feel super clean, as if Apple had native-designed it — not many
  copies of the nav bar, not pages always transitioning the same direction."
- Item 9: "plan week" is the blank-week page. The owner suspects the app now
  keeps every view populated; the week lane verifies and designs the empty
  week as a normal state with the full context.
- The launcher-icon working-tree changes are the owner's, in progress — no lane
  touches them.
- Build order agreed: navigation shell first, then the rest.

Owner rulings, 2026-09-02 (the second consult, on the merged board):

- **Library · v2 — signed off** ("looks awesome"); D1–D8 as recommended
  (`⋯` beside `＋`, no `/account` yet; titles-only search; per-device fold;
  book `⋯` with the refused delete + "Move them to…"; the reporting ★).
  Board tag flipped to signed off; build waits on the nav shell.
- **Piece → measure — rejected as drawn.** Owner: piece is the fallback when
  no appropriate measure exists; where one does (clove, medium…) piece must
  not be offered at all, otherwise we are guessing what a piece means. Not
  rule-based: the seeded vocab is curated by hand, and the user decides for
  new ingredients. **Redrawn** as an *admission* fact: `piece` lives in the
  existing explicit `allowed_units` list and is absent wherever a piece-type
  measure exists; no new column, no runtime cascade, no `inferred` mark.
  Import falls through the shipped not-allowed-unit chips (one measure ⇒
  preselected, several ⇒ the user picks; Save gated as today). New
  ingredients keep `piece` until the user adds a measure, when the manager
  asks whether to keep offering it (default no). The seed is curated by hand
  in [0022-piece-curation.md](./0022-piece-curation.md): 142 seeded
  ingredients with measures, drafted 119 drop · 4 keep · 19 for the owner's
  call; lands as `curation_overrides.jsonl` lines → reseed, pinned by pgTAP,
  never a backfill. **Ticked 2026-09-02 — signed off.** A/B accepted as
  drafted; C: broccoli's bunch is the whole (relabel), dill pickle → spear,
  ginger gains a `piece, 2 cm` (weight `seed:typical`, awaiting the owner's
  number), kombu → strip; D: everything dropped (asparagus, basil, cauliflower,
  celery, cherry tomato — its `cherry` measure relabelled, density + macros
  verified present — iceberg, mint, multigrain bread, cabbage, rhubarb), the
  unnamed rows by analogy. Net: no seeded ingredient with a measure keeps
  `piece`. **Landed on main 2026-09-02** (`4753a0c`…`6ffd425`, rebased over
  8.6's sub-recipe macro reasons — the two reason sets now coexist in
  `RecipeMacroSummary`/`incompleteNote`): 142 curation lines (66 no-ops kept
  as the record), broccoli `whole`, cherry tomato's borrowed measure dropped,
  ginger `piece, 1 inch` 12 g typical, the manager's stop-offering-piece
  prompt, the import fall-through, the chip row, ADR-0010, 12 new pgTAP
  assertions (146/146), 1053 app tests, 153 deno. Finding: every seeded
  count-default row carries a measure, so the template admits `piece`
  nowhere — the fallback exists only for household-created rows. **Cloud:**
  needs the template-vocab reseed (`docs/release.md` §4 — `db push` does not
  reseed). **Sim:** scenarios 4 and 5 to re-drive.
- **Recipe editor — liked** (one card per step). Owner asks: tap a chip or a
  timer to edit it; select text → "To ingredient / To timer" in the selection
  menu, prefilled by a match over the recipe's own lines; the `@` is not
  understood (dropped); the first-mention amount rule needs explaining or
  simplifying. **Revised:** tap-to-edit is the primary interaction (a chip
  sheet with Points at · Word · Show the amount here · Remove chip, keeps the
  word; a seeded timer sheet with Remove timer); selection → "To ingredient /
  To timer" in the platform selection toolbar (Forui's `FTextField.multiline`
  exposes `contextMenuBuilder`; an overlay pill is the fallback), prefilled
  by a word-prefix match over the recipe's own lines; the `@` is dropped;
  new **D9** states the amount rule in one sentence ("the first time a step
  calls for something, its chip shows the amount; after that it just names
  it") with a per-chip switch, and proposes renaming `StepMention` →
  `ChipAmountRule`. D1 and D3 kept. **Signed off 2026-09-02 ("lgtm");
  build lane started on the nav PoC base.**
- **Week · v2 — liked**, one change: the cook marker ("from Monday's batch",
  "cooks today") sits under the recipe name, not beside it. Lane revising.
- **Navigation · v2 — liked**, pending a short live PoC on the simulator
  before committing. **PoC built** on a worktree branch (commit `d499a94`,
  not merged): `StatefulShellRoute` with one persistent bar in a new
  `shared/ansi_tab_shell.dart`, a 120 ms opacity-only content cross-fade
  (`kTabFade`, set to zero for the hard-cut comparison), the label-highlight
  bug fixed, pushed pages full-screen over the bar with the native push and
  edge-swipe-back. Analyze clean, 1031 tests. Left for the full build: the
  sheet/dialog root-navigator sweep (only the Week add-meal sheets and the
  Library prompt done), the Android predictive-back manifest flag, D3's back
  rule, `make test-sim`. Running on the iPhone 17 sim for the owner, signed
  in as a throwaway local household provisioned by `scripts/smoke_auth.sh`.
  **Owner tried it: "nice!" — signed off 2026-09-02.** Full build starts from
  the PoC branch; the Library and Week builds branch off the same base.
- **Errors — signed off** as recommended, plus **D9** (owner): the Shopping
  list carries its own sync status line under the header — `Synced · just
  now` / `Sending…` / `2 ticks waiting` / amber `Ticks aren't reaching the
  other phone · since 14:02` with *Try now* — off the same sync-health
  provider as the Library `⋯` line, so the two cannot disagree; no per-item
  pending marks. Assumed unless overruled: the 5-minute stall threshold,
  structural test only (no custom_lint package yet), the four named
  load-bearing providers.
- **Week — signed off** as recommended with the owner's change: the cook
  marker sits on a second line under the dish title, not in a trailing
  column. Assumed unless overruled: D3 (Cook/Shop follow the viewed week, so
  `shopping_list_entry` gains `week_start_date`), D4 partial totals with a
  stated denominator and named exclusions, D8 the lens dims.
- **Search — signed off 2026-09-02 with the floor at 4** ("i'm fine matching
  nion... dropping to 4 is fine"; the "nion must stay silent" sentence was the
  tracker's, not the owner's, and is withdrawn). D1–D6 otherwise as
  recommended. Re-measured at floor 4 on the real 308-row vocab: 29/30 hand
  typos at rank 1, 93% right-family@1 systematically (80% at floor 5), 0%
  silent (was 16%), 7% near-sibling wrong-family@1 with the intended row at
  rank 2–3; `aoli` → Romesco Aioli 0.80. Accepted cost, owned by the band's
  header: `nion`→Onion, `pear`→Peach, `beef`→Beets, `pork`→Portobello,
  `lamb`→Burger Buns. Three-letter mistypes (`rce`, `oyl`) stay silent. Two
  existing tests flip (`ingredient_repository_test.dart:124` and `:168`).
  Board section marked signed off.
- Earlier note, kept for the record: the owner wanted to "vibe" first. Probed the owner's own case with
  the lane's scripts against the real vocab and a title list: `aoli` is four
  letters, so under the proposed floor of 5 it is NOT guessed; at a floor of
  4 it finds *Romesco Aioli* (0.80) among titles — and `nion` finds *Onion*
  (0.80), which the earlier ruling wanted silent. With guesses confined to a
  labelled "did you mean" band, a floor of 4 is the recall-leaning choice put
  to the owner. Also clarified for the owner: this is the phone's search
  boxes (ingredient picker, recipe pickers), not the server's import matcher.

## Step-done checklist

- [ ] Roadmap rows updated (8.7 absorbed; new rows for nav / library / week /
      editor / search / errors).
- [ ] `docs/QUALITY.md` grades for every area touched.
- [ ] `app/AGENTS.md` "Current focus" still true.
- [ ] `make test-sim` re-driven on a booted simulator; result recorded here.
- [ ] Tech-debt rows added and retired.
- [ ] No new migrations expected; if one appears, the cloud ledger gets an entry.
- [ ] `make ci` green.
