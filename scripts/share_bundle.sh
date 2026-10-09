#!/usr/bin/env bash
# Build a recipe's share-page bundle, then prove it renders where it will run.
#
# The bundle is the app's own Dart (app/lib/features/share/page) compiled to
# JS: the `share-recipe` edge function renders the page with it and the
# browser runs the stepper and timers with it. Compiling is also the purity
# check — dart2js refuses a `package:flutter` import anywhere the page reaches.
#
# It writes two generated files beside the function, both committed:
#   share_page.js         the bundle, imported by the function to evaluate it
#   share_page_source.ts  the same source as a string, served to browsers
# CI rebuilds them and fails when the committed copies are stale.
#
#   scripts/share_bundle.sh [dir]   default: supabase/functions/share-recipe
set -euo pipefail
cd "$(dirname "$0")/.."

dir=${1:-supabase/functions/share-recipe}
case "$dir" in /*) ;; *) dir="$PWD/$dir" ;; esac
mkdir -p "$dir"
js="$dir/share_page.js"

(cd app && dart compile js -O4 --no-source-maps -o "$js" \
  lib/features/share/page/share_page_main.dart >/dev/null)
rm -f "$js.deps"

deno run --allow-read --allow-write scripts/share_bundle_smoke.ts "$js" \
  app/test/features/share/testdata/share_payload.json "$dir/share_page_source.ts"
