# PowerSync `watch()` — how a query decides what re-fires it

_Mechanics explainer, traced against `powersync_core` 1.8.0._

Every reactive read in the app is a `db.watch(sql)` stream. PowerSync decides
which tables should re-fire that stream by running **`EXPLAIN` on the SQL** and
collecting the tables SQLite says it will actually touch. That derivation is the
whole story, and it has one sharp edge.

## The trap: SQLite drops LEFT JOINs you never select from

If a query LEFT JOINs a table and selects **no column** from it, SQLite's query
planner removes the join — the result set is provably identical without it. The
`EXPLAIN` output then never mentions that table, so it never lands in the watch's
trigger set, so **writes to it don't re-fire the stream**.

This is not theoretical: it shipped a live bug. `watchRecipe` joined `book` and
`book_section` only to render a breadcrumb, selected nothing from them, and so
never re-fired when a section was renamed — the breadcrumb went stale until you
navigated away and back.

**The rule:** select at least one column from every table a watch joins, even if
the UI doesn't render it. `app/test/core/sync/watch_coverage_test.dart` enforces
this structurally across the repos rather than leaving it as a prose convention.

### The nuance: it only bites joins onto a unique key

The planner may only drop a LEFT JOIN when it can prove the join can't change the
number of output rows — i.e. the right-hand side is unique on the join column, in
practice a **primary key or a unique index**. `LEFT JOIN book b ON b.id =
r.book_id` qualifies and gets dropped. A LEFT JOIN onto a **non-unique** column
(one recipe → many line items) can multiply rows, so the planner must keep it,
and that table stays in the trigger set whether or not you select from it.

So the failure mode is narrower than "any unselected LEFT JOIN": it is
**unselected LEFT JOINs onto a key**. That is still the common case — those are
exactly the lookup joins you add for a name or a label — so the select-a-column
rule is worth applying uniformly instead of reasoning about uniqueness per query.
Applying it costs one column; getting the reasoning wrong costs a silent stale
screen. Every repository watch is covered — the set is derived and asserted by
`app/test/core/sync/watch_coverage_test.dart`, so the count is a test's
business and not a sentence's.

## The escape hatch: `triggerOnTables:`

When a query genuinely can't satisfy the rule — a `SELECT count(*)`, an
aggregate, an `EXISTS` subquery, anything where adding a column would change the
shape of the result — name the tables explicitly:

```dart
db.watch(
  'SELECT count(*) AS n FROM recipe WHERE deleted_at IS NULL',
  triggerOnTables: ['recipe', 'book'],
)
```

Given logical table names, `PowerSyncDatabase.watch` expands each into the three
physical names the sync layer actually writes (`<t>`, `ps_data__<t>`,
`ps_data_local__<t>`) and hands that set to the underlying watcher — so you pass
the table name you'd write in SQL, not a storage name.

Two cautions:

- **It replaces the derivation, it doesn't extend it.** Passing a non-empty
  `triggerOnTables` means your list *is* the trigger set. Miss a table and the
  stream goes stale in exactly the way the rule was protecting you from.
- **Prefer the column.** A selected column keeps the trigger set correct
  automatically as the query evolves; a hand-maintained list is one more thing to
  update when someone adds a join six months from now. Reach for
  `triggerOnTables` only when the query shape leaves no alternative, and say why
  in a comment.

## Source map

- `watch` + the trigger expansion — `powersync_core/lib/src/database/powersync_db_mixin.dart`
- The structural guard — `app/test/core/sync/watch_coverage_test.dart`
- The bug that found it — `docs/exec-plans/completed/0004-test-harness-and-doc-hygiene.md`
