#!/usr/bin/env bash
# Regenerate docs/generated/*. STUB: once migrations define domain tables, parse
# supabase/migrations/*.sql and render docs/generated/db-schema.md. For now it
# just re-stamps the placeholder so the target exists and is idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "gen_docs: db-schema generation not implemented yet (no domain tables)."
echo "          docs/generated/db-schema.md left as placeholder."
