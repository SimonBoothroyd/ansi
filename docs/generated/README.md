# Generated docs — do not hand-edit

Everything in this folder is produced by `scripts/gen_docs.sh` (`make docs`) from
a source of truth elsewhere in the repo. Editing these by hand will be
overwritten. If a generated doc is wrong, fix the generator or the source.

- `db-schema.md` — generated from `supabase/migrations/*.sql`: per table, the
  columns (from `create table` + later `alter table add column`s), nullability,
  the RLS flag, `powersync`-publication membership, and the migration that
  introduced it. Regenerate after any migration change and commit the result
  (`make docs-check` has no schema-drift check yet; the generated header lists
  the parser's limitations).
