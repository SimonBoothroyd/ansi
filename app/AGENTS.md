# AGENTS.md — Flutter app

Overrides/extends the root `AGENTS.md` for everything under `app/`.

## Layout (feature-first + MVVM)

```
lib/
  main.dart          entrypoint → bootstrap()
  bootstrap.dart     ProviderScope, error handling, sync init
  app.dart           root widget: Forui theme + go_router
  core/              cross-cutting; never imports a feature
    config/          env (--dart-define reader)
    result/          Result<Failure, T>
    router/          go_router config
    sync/            PowerSync schema, database, Supabase connector
    theme/           Ansi design tokens mapped to Forui
    units/           THE UNIT SYSTEM — pure Dart, build first (spec §4)
  features/<f>/
    domain/          entities + repo interfaces — PURE DART (no package:flutter)
    data/            repo impls, DTOs, PowerSync queries
    presentation/    Views (widgets) + ViewModels (Riverpod notifiers)
  shared/            reusable widgets
```

`shared/ansi_tab_shell.dart` is the app's navigation spine: the four tabs are
branches of one `StatefulShellRoute` and the bottom bar lives there, **once**.
Two rules follow, and both are held by structural tests rather than by this
paragraph — a tab screen never draws its own footer, and a sheet or dialog opens
through `showAnsiSheet`/`showAnsiDialog` (`shared/ansi_modals.dart`), because
Forui's own functions default to the *branch* navigator and leave the bar
tappable beside the barrier. Tap-driven navigation goes through
`context.pushOnce`/`goOnce`. The whole picture, including what back does on each
screen: [`../docs/design-docs/navigation.md`](../docs/design-docs/navigation.md).

## Rules specific to the app

- **No `package:flutter` in `core/units` or any `domain/`.** CI greps for this.
  If a domain type needs a colour or an icon, it's modelled wrong.
- **ViewModels are Riverpod notifiers** (`@riverpod`), not `setState`. Views are
  `ConsumerWidget`/`HookConsumerWidget` that only read state and dispatch intents.
- **Repositories are interfaces in `domain/`**, implemented in `data/`. Tests
  override the provider with a fake — never hit Supabase in a unit test.
- **Every repository write reached from a widget goes through
  `ref.write(context, what, action)`** (`shared/write.dart`), so a write that
  throws says so instead of stopping a spinner. Enforced by
  `test/structure/no_bare_repo_write_test.dart`, whose write set is derived from
  the `domain/` interfaces. The posture it belongs to — what gets a toast, what
  gets a banner, and the seven things the app deliberately stays quiet about:
  [`../docs/design-docs/errors-and-sync-health.md`](../docs/design-docs/errors-and-sync-health.md).
- **A write after an awaited sheet, dialog or prompt goes through the handles
  captured before the await** — `ProviderScope.containerOf(context, listen:
  false)` and `hostContextOf(context)`, then `container.write(host, what,
  action)` (`shared/write.dart`). Never the widget's `ref` (every list is a
  viewport; the sheet's keyboard shrinks it and the row that opened the sheet
  can be unmounted by the time the user confirms — Riverpod 3 throws on that)
  and never a `context.mounted` bail on the write itself (it drops the action
  the user just confirmed). Enforced by
  `test/structure/no_ref_after_await_test.dart`.
- **An amount prints through `formatAmount` and is read back through
  `parseAmount`** (`core/units/number_format.dart`) — a cook says `⅔ cup`,
  not `0.67 cup`; the nine kitchen fractions print as vulgar glyphs set tight
  against the whole (`1½`), and a field that takes one still needs the text
  keyboard, because the parser also reads the `2/3` a person types and iOS's
  numeric pads carry no `/`. No file rounds its own amount; enforced by
  `test/structure/amounts_print_through_format_test.dart`, whose only other
  rule-holder is `macros_format.dart` (macros are label readings, not
  fractions). **A site with the unit in scope prints through
  `formatAmountIn(amount, unit)`** (`formatQuantityIn`, `shared/format.dart`,
  for one that may be absent): `g`, `kg`, `ml` and `l` are scale-and-jug
  readings and stay decimal — `213.5 g`, never `213½ g` — while every
  other unit keeps its fractions. The split is `Unit.isMetric`, and it is
  printing only: a grams field still parses `2/3`.
- **Never `.future` an autoDispose provider from a one-shot read** — read the
  repository instead. Nothing is listening, PowerSync's `watch` does not emit
  synchronously, and the element is disposed before its first value, so the
  future completes with a `StateError` rather than a list. Enforced by
  `test/structure/no_future_on_autodispose_test.dart`.
- **Repository tests open a real `PowerSyncDatabase`** (`test/helpers/test_db.dart`,
  built from `core/sync/schema.dart`), because local tables are SQLite *views*
  and reject SQL that plain tables accept — `INSERT … ON CONFLICT` above all.
  Setup: `make powersync-core` (fetches the core extension; `make test-app` runs
  it) and, on macOS, `brew install sqlite` — the system SQLite omits extension
  loading.
- **Phone-first layout, and one file reads the viewport.** Fixed logical-px
  spacing is the idiom here; don't derive sizes from screen dimensions ad hoc.
  `shared/ansi_layout.dart` is the **only** file under `lib/` allowed to ask how
  wide the window is: it names the three bands (`AnsiLayout` — compact < 640,
  medium 640–1023, expanded ≥ 1024, off Forui's own `FBreakpoints`) and applies
  them with `AnsiMeasure`, which centres a page in a 640 column from medium up
  and is a no-op on a phone. The measure is applied in exactly two places — the
  tab shell wraps everything it owns, the router's `_page` helper wraps every
  pushed page — so **a screen never wraps or measures itself**. Enforced by
  `test/structure/one_viewport_reader_test.dart`, which fails on
  `MediaQuery.sizeOf`, `MediaQuery.of(context).size` or `LayoutBuilder` anywhere
  else. Inset reads (`viewInsetsOf`, `paddingOf`) are not viewport reads and are
  fine. The whole picture:
  [`../docs/design-docs/wide-screen.md`](../docs/design-docs/wide-screen.md).
- **Reads come from PowerSync's local SQLite** as watched queries, surfaced as
  providers. The app does not call Supabase REST directly for synced data.
- **Run codegen after touching any `@riverpod`, `@freezed`, or JSON type:**
  `make gen` (or `make watch`).
- **Every file in `core/` or a `domain/` ships with a test** — `<file>_test.dart`
  under that feature's directory in `test/`.

## Code style — docs, comments, structure

The lint ruleset (`very_good_analysis` + the overrides in `analysis_options.yaml`)
is the source of truth for anything mechanical — formatting, import style
(relative within `lib/`), ordering. `make analyze` must be clean. This section
covers only the judgment calls a linter can't make. When a rule here gets
repeated as review feedback, promote it into a lint instead of a longer
paragraph (core belief 2).

**Doc comments (`///`) — Dart's docstring.** Use `///`, never `/** */`; dartdoc
reads them.

- We relax `public_member_api_docs` (this app isn't a published package), so
  don't write ceremony docs that restate the signature — a `///`-comment that
  says "the user's id" over `final String userId` is noise. *Do* document
  everything non-obvious: the contract, the units, the invariant it upholds, and
  how it fails. `core/units` and every `domain/` entity are the places docs earn
  their keep — a reader must know that a `stub` ingredient is excluded from
  conversions (invariant 3) without reading the body.
- Open with a one-sentence summary in the third person — "Converts a quantity to
  its canonical base." / "Returns a [Failure] when …" — then elaborate in later
  paragraphs.
- Refer to other identifiers with square brackets: `[Quantity]`, `[Result.err]`.
  The `comment_references` lint fails the build if the name doesn't resolve, so
  these stay honest.
- A `library;` directive with a leading `///` block documents a whole file; see
  `lib/core/units/units.dart` for the intended shape.

**Comments explain *why*, not *what*.** The code already says what it does.

- No narration (`// loop over the ingredients`), no history or transcript
  comments (`// changed from X`, `// was broken, now fixed`, `// per review`) —
  git holds the history, and these rot. No commented-out code; delete it.
- No plan numbers, decision letters or board versions in code comments — they
  need the chat thread to decode, and the thread is gone. Name the rule, not the
  ruling. Do not write a number a future edit will falsify.
- A good comment carries intent a future reader can't recover from the code: an
  invariant, a non-obvious edge case, a link to the spec/ADR that forced the
  shape (`// spec §4: shelf-life split is greedy, O(n log n)`).

**Both rules are held mechanically, not by review.** A doc reference is
`[Ident]` rather than `` `Ident` `` precisely so `comment_references` fails the
build when the name stops resolving — backticks stay for the things that are
not Dart identifiers in scope: SQL and column names, file paths, flags, and
stored string values like `piece` or `usda_fdc:<id>`. And
`test/structure/no_transcript_comments_test.dart` scans every comment line in
`lib/` for the transcript habits above — memory backlinks, dates, plan numbers,
review-speak, "used to"/"previously"/"changed from", board versions like
`Library v2`, and commented-out code — printing `file:line: text` for each hit.
It has no allow-list on purpose: the fix is to rewrite the comment.

**Structure — cohesion over fragmentation.**

- Prefer a few functions that read top-to-bottom over a swarm of one-line
  private helpers. Extract a helper when it earns a name — it removes real
  duplication or lifts a messy step out of the flow — not reflexively.
- Keep one function at one altitude: don't interleave the high-level steps of an
  algorithm with the bit-twiddling of one step. Pull the detail into a named
  function so the caller reads as a sequence of intentions.
- A file is a vertical slice of one idea. Don't shatter a single concept across
  a dozen micro-files, and don't let one file accumulate unrelated concepts.

## Commands

```
make gen             # build_runner
make analyze         # flutter analyze + custom_lint (must be clean)
make test-app        # flutter test (fetches the PowerSync core extension first)
make test-sim        # integration smoke on a booted iOS sim (local gate); FILE=week DEVICE=<udid> narrow it
make powersync-core  # fetch the PowerSync SQLite core extension for host tests
make run             # flutter run with --dart-define from .env.local
make ci-full         # the whole gate incl. migrations + pgTAP (needs Docker)
```

## Running & visually iterating (iOS Simulator)

When a change needs to be *seen* (matching a design, checking a screen), iterate
on the iOS Simulator in a tight observe→edit→rebuild→screenshot loop. This
worked well for the step-2 design-fidelity pass. Requires a full **Xcode**
install (not just command-line tools): `xcode-select -p` must point at
`/Applications/Xcode.app/...`.

The loop (agents drive it with the iOS Simulator tools; humans use `flutter run`):

1. **Boot** a sim: `xcrun simctl boot "iPhone 17"` (any installed iPhone).
   > One-time, after the 2026-09-01 rename: the bundle id moved
   > `com.example.mise` → `io.ansi.app`, so any sim that ran an older build
   > still has the old app installed under the old id. It is inert (nothing
   > targets it) but it looks like a duplicate "Ansi" on the home screen —
   > clear it once with
   > `xcrun simctl uninstall booted com.example.mise || true`.
2. **Attach** the live panel (agent tool `control{action:"attach"}`) so the
   change is watchable.
3. **Build + launch.** iOS builds via **Swift Package Manager** (no CocoaPods /
   Podfile) — first build ~2 min, incremental ~15 s. Either `flutter run -d
   <sim-udid>` (hot reload with `r`) or `flutter build ios` then the sim
   launch tool.
4. **Observe** (`control{action:"screenshot"}`) → compare to the design →
   **edit** the Forui/theme code → rebuild → screenshot again. Repeat.

**The smoke test.** `make test-sim` drives the real UI on a booted simulator
over the real stack with **live sync**, so it needs the local stack running
(`make db-up`) and nothing else. It is **one file per flow** under
`integration_test/` — `FILE=week` runs `week_test.dart` alone, `DEVICE=<udid>`
picks the simulator, and each file's own header says what it drives. Every file
is **self-provisioning**: it creates its own throwaway household over HTTP and
seeds what its flow needs through the app's repositories, never by driving
another flow's UI. `support/` holds the shared boot, waits, finders and drivers.
Deliberately *not* in CI — macOS runners are slow and expensive at hobby scale.

**It is a gate, not a step.** Nine files, about **27 minutes** on an unloaded
machine — so run `FILE=<name>` while you are fixing, and the whole suite once
before landing. Two things that have cost real hours here: piping the run
through `tail` reports the pipe's exit status and turns a red suite green, and
a run that is slow or hangs is usually the *host* — check for orphaned
`flutter_tester` processes and the load average before suspecting the code.

**Waits belong on what you are about to touch.** Every file syncs its household
down live, so a finder can miss simply because its row has not arrived. Use
`pumpUntilFound` on the exact widget the next line acts on — not on a
neighbour. Waiting for the ingredient's *name* and then tapping its *amount*
is how the `3 clove` flake lived in the tracker for a round: the name arrives
with the line, the amount only once the measure row does, and until then the
cell honestly reads `piece · measure pending sync`.

Notes:

- The app now opens on a **sign-in gate** (step 7). `make run` needs a Supabase
  in `.env.local` (local: `make db-up` + dev email/password; cloud: see
  [`../docs/cloud-setup.md`](../docs/cloud-setup.md)). After sign-in a
  `/connecting` screen shows until onboarding + first-sync resolve the household,
  then the Library. A fresh household starts with **no recipes** — drive the
  editor UI (or `tap`/`text`) to create one; the ingredient vocab arrives via
  sync.
- Design targets live in `docs/product-specs/board/`, one file per screen — the
  drawn reference for what a screen looks like. Re-verify the view you touch
  against the code and refresh its status date (or write its `differs:` line);
  replace a screen's frames, never append a version. Rules: `board/README.md`.
- **Fonts** must be bundled to render (Spectral / IBM Plex Mono in
  `assets/fonts/`, declared in `pubspec.yaml`); Inter comes from Forui. After
  adding a font, `flutter clean` + rebuild so the iOS bundle picks it up.
- **The web build** (no Xcode needed): `make run-web` (Chrome, with the defines
  from `.env.local`), or `flutter build web --release --base-href /` and serve
  `build/web`. Nothing to fetch first — `web/` already holds the two PowerSync
  workers and `sqlite3.wasm`, and `test/structure/web_workers_match_powersync_test.dart`
  fails if a `powersync` bump leaves them stale (`dart run powersync:setup_web`
  refreshes them). `core/sync/database.dart` branches on `kIsWeb`: there is no
  filesystem, so PowerSync persists via OPFS/IndexedDB, and it needs no
  COOP/COEP headers to do it.

  Four platform facts the app holds explicitly, each a `kIsWeb` branch with a
  test rather than a `try`/`catch` around a plugin — **a screen must not offer
  what the browser cannot do**:

  | | On the web |
  |---|---|
  | Google sign-in | returns to the page the app is served from (`features/auth/presentation/oauth_redirect.dart`), not the `io.ansi.app://` scheme. Every origin must be listed in Supabase → URL Configuration first (`../docs/cloud-setup.md` §1.6). |
  | Photo import | one "choose image files" door; pages are read through `XFile` (a blob URL, not a `dart:io` file) and downscaled through `compute`, never `Isolate.run` |
  | Crop / rotate | skipped, and the screen says so — `image_cropper` needs `WebUiSettings` + cropperjs in `web/index.html` |
  | Barcode scan | door not drawn; the typed barcode field is the path, as it always was |

  Routes are **hash URLs** (`…/#/week`) because the host is a static one that
  cannot rewrite a deep link. Hosting, the owed Pages setup and the trade it
  carries: `../docs/release.md` §6.

## Current focus

What is built and what is next lives in one place:
[`../docs/exec-plans/roadmap.md`](../docs/exec-plans/roadmap.md). Read it before
starting, and `lib/core/units/units.dart` before writing new `core/` code — it
is the reference example of the intended style.
