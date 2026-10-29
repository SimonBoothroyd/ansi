#!/usr/bin/env bash
# The simulator smoke on CI (.github/workflows/sim.yml): one integration_test
# file on an Android emulator, against the same local Supabase + PowerSync
# stack `make db-up` starts on a laptop. Two halves, so the workflow can start
# the backend early and build the app while it comes up:
#
#   scripts/sim_ci.sh backend   start Supabase + PowerSync; record the outcome
#                               in $SIM_LOGS/backend.status (run it backgrounded)
#   scripts/sim_ci.sh run       wait for that, then run $SIM_FILE on the
#                               booted emulator (inside the emulator action)
#
# Locally, use `make test-sim` — this script assumes a throwaway CI runner.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIM_LOGS:?set SIM_LOGS to a directory for logs}"
mkdir -p "$SIM_LOGS"
status_file="$SIM_LOGS/backend.status"

backend() {
  trap 'echo $? > "$status_file"' EXIT
  # No smoke file reaches an edge function, storage, realtime or the
  # dashboard (import runs over the local repository — see
  # SmokeStack.openLibraryWithLocalImport), so those images are never pulled.
  supabase start -x studio,imgproxy,edge-runtime,storage-api,realtime,logflare,vector,postgres-meta,supavisor
  # No --env-file: compose.yaml's defaults are the local stack's values.
  docker compose --file docker/compose.yaml up -d
}

collect() {
  adb exec-out screencap -p > "$SIM_LOGS/screen.png" 2>/dev/null || true
  adb logcat -d > "$SIM_LOGS/logcat.txt" 2>/dev/null || true
  docker logs ansi-powersync > "$SIM_LOGS/powersync.log" 2>&1 || true
}

run() {
  : "${SIM_FILE:?set SIM_FILE to an integration_test file name, e.g. week}"
  trap 'rc=$?; [ "$rc" -eq 0 ] || collect; exit "$rc"' EXIT

  echo "waiting for the backend…"
  for _ in $(seq 600); do [ -s "$status_file" ] && break; sleep 1; done
  if [ "$(cat "$status_file" 2>/dev/null)" != 0 ]; then
    echo "::error::the local backend did not start — see backend.log"
    cat "$SIM_LOGS/backend.log" || true
    exit 1
  fi

  # The legacy anon JWT, as `.env.local` holds it (see .env.local.template).
  anon="$(supabase status -o env | sed -nE 's/^ANON_KEY="?([^"]*)"?$/\1/p')"
  [ -n "$anon" ] || { echo "::error::no ANON_KEY in supabase status"; exit 1; }

  echo "waiting for PowerSync…"
  for _ in $(seq 120); do curl -s -o /dev/null http://127.0.0.1:8080/ && break; sleep 1; done
  curl -s -o /dev/null http://127.0.0.1:8080/ || {
    echo "::error::PowerSync is not answering on :8080"
    exit 1
  }

  # The emulator's own 127.0.0.1 is the emulator; reversing the two ports
  # makes it the runner's, so the app is built with the same URLs a laptop
  # run uses against the iOS Simulator.
  adb reverse tcp:54321 tcp:54321
  adb reverse tcp:8080 tcp:8080

  # tee, not tail: with pipefail the run's exit status is the test's.
  cd app
  flutter test "integration_test/${SIM_FILE}_test.dart" -d emulator-5554 \
    --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
    --dart-define=SUPABASE_ANON_KEY="$anon" \
    --dart-define=POWERSYNC_URL=http://127.0.0.1:8080 \
    --dart-define=SHARE_BASE_URL= \
    2>&1 | tee "$SIM_LOGS/flutter-test.log"
}

case "${1:-}" in
  backend) backend ;;
  run) run ;;
  *) echo "usage: $0 backend|run" >&2; exit 2 ;;
esac
