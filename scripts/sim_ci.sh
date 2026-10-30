#!/usr/bin/env bash
# The simulator smoke on CI (.github/workflows/sim.yml): one integration_test
# file on an Android emulator, against the same local Supabase + PowerSync
# stack `make db-up` starts on a laptop. Three parts, so the backend starts,
# the app builds and the emulator boots all at once:
#
#   scripts/sim_ci.sh backend   start Supabase + PowerSync; record the outcome
#                               in $SIM_LOGS/backend.status (run it backgrounded)
#   scripts/sim_ci.sh build     build $SIM_FILE's debug APK; record the outcome
#                               in $SIM_LOGS/build.status (run it backgrounded)
#   scripts/sim_ci.sh run       wait for both, then run $SIM_FILE on the
#                               booted emulator (inside the emulator action)
#
# Locally, use `make test-sim` — this script assumes a throwaway CI runner.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIM_LOGS:?set SIM_LOGS to a directory for logs}"
mkdir -p "$SIM_LOGS"
status_file="$SIM_LOGS/backend.status"
build_status="$SIM_LOGS/build.status"

# The stack's images come from GitHub's registry, where Supabase mirrors
# them (the CLI's own fallback list names it). Its default, public.ecr.aws,
# rate-limits nine jobs pulling at once, and once refused one outright
# ("toomanyrequests: Data limit exceeded"), failing the run.
export SUPABASE_INTERNAL_IMAGE_REGISTRY=ghcr.io

# The URLs the app is built with. The emulator reaches the runner's ports
# through adb reverse, so they are the ones a laptop run uses against the
# iOS Simulator.
set_defines() { # $1 = anon key
  defines=(
    --dart-define=SUPABASE_URL=http://127.0.0.1:54321
    "--dart-define=SUPABASE_ANON_KEY=$1"
    --dart-define=POWERSYNC_URL=http://127.0.0.1:8080
    --dart-define=SHARE_BASE_URL=
  )
}

# Prefixes each line with the UTC time, so a slow phase can be found.
stamp() { while IFS= read -r line; do printf '%s %s\n' "$(date -u +%T)" "$line"; done; }

backend() {
  trap 'echo $? > "$status_file"' EXIT
  echo "$(date -u +%T) supabase start"
  supabase start -x studio,imgproxy,edge-runtime,storage-api,realtime,logflare,vector,postgres-meta,supavisor 2>&1 | stamp
  # No --env-file: compose.yaml's defaults are the local stack's values.
  docker compose --file docker/compose.yaml up -d 2>&1 | stamp
  echo "$(date -u +%T) backend done"
}

build() {
  : "${SIM_FILE:?set SIM_FILE to an integration_test file name, e.g. week}"
  trap 'echo $? > "$build_status"' EXIT
  cd app
  # This warms Gradle — the plugins' Kotlin and Java, dexing, the NDK — so
  # flutter test's build is only its Dart. That compile cannot be shared:
  # flutter test builds a generated listener.dart in a fresh temp directory
  # around the test file, never the file itself, so no build made
  # beforehand matches it. The defines need not match either.
  flutter build apk --debug --target-platform android-x64 \
    --target "integration_test/${SIM_FILE}_test.dart"
  echo "$(date -u +%T) build done"
}

collect() {
  adb logcat -d > "$SIM_LOGS/logcat.txt" 2>/dev/null || true
  docker logs ansi-powersync > "$SIM_LOGS/powersync.log" 2>&1 || true
}

run() {
  : "${SIM_FILE:?set SIM_FILE to an integration_test file name, e.g. week}"
  shooter=""
  trap 'rc=$?; [ -z "$shooter" ] || kill "$shooter" 2>/dev/null; [ "$rc" -eq 0 ] || collect; exit "$rc"' EXIT

  echo "waiting for the backend…"
  for _ in $(seq 600); do [ -s "$status_file" ] && break; sleep 1; done
  echo "::group::the local backend"
  cat "$SIM_LOGS/backend.log" || true
  echo "::endgroup::"
  if [ "$(cat "$status_file" 2>/dev/null)" != 0 ]; then
    echo "::error::the local backend did not start — see the backend group above"
    exit 1
  fi

  # The legacy anon JWT, as `.env.local` holds it (see .env.local.template).
  anon="$(supabase status -o env | sed -nE 's/^ANON_KEY="?([^"]*)"?$/\1/p')"
  [ -n "$anon" ] || { echo "::error::no ANON_KEY in supabase status"; exit 1; }

  echo "waiting for the build…"
  for _ in $(seq 1200); do [ -s "$build_status" ] && break; sleep 1; done
  echo "::group::the debug build"
  cat "$SIM_LOGS/build.log" || true
  echo "::endgroup::"
  if [ "$(cat "$build_status" 2>/dev/null)" != 0 ]; then
    echo "::error::the debug build failed — see the build group above"
    exit 1
  fi

  echo "waiting for PowerSync…"
  for _ in $(seq 120); do curl -s -o /dev/null http://127.0.0.1:8080/ && break; sleep 1; done
  curl -s -o /dev/null http://127.0.0.1:8080/ || {
    echo "::error::PowerSync is not answering on :8080"
    exit 1
  }

  # The emulator's own 127.0.0.1 is the emulator; reversing the two ports
  # makes it the runner's (see set_defines).
  adb reverse tcp:54321 tcp:54321
  adb reverse tcp:8080 tcp:8080

  # The iOS Simulator the suite is written on types through a hardware
  # keyboard, so no on-screen keyboard ever covers the form. Android's does —
  # it took the taps meant for the shelf-life stepper and the ingredient
  # form's Save. With every input method disabled the emulator draws none;
  # enterText still types, since it talks to the framework, not a keyboard.
  for ime in $(adb shell ime list -s | tr -d '\r'); do
    adb shell pm disable-user --user 0 "${ime%%/*}" > /dev/null ||
      echo "::warning::could not disable the input method $ime"
  done
  echo "input methods left enabled: [$(adb shell ime list -s | tr -d '\r')]"

  # The app has exited by the time the test run returns, so a screenshot taken
  # then shows the launcher. Shoot every 5 s while it runs instead, named by
  # UTC time so a failure's log timestamp picks its frame, and keep the last
  # five minutes: a file can fail early and run on through later tests.
  mkdir -p "$SIM_LOGS/screens"
  (
    while sleep 5; do
      shot="$SIM_LOGS/screens/$(date -u +%Y%m%dT%H%M%S).png"
      adb exec-out screencap -p > "$shot.tmp" 2>/dev/null && mv "$shot.tmp" "$shot"
      ls -1 "$SIM_LOGS/screens"/*.png 2>/dev/null | head -n -60 | xargs -r rm -f
    done
  ) &
  shooter=$!

  # An app that never becomes active hangs flutter test with no output at all
  # (once here: sixteen minutes after install, not even setUpAll). An "isn't
  # responding" dialog is the usual cause on a loaded emulator; the error
  # dialogs are hidden, and a hang is bounded so it fails with the screens
  # and logcat instead of eating the job.
  adb shell settings put global hide_error_dialogs 1

  # tee, not tail: with pipefail the run's exit status is the test's.
  set_defines "$anon"
  cd app
  local rc=0
  timeout "${SIM_TEST_TIMEOUT:-15m}" flutter test "integration_test/${SIM_FILE}_test.dart" \
    -d emulator-5554 "${defines[@]}" 2>&1 | tee "$SIM_LOGS/flutter-test.log" || rc=$?
  if [ "$rc" -eq 124 ]; then
    echo "::error::flutter test made no end in ${SIM_TEST_TIMEOUT:-15m} — see screens/ in the sim-${SIM_FILE} artifact"
  fi
  return "$rc"
}

case "${1:-}" in
  backend) backend ;;
  build) build ;;
  run) run ;;
  *) echo "usage: $0 backend|build|run" >&2; exit 2 ;;
esac
