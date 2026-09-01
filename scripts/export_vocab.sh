#!/usr/bin/env bash
# Export the TEMPLATE household's ingredient vocabulary as JSON, in exactly the
# shape `app/tool/density_audit.dart` reads. That tool re-runs the shipped
# domain derivation (allowedUnitsFor / allowedUnitChoicesFor / rankedUnitChips)
# over this dump, and **the density/admission review HTML page is built from
# its output** — so this script is the first half of one pipeline:
#
#   scripts/export_vocab.sh > vocab.json          (this file — DB → JSON)
#   dart run tool/density_audit.dart vocab.json   (JSON → enriched audit.json)
#   → the audit page renders audit.json
#
# `make vocab-audit` runs both halves into scratch/ (gitignored). Deliberately
# NOT in CI: it needs the local Supabase stack up (`make db-up`).
#
# The template household (`household.is_template`) is the curated vocab every
# real household clones at onboarding (migration 0008) — auditing it audits
# what every user actually gets. Read-only: one SELECT, no writes.
#
# Usage:
#   ./scripts/export_vocab.sh > vocab.json
#   MISE_DB_URL=postgresql://… ./scripts/export_vocab.sh   # non-default target
set -euo pipefail
cd "$(dirname "$0")/.."

DB_URL="${MISE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
DB_CONTAINER="${MISE_DB_CONTAINER:-supabase_db_mise}"

# Column notes for the reader:
#   * `basis_amount` (not `grams`) — renamed in 0010_measure_provenance.sql; it
#     is grams OR millilitres depending on the ingredient's `macros_basis`,
#     which is why the Dart side passes `basis` into every Measure.
#   * `has_macros` is a boolean, not the macros blob: the audit page cares
#     whether a row can carry honest totals (invariant 3), not the numbers.
#   * `allowed_units` is already a jsonb string array (0012_unit_admission.sql);
#     the Dart tool compares it against the freshly derived list to surface
#     drift between the SQL mirror and the domain code.
read -r -d '' QUERY <<'SQL' || true
select coalesce(jsonb_pretty(jsonb_agg(r order by r->>'canonical_name')), '[]')
from (
  select jsonb_build_object(
           'canonical_name',   i.canonical_name,
           'category',         i.category,
           'status',           i.status,
           'source',           i.source,
           'default_unit',     i.default_unit,
           'density_g_per_ml', i.density_g_per_ml,
           'macros_basis',     i.macros_basis,
           'has_macros',       (i.macros is not null),
           'allowed_units',    i.allowed_units,
           'measures', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'label',  m.label,
                      'amount', m.basis_amount,
                      'sort',   m.sort_order)
                    order by m.sort_order, m.label)
             from ingredient_measure m
             where m.ingredient_id = i.id
               and m.deleted_at is null), '[]'::jsonb)
         ) as r
  from ingredient i
  join household h on h.id = i.household_id
  where h.is_template
    and h.deleted_at is null
    and i.deleted_at is null
) s;
SQL

# psql is the happy path; not every machine has libpq installed, and the
# Supabase container always does — so fall back to it rather than making
# `brew install libpq` a prerequisite of an audit command.
if command -v psql >/dev/null 2>&1; then
  psql "$DB_URL" -tA -c "$QUERY"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$DB_CONTAINER"; then
  docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres -tA -c "$QUERY"
else
  echo "export_vocab: no psql on PATH and container '$DB_CONTAINER' is not running." >&2
  echo "  Start the local stack with 'make db-up', or set MISE_DB_URL /" >&2
  echo "  MISE_DB_CONTAINER to point somewhere else." >&2
  exit 1
fi
