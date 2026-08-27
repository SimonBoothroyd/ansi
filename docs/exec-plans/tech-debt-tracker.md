# Tech debt tracker

Known, deliberate debt. Pay it down in small, continuous increments rather than
letting it compound. Add an item when you knowingly cut a corner; remove it when
you fix it.

| Added | Area | Debt | Cost if ignored | Plan |
|-------|------|------|-----------------|------|
| 2026-08-24 | scaffold | Package version floors in `app/pubspec.yaml` are caret ranges, not resolved/pinned. | Resolver drift between machines. | Run `flutter pub get` + commit `pubspec.lock` once the app boots, or pin floors. |
| 2026-08-26 | recipes/data | Repository unit tests run against plain SQLite (real tables), not PowerSync's view-backed tables — so view-only SQL failures slip through (a `saveRecipe` UPSERT bug shipped green, caught only by running the app). | Write-path bugs pass CI, fail on device. | Cover write paths with a real `PowerSyncDatabase` harness or an on-device/integration smoke test. (PowerSync local tables are views: no `INSERT … ON CONFLICT`, no subquery DELETE/UPDATE.) |
| 2026-08-26 | recipes/ui | Two Forui 0.22.3 workarounds: a custom underline tab bar (Forui's `FTabsStyle` underline needs the un-exported `FVariants`) and a custom hairline (`FDivider` bakes in a 16px margin). | Diverges from Forui; extra code to maintain. | Revisit if Forui exposes an underline `FTabsStyle` label style and zero-margin dividers. |
| 2026-08-26 | recipes | Recipe shelf-life (`keeps_for_days`, `freezable`, `freezer_days`) has DB columns + display chips but **no editor input** — deferred from step 2. | Chips never populate; step 5 can't cluster. | Add the inputs when step 5 (cook plan) needs them. |
| 2026-08-26 | books/ui | Section reorder is up/down menu items, not drag-and-drop. | Clunky for many sections. | Add a reorderable list when Forui offers a drag handle, or wrap Material's `ReorderableListView`. |
| 2026-08-26 | books | Provider-lifecycle bugs also escape the plain-SQLite repo tests: a first-cut autoDispose `LibraryActions` notifier crashed when its `ref` was used after an async dialog — caught only on the sim, not in CI. | UI-wiring bugs pass CI, fail on device. | Same fix as the view-only-SQL row: a real-DB/widget harness that drives the async mutation paths (or keep leaning on the sim smoke test). |

_When empty, keep the header — an empty tracker is a healthy signal, not a file to delete._
