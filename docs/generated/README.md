# Generated docs — do not hand-edit

Everything in this folder is produced by `scripts/gen_docs.sh` (`make docs`) from
a source of truth elsewhere in the repo. Editing these by hand will be
overwritten. If a generated doc is wrong, fix the generator or the source.

- `db-schema.md` — generated from `supabase/migrations/*.sql`: per table, the
  columns (from `create table` + later `alter table add column`s), nullability,
  the RLS flag, `powersync`-publication membership, and the migration that
  introduced it. Regenerate after any migration change and commit the result
  (nothing compares it against a *live* database; the generated header lists
  the parser's limitations).
- `unit-admission.md` — generated from
  `app/lib/features/ingredients/domain/allowed_units.dart` by
  `app/tool/gen_unit_admission.dart`, which **runs** the rule (pure Dart,
  invariant 2) rather than describing it: per default unit and macro basis,
  which units a line may be said in, with and without a stored density, plus
  the per-category imprecise-word gates. Regenerate after any change to the
  admission rule.

`make docs-check` regenerates both to temp paths and diffs them against the
committed files, so a stale one fails CI.
