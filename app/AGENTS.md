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

## Rules specific to the app

- **No `package:flutter` in `core/units` or any `domain/`.** CI greps for this.
  If a domain type needs a colour or an icon, it's modelled wrong.
- **ViewModels are Riverpod notifiers** (`@riverpod`), not `setState`. Views are
  `ConsumerWidget`/`HookConsumerWidget` that only read state and dispatch intents.
- **Repositories are interfaces in `domain/`**, implemented in `data/`. Tests
  override the provider with a fake — never hit Supabase in a unit test.
- **Repository tests open a real `PowerSyncDatabase`** (`test/helpers/test_db.dart`,
  built from `core/sync/schema.dart`), because local tables are SQLite *views*
  and reject SQL that plain tables accept — `INSERT … ON CONFLICT` above all.
  Setup: `make powersync-core` (fetches the core extension; `make test-app` runs
  it) and, on macOS, `brew install sqlite` — the system SQLite omits extension
  loading.
- **Phone-first layout.** Fixed logical-px spacing is the idiom here; don't
  derive sizes from screen dimensions ad hoc. One shared max-width wrapper
  arrives with the web step (roadmap step 10) and is the only place that reads
  the viewport.
- **Reads come from PowerSync's local SQLite** as watched queries, surfaced as
  providers. The app does not call Supabase REST directly for synced data.
- **Run codegen after touching any `@riverpod`, `@freezed`, or JSON type:**
  `make gen` (or `make watch`).
- **Every file in `core/` or a `domain/` ships with a test** in the mirrored
  `test/` path.

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
- A good comment carries intent a future reader can't recover from the code: an
  invariant, a non-obvious edge case, a link to the spec/ADR that forced the
  shape (`// spec §4: shelf-life split is greedy, O(n log n)`).

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
make test-sim        # integration smoke on a booted iOS sim (local gate)
make powersync-core  # fetch the PowerSync SQLite core extension for host tests
make run             # flutter run with --dart-define from .env.local
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

**The smoke test.** `make test-sim` runs `integration_test/app_test.dart`
against whichever simulator is booted (boot one first — step 1 above), driving
the real UI over the real step-7 stack with **live sync**. It needs the **local
stack running** (`make db-up`) and nothing else: the suite is **auth-aware and
self-provisioning** (it creates a throwaway two-person household over HTTP,
then signs in through the real gate). Three scenarios: auth → library
(create/edit a recipe incl. method steps, jsonb + child-diff round-trips) →
week/cook/shop. It is deliberately *not* in CI (macOS runners are slow and
expensive at hobby scale).

Notes:

- The app now opens on a **sign-in gate** (step 7). `make run` needs a Supabase
  in `.env.local` (local: `make db-up` + dev email/password; cloud: see
  [`../docs/cloud-setup.md`](../docs/cloud-setup.md)). After sign-in a
  `/connecting` screen shows until onboarding + first-sync resolve the household,
  then the Library. A fresh household starts with **no recipes** — drive the
  editor UI (or `tap`/`text`) to create one; the ingredient vocab arrives via
  sync.
- Design targets for the recipe screens live in `docs/product-specs/`
  (`design-board.html`); the step-2 mockups were captured under `scratch/`.
- **Fonts** must be bundled to render (Spectral / IBM Plex Mono in
  `assets/fonts/`, declared in `pubspec.yaml`); Inter comes from Forui. After
  adding a font, `flutter clean` + rebuild so the iOS bundle picks it up.
- **Web fallback** (no Xcode needed): `dart run powersync:setup_web` once (fetches
  the sqlite3 wasm + workers into `web/`), then `flutter run -d web-server` and
  open it in a browser. `core/sync/database.dart` already branches on `kIsWeb`
  (web has no filesystem — PowerSync persists via OPFS/IndexedDB).

## Current focus

What is built and what is next lives in one place:
[`../docs/exec-plans/roadmap.md`](../docs/exec-plans/roadmap.md). Read it before
starting, and `lib/core/units/units.dart` before writing new `core/` code — it
is the reference example of the intended style.
