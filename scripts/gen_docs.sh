#!/usr/bin/env bash
# Regenerate docs/generated/* from sources of truth (`make docs`).
#   docs/generated/db-schema.md      ← supabase/migrations/*.sql (python, below)
#   docs/generated/unit-admission.md ← the domain rule itself, run for real by
#                                      app/tool/gen_unit_admission.dart
# The schema half is deliberately boring: python3 stdlib only, a ~90% parse of
# our own migration style (limitations are stated in the generated header).
set -euo pipefail
cd "$(dirname "$0")/.."

# Optional arguments: write somewhere other than the committed files, one path
# per generated doc, each defaulting to its committed path. The freshness check
# in check_docs.sh regenerates to temp paths and diffs.
#   gen_docs.sh [db-schema-out] [unit-admission-out]
root=$(pwd)
abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$root/$1" ;; esac; }
export GEN_DOCS_OUT="$(abspath "${1:-docs/generated/db-schema.md}")"
units_out="$(abspath "${2:-docs/generated/unit-admission.md}")"

python3 - <<'PY'
import os
import re
from pathlib import Path

MIGRATIONS = sorted(Path("supabase/migrations").glob("*.sql"))
OUT = Path(os.environ["GEN_DOCS_OUT"])

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
        m = re.match(r"alter table (\w+) enable row level security$", stmt, re.I)
        if m and m.group(1) in tables:
            tables[m.group(1)]["rls"] = True
            continue
        # One `alter table` may carry several comma-separated clauses:
        #   alter table recipe add column a int check (…), add column b int …
        # Splitting at the top level (so commas inside a check(...) don't count)
        # is what keeps the second column from being smeared into the first's
        # "details" cell. Non-`add column` clauses are ignored, not guessed at.
        m = re.match(r"alter table (\w+) (.*)$", stmt, re.I)
        if m and m.group(1) in tables:
            t = tables[m.group(1)]
            for clause in split_top_level(m.group(2)):
                c = re.match(r"add column (?:if not exists )?(.*)$", clause, re.I)
                if c:
                    t["columns"].append(parse_column(c.group(1), path.name))
                    continue
                # `drop column` removes it: the doc describes the live schema,
                # and git holds what a dropped column used to be (0042 drops
                # ingredient.default_measure_id).
                c = re.match(r"drop column (?:if exists )?(\w+)$", clause, re.I)
                if c:
                    t["columns"] = [
                        col for col in t["columns"] if col["name"] != c.group(1)]
                    continue
                # `alter column x drop/set not null` RELAXES or tightens a
                # column that already exists (0017 relaxes
                # recipe_line_item.ingredient_id). Without this the table
                # renders the original `create table` nullability forever —
                # a generated doc quietly lying about the live schema.
                c = re.match(
                    r"alter column (\w+) (drop|set) not null$", clause, re.I)
                if c:
                    for col in t["columns"]:
                        if col["name"] != c.group(1):
                            continue
                        drop = c.group(2).lower() == "drop"
                        col["nullable"] = "yes" if drop else "no"
                        col["detail"] = (
                            col["detail"].replace("not null", "").strip()
                            if drop else (col["detail"] + " not null").strip())
                        # A column added and tightened by the SAME migration
                        # (0012's basis_amount) needs no second stamp.
                        if col["added_in"] != path.name:
                            col["detail"] = (
                                (col["detail"] + " " if col["detail"] else "")
                                + f"*({'nullable' if drop else 'not null'} "
                                  f"since `{path.name}`)*")
                    continue
                # A table-level rule can arrive, or be RESTATED, in a later
                # migration (0048 widens week_recipe_line_override's amount
                # pair, so a line said in a recipe's own word may carry no
                # unit). Without these two the doc prints the `create table`
                # rules forever and misstates the rest — the same quiet lie
                # the nullability branch above fixes.
                c = re.match(
                    r"drop constraint (?:if exists )?(\w+)", clause, re.I)
                if c:
                    t["constraints"] = [
                        k for k in t["constraints"]
                        if not re.match(rf"constraint {c.group(1)}\b", k, re.I)]
                    continue
                if re.match(r"add constraint \w+ ", clause, re.I):
                    t["constraints"].append(clause[len("add "):])
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

# The unit table is generated by running the domain rule itself — pure Dart
# (invariant 2), so `dart run` suffices and no Flutter toolchain is involved.
(cd app && dart run tool/gen_unit_admission.dart "$units_out")
