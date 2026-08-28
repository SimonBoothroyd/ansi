#!/usr/bin/env bash
# Regenerate docs/generated/* from sources of truth (`make docs`).
# Currently: docs/generated/db-schema.md from supabase/migrations/*.sql.
# Deliberately boring: python3 stdlib only, a ~90% parse of our own migration
# style (limitations are stated in the generated header).
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import re
from pathlib import Path

MIGRATIONS = sorted(Path("supabase/migrations").glob("*.sql"))
OUT = Path("docs/generated/db-schema.md")

# Keywords that end the "type" part of a column definition.
TYPE_STOP = {"not", "null", "default", "references", "primary", "unique",
             "check", "generated", "constraint"}
# Exact first-token match (not a prefix — a column named `checked` is a column).
CONSTRAINT_START = {"check", "constraint", "primary", "unique", "foreign",
                    "exclude"}

tables = {}   # name -> dict(migration, columns=[...], constraints=[...], rls, published)
order = []    # introduction order

def split_top_level(body):
    parts, depth, cur = [], 0, []
    for ch in body:
        if ch == "(": depth += 1
        elif ch == ")": depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur)); cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip(): parts.append("".join(cur))
    return [p.strip() for p in parts if p.strip()]

def parse_column(defn, migration=None):
    name, _, rest = defn.partition(" ")
    toks, typ = rest.split(), []
    while toks and toks[0].split("(")[0].lower() not in TYPE_STOP:
        typ.append(toks.pop(0))
    detail = " ".join(toks)
    nullable = "no" if ("not null" in detail or "primary key" in detail) else "yes"
    return {"name": name, "type": " ".join(typ), "nullable": nullable,
            "detail": detail, "added_in": migration}

for path in MIGRATIONS:
    sql = path.read_text()
    sql = re.sub(r"--[^\n]*", "", sql)                  # strip line comments
    sql = re.sub(r"\$\$.*?\$\$", "$$…$$", sql, flags=re.S)  # drop function bodies
    sql = re.sub(r"\s+", " ", sql)
    for stmt in (s.strip() for s in sql.split(";")):
        m = re.match(r"create table (?:if not exists )?(\w+) \((.*)\)$", stmt, re.I)
        if m:
            name, body = m.group(1), m.group(2)
            t = {"migration": path.name, "columns": [], "constraints": [],
                 "rls": False, "published": False}
            for item in split_top_level(body):
                if item.split()[0].lower() in CONSTRAINT_START:
                    t["constraints"].append(item)
                else:
                    t["columns"].append(parse_column(item))
            tables[name] = t
            order.append(name)
            continue
        m = re.match(r"alter table (\w+) add column (?:if not exists )?(.*)$", stmt, re.I)
        if m and m.group(1) in tables:
            tables[m.group(1)]["columns"].append(parse_column(m.group(2), path.name))
            continue
        m = re.match(r"alter table (\w+) enable row level security$", stmt, re.I)
        if m and m.group(1) in tables:
            tables[m.group(1)]["rls"] = True
            continue
        m = re.match(r"alter publication powersync add table (.*)$", stmt, re.I)
        if m:
            for name in (n.strip() for n in m.group(1).split(",")):
                if name in tables: tables[name]["published"] = True

lines = [
    "<!-- GENERATED FILE — do not edit. Regenerate with `make docs` (scripts/gen_docs.sh). -->",
    "# Database schema (generated)",
    "",
    f"Parsed from `supabase/migrations/*.sql` ({len(MIGRATIONS)} migrations, "
    f"{len(order)} tables). Per table: columns from `create table` plus later "
    "`alter table add column`s, whether RLS is enabled, whether the table is in "
    "the `powersync` publication, and the migration that introduced it.",
    "",
    "**Limitations (honest 90% parse):** indexes, RLS policy bodies, grants,",
    "functions, triggers, and seed data are not listed — read the migration for",
    "those. Column types/details are shown as written, not introspected from a",
    "live database.",
    "",
]
for name in order:
    t = tables[name]
    flags = [f"introduced in `{t['migration']}`"]
    flags.append("RLS enabled" if t["rls"] else "**RLS not enabled**")
    if t["published"]: flags.append("in the `powersync` publication")
    lines += [f"## `{name}`", "", " · ".join(flags), "",
              "| Column | Type | Nullable | Details |",
              "|---|---|---|---|"]
    for c in t["columns"]:
        detail = c["detail"]
        if c["added_in"]:
            detail = (detail + " " if detail else "") + f"*(added in `{c['added_in']}`)*"
        lines.append(f"| `{c['name']}` | `{c['type']}` | {c['nullable']} | {detail} |")
    if t["constraints"]:
        lines += ["", "Table constraints: " +
                  "; ".join(f"`{c}`" for c in t["constraints"])]
    lines.append("")

OUT.write_text("\n".join(lines).rstrip() + "\n")
print(f"gen_docs: wrote {OUT} ({len(order)} tables from {len(MIGRATIONS)} migrations)")
PY
