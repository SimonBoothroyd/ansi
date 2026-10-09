#!/usr/bin/env bash
# Build a recipe's share-page bundle, then prove it renders where it will run.
#
# The bundle is the app's own Dart (app/lib/features/share/page) compiled to
# JS: the edge function renders the page with it and the browser runs the
# stepper and timers with it. Compiling is also the purity check — dart2js
# refuses a `package:flutter` import anywhere the page reaches.
#
#   scripts/share_bundle.sh [out]     default: app/build/share/share_page.js
set -euo pipefail
cd "$(dirname "$0")/.."

out=${1:-app/build/share/share_page.js}
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
mkdir -p "$(dirname "$out")"

(cd app && dart compile js -O4 --no-source-maps -o "$out" \
  lib/features/share/page/share_page_main.dart >/dev/null)
rm -f "$out.deps"

deno run --allow-read scripts/share_bundle_smoke.ts "$out" \
  app/test/features/share/testdata/share_payload.json
