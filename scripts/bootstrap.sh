#!/usr/bin/env bash
# One-shot dev environment check + setup. Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."

ok=1
need () {
  if command -v "$1" >/dev/null 2>&1; then
    printf "  ✓ %-10s %s\n" "$1" "$($2 2>/dev/null | head -n1)"
  else
    printf "  ✗ %-10s missing — %s\n" "$1" "$3"; ok=0
  fi
}

echo "Checking tooling…"
need flutter "flutter --version" "install Flutter 3.44+  (https://docs.flutter.dev/get-started)"
need dart    "dart --version"    "comes with Flutter"
need supabase "supabase --version" "brew install supabase/tap/supabase"
need deno    "deno --version"    "https://deno.land"
need docker  "docker --version"  "https://docs.docker.com/get-docker"

echo
if [ ! -f .env.local ]; then
  cp .env.local.template .env.local
  echo "  → created .env.local from template — fill in Supabase + PowerSync values"
else
  echo "  ✓ .env.local present"
fi

echo
if [ "$ok" -eq 1 ] && command -v flutter >/dev/null 2>&1; then
  echo "Fetching Flutter packages…"
  ( cd app && flutter pub get ) || echo "  (pub get failed — resolve versions in app/pubspec.yaml)"
  echo
  echo "NOTE: the Flutter app has no platform folders yet. To create them, run:"
  echo "      cd app && flutter create . --platforms=android,web --project-name ansi"
fi

echo
[ "$ok" -eq 1 ] && echo "Bootstrap OK." || { echo "Some tools missing — see above."; exit 1; }
