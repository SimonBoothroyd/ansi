#!/usr/bin/env bash
# Guard against the two copies of the sync security boundary diverging:
#   docker/powersync.yaml              — local Open Edition (bucket_definitions)
#   docker/powersync-cloud.streams.yaml — PowerSync Cloud (edition-3 streams)
# Same boundary, different dialects. This extracts each file's
# (table, column-list) pairs and diffs them. Run by `make docs-check`.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'EOF'
import re, sys

def extract(path):
    pairs = set()
    for line in open(path):
        m = re.search(
            r'select\s+(.+?)\s+from\s+(\w+)\s+where', line, re.IGNORECASE)
        if m:
            cols = re.sub(r'\s+', '', m.group(1).lower())
            pairs.add((m.group(2).lower(), cols))
    return pairs

local = extract('docker/powersync.yaml')
cloud = extract('docker/powersync-cloud.streams.yaml')

ok = True
for name, only in (('local (powersync.yaml)', local - cloud),
                   ('cloud (powersync-cloud.streams.yaml)', cloud - local)):
    for table, cols in sorted(only):
        print(f'  ✗ {table} [{cols}] only in {name}')
        ok = False

if not local:
    print('  ✗ no queries parsed from docker/powersync.yaml'); ok = False
if 'usda_food' in {t for t, _ in local | cloud}:
    print('  ✗ usda_food is server-only (ADR-0005) and must not be synced')
    ok = False

if ok:
    print(f'  ✓ sync boundaries match ({len(local)} tables, column lists equal)')
sys.exit(0 if ok else 1)
EOF
