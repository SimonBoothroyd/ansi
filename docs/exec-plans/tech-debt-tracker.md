# Tech debt tracker

Known, deliberate debt. Pay it down in small, continuous increments rather than
letting it compound. Add an item when you knowingly cut a corner; remove it when
you fix it.

| Added | Area | Debt | Cost if ignored | Plan |
|-------|------|------|-----------------|------|
| 2026-08-24 | scaffold | Version floors in `app/pubspec.yaml` are caret ranges. `pubspec.lock` **is** committed now, so resolution is pinned in practice. | Loosened floors could drift on a `pub upgrade`. | Tighten floors when a resolve conflict actually shows; the lock carries it until then. |
| 2026-08-26 | recipes/ui | Two Forui 0.22.3 workarounds: a custom underline tab bar (Forui's `FTabsStyle` underline needs the un-exported `FVariants`) and a custom hairline (`FDivider` bakes in a 16px margin). | Diverges from Forui; extra code to maintain. | Revisit if Forui exposes an underline `FTabsStyle` label style and zero-margin dividers. |
| 2026-08-26 | recipes | Recipe shelf-life (`keeps_for_days`, `freezable`, `freezer_days`) has DB columns + display chips but **no editor input** — deferred from step 2. | Chips never populate; step 5 can't cluster. | Add the inputs when step 5 (cook plan) needs them. |
| 2026-08-26 | books/ui | Section reorder is up/down menu items, not drag-and-drop. | Clunky for many sections. | Add a reorderable list when Forui offers a drag handle, or wrap Material's `ReorderableListView`. |
| 2026-08-26 | books | Provider-lifecycle bugs (the `LibraryActions` crash: `ref` used after an async dialog) are covered by exactly one path — the `make test-sim` smoke, which is local-only. Every other async mutation path is unguarded. | A lifecycle bug on an uncovered path still reaches the phone. | Widen the smoke, or add widget tests over the real-DB harness for each mutation flow. Standing rule meanwhile: mutations go through keep-alive repo providers. |
| 2026-08-27 | app/test | Host repo tests need an extension-capable SQLite; macOS's system build omits extension loading, so `test_db.dart` falls back to Homebrew's `libsqlite3.dylib`. The Linux/CI path (`libsqlite3-dev` + the fetched extension) has not run yet. | A machine without `brew install sqlite` can't run `make test-app`; CI may need a tweak on its first run. | Confirm on the next CI run; revisit if the sqlite3 package ever ships a bundled host library. |
| 2026-08-27 | app/ui | Opening a Forui dialog with the semantics tree live trips a framework assertion (`node.isMergedIntoParent`), so `integration_test/app_test.dart` filters that one assertion. Reproduces in a plain widget test with `ensureSemantics()`. | Real assistive-tech users may hit a malformed semantics tree; the filter could mask a future regression. | Re-check when forui moves past 0.22.x; drop the filter if it's fixed, otherwise report upstream. |

_When empty, keep the header — an empty tracker is a healthy signal, not a file to delete._
