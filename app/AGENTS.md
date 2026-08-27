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
    theme/           Mise design tokens mapped to Forui
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
make gen        # build_runner
make analyze    # flutter analyze + custom_lint (must be clean)
make test-app   # flutter test
make run        # flutter run with --dart-define from .env.local
```

## Running & visually iterating (iOS Simulator)

When a change needs to be *seen* (matching a design, checking a screen), iterate
on the iOS Simulator in a tight observe→edit→rebuild→screenshot loop. This
worked well for the step-2 design-fidelity pass. Requires a full **Xcode**
install (not just command-line tools): `xcode-select -p` must point at
`/Applications/Xcode.app/...`.

The loop (agents drive it with the iOS Simulator tools; humans use `flutter run`):

1. **Boot** a sim: `xcrun simctl boot "iPhone 17"` (any installed iPhone).
2. **Attach** the live panel (agent tool `control{action:"attach"}`) so the
   change is watchable.
3. **Build + launch.** iOS builds via **Swift Package Manager** (no CocoaPods /
   Podfile) — first build ~2 min, incremental ~15 s. Either `flutter run -d
   <sim-udid>` (hot reload with `r`) or `flutter build ios` then the sim
   launch tool.
4. **Observe** (`control{action:"screenshot"}`) → compare to the design →
   **edit** the Forui/theme code → rebuild → screenshot again. Repeat.

Notes:

- The app starts with **no data**. To exercise the populated screens, drive the
  editor UI (or the sim's `tap`/`text`) to create a recipe first.
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

See [`../docs/exec-plans/roadmap.md`](../docs/exec-plans/roadmap.md). Steps 1–2
are done: `lib/core/units/units.dart` (the reference example of the intended
style — read it before writing new `core/` code), the ingredient data model +
seed (`supabase/migrations/0001–0003`, `_shared/normalize.ts`), and the
single-user recipes feature (`features/recipes` + the read-only ingredient
picker in `features/ingredients`), persisting to a **local-only** PowerSync DB
(no `.connect()` until step 7). Step 3 (recipe books + user-defined sections) is
next; steps 3+ are empty feature folders awaiting work.
