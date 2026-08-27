#!/usr/bin/env bash
# Fetch the PowerSync SQLite core extension for the *host* OS into app/, so
# `flutter test` can open a real (view-backed) PowerSyncDatabase on the VM.
# On a device the extension is linked in by powersync_flutter_libs; host tests
# have to load it themselves. Idempotent; git-ignored output.
set -euo pipefail
cd "$(dirname "$0")/../app"

# Pinned to the version powersync_flutter_libs links on-device, so host tests
# and the phone run the same extension. Bump both together.
VERSION="0.4.11"
BASE="https://github.com/powersync-ja/powersync-sqlite-core/releases/download/v${VERSION}"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)  asset="libpowersync_aarch64.macos.dylib"; out="libpowersync.dylib" ;;
  Darwin-x86_64) asset="libpowersync_x64.macos.dylib";     out="libpowersync.dylib" ;;
  Linux-aarch64) asset="libpowersync_aarch64.linux.so";    out="libpowersync.so" ;;
  Linux-x86_64)  asset="libpowersync_x64.linux.so";        out="libpowersync.so" ;;
  *) echo "Unsupported host $(uname -s)-$(uname -m) — see $BASE" >&2; exit 1 ;;
esac

stamp=".powersync-core-version"
if [ -f "$out" ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$VERSION" ]; then
  echo "  ✓ app/$out (v$VERSION)"
  exit 0
fi

echo "Fetching PowerSync core extension v$VERSION ($asset)…"
curl -fsSL "$BASE/$asset" -o "$out.tmp"
mv "$out.tmp" "$out"
echo "$VERSION" > "$stamp"
echo "  ✓ app/$out"
