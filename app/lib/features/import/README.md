# Feature: import

**Roadmap:** Step 8 — import + reconciliation (client side; see
`docs/exec-plans/active/0017-import-client.md` and `0019-import-integration.md`).

Kick off a server-side import from a URL or photos, review every extracted line
on one editable screen, then commit the resolved recipe. Matching itself is
server-side (ADR-0004); the phone never fuzzy-matches.

## Layout

```
import/
  domain/         PURE DART (no package:flutter)
    reconciliation_payload.dart  the edge function's output, mirrored in Dart
    commit_payload.dart          what the repo writes
    line_resolution.dart         per-line user decision + buildCommit (the gate)
    line_validation.dart         per-line issues + the acceptable unit set
    preview_recipe.dart          the in-memory Recipe the review renders
    import_repository.dart       ImportRepository interface + ImportSource
  data/
    remote_import_repository.dart  EdgeImportRepository — the REAL invoke
    import_repository_impl.dart    SqliteImportRepository — commit + canned
    canned_payload.dart            the fixed payload tests/the sim smoke use
    photo_intake.dart              pick → crop/rotate → paths
    import_providers.dart          importRepositoryProvider
  presentation/
    import_view.dart          the `/import` route (intake → review → commit)
    reconciliation_view.dart  the single review surface
    recon_line_card.dart      one expandable review line
    import_view_models.dart   ImportController + the validation providers
```

## Notes

- **Extraction is server-side and real.** `importRepositoryProvider` builds
  `EdgeImportRepository` (`functions.invoke('import-recipe')`, 60s timeout).
  With Supabase unconfigured it refuses the import loudly — it does NOT fall
  back to `canned_payload.dart`. That canned payload is the test/dev fixture,
  named explicitly by `SqliteImportRepository` (which the unit tests and
  `integration_test/app_test.dart` construct directly).
- **`commit` is always local**, through PowerSync, in one transaction: stubs,
  the recipe, groups, line items, correction aliases. Local tables are SQLite
  views, so every write is a plain INSERT/UPDATE — no UPSERT
  (`[[mise-powersync-views-no-upsert]]`).
- **Nothing is invented (0014).** Absent values arrive as nulls, ranges, or
  `parse_warnings`; the review screen shows all of them, and `buildCommit`
  throws unless every line is both resolved and valid.
- **One gate, one counter.** `importValidation` is the single source for the
  per-line flags, the Save button, and the header's "N to review"
  (`importOutstandingLines`).
