/// Structural test: every table a repository's load path reads must be a
/// trigger of its watch query.
///
/// PowerSync derives a watch's trigger tables from `EXPLAIN` on the watched
/// SQL — and SQLite drops a LEFT JOIN whose columns are never selected, so a
/// joined-but-unselected table silently falls out of the trigger set. The
/// repos guard this by selecting one column from every joined table; this test
/// enforces the invariant mechanically instead of by prose rule (core belief:
/// enforce invariants, not style).
///
/// It is a deliberately simple *string-level* check over the repo sources:
/// - every `FROM`/`JOIN <table>` in any SELECT in the file must also appear in
///   that file's watch SQL (unless listed as exempt — a query that feeds a
///   one-shot Future API, not the watch stream), and
/// - every table joined in the watch SQL must contribute a selected column
///   (checked via its alias appearing in the SELECT list).
///
/// Known limits, accepted for simplicity: SQL built with `$interpolation` is
/// skipped (it can't name a literal table), and files with several watch
/// queries are checked against the union of their watch tables. If this test
/// ever turns brittle, replace it with a pinned watched-tables list per repo.
///
/// The rule is OPT-OUT: every `lib/features/*/data/*_repository_impl.dart` that
/// contains a `.watch(` is covered automatically, so a new repository joins the
/// rule by existing rather than by someone remembering to list it. Skipping one
/// takes an entry in [_excluded] with a reason.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// Where the covered repositories live, relative to `app/` (the cwd of
/// `flutter test`).
const _repoGlobDir = 'lib/features';
const _repoSuffix = '_repository_impl.dart';

/// Tables a given repo reads only from a one-shot Future API that is not part
/// of any watch stream's load path.
const _exemptTables = <String, Set<String>>{
  // The vocab repo watches the manager list, one row (`watchIngredient`) and
  // one row's aliases (`watchAliases`). Every table below belongs to a
  // one-shot Future instead: the reference tables to `recentlyUsed` and the
  // delete guard's own reference count, `ingredient_measure` to
  // `setDefaultMeasure`'s own-measure check. None of them can make a watched
  // read stale — and the measure count the list and the row BOTH draw rides
  // the `ingredient` watch as a correlated subquery.
  // The week's three (0041) are the delete guard's too: it counts every live
  // line naming the row — a recipe line, a bare-ingredient meal, a this-week
  // swap — so it refuses exactly what the database refuses. One-shot Future,
  // read at the moment of the tap, like the rest of this list.
  'lib/features/ingredients/data/ingredient_repository_impl.dart': {
    'ingredient_measure',
    'recipe_line_item',
    'ingredient_group',
    'recipe',
    'shopping_list_entry',
    'shopping_list_contribution',
    'plan_entry',
    'week_plan',
    'week_recipe_line_override',
  },
  // The measure repo watches one ingredient's measures. The tables below are
  // `countLinesUsing`'s alone — the delete guard, a one-shot Future read at
  // the moment of the tap. Nothing watched reads them, so nothing watched can
  // go stale when one of them changes.
  'lib/features/ingredients/data/measure_repository_impl.dart': {
    'recipe_line_item',
    'shopping_list_contribution',
    'plan_entry',
    'ingredient_group',
    'recipe',
  },
  // The recipe-measure repo watches one recipe's own words. The tables below
  // are the delete gate's alone (`countLinesUsing` — the two tables 0048 says
  // can carry a pointer, plus the join naming the recipes a refusal sends
  // somebody to): a one-shot Future read at the moment of the tap. Nothing
  // watched here reads them, so nothing watched can go stale when one changes —
  // and the surfaces that depend on a word watch `recipe_measure` themselves,
  // which is how a re-stated `blob` reaches them.
  'lib/features/recipes/data/recipe_measure_repository_impl.dart': {
    'recipe_line_item',
    'week_recipe_line_override',
    'ingredient_group',
    'recipe',
  },
  // The planner watches a week's meals. It reads the week's line overrides in
  // exactly one place — `copyLastWeek`, counting the variants it is about to
  // leave behind — which is a one-shot Future taken at the moment of the copy.
  // The Week screen reads the same table through its own watched provider, so
  // no watched read here can go stale for it.
  'lib/features/planning/data/planning_repository_impl.dart': {
    'week_recipe_line_override',
  },
};

/// Repositories deliberately outside the rule, each with the reason. A watching
/// repo may only be added here with a real justification — this list is the
/// audit trail, not a place to silence a failure.
const _excluded = <String, String>{};

/// A single- or double-quoted Dart string literal.
final _literal = RegExp('"(?:[^"\\\\]|\\\\.)*"|\'(?:[^\'\\\\]|\\\\.)*\'');

/// `FROM x` / `JOIN x`, optionally `x alias`. Interpolated names (`\$table`)
/// don't match the identifier class and are skipped by design.
final _tableRef = RegExp(
  r'\b(?:FROM|JOIN)\s+([a-z_][a-z0-9_]*)(?:\s+([a-z_][a-z0-9_]*))?',
  caseSensitive: false,
);

const _sqlKeywords = {
  'on', 'where', 'left', 'right', 'inner', 'outer', 'cross', 'join', //
  'order', 'group', 'limit', 'set', 'values', 'as', 'and', 'or',
};

/// Merges adjacent string literals (Dart concatenates them) into the full
/// strings the source builds, keeping each string's start offset.
List<({int offset, String text})> _mergedStrings(String source) {
  final out = <({int offset, String text})>[];
  int? runStart;
  var runText = StringBuffer();
  var lastEnd = -1;
  for (final m in _literal.allMatches(source)) {
    final body = source.substring(m.start + 1, m.end - 1);
    final adjacent =
        runStart != null && source.substring(lastEnd, m.start).trim().isEmpty;
    if (adjacent) {
      runText.write(body);
    } else {
      if (runStart != null) {
        out.add((offset: runStart, text: runText.toString()));
      }
      runStart = m.start;
      runText = StringBuffer(body);
    }
    lastEnd = m.end;
  }
  if (runStart != null) out.add((offset: runStart, text: runText.toString()));
  return out;
}

/// (table → alias-or-table) for every literal table reference in [sql].
Map<String, String> _tables(String sql) {
  final tables = <String, String>{};
  for (final m in _tableRef.allMatches(sql)) {
    final table = m.group(1)!.toLowerCase();
    final alias = m.group(2)?.toLowerCase();
    tables[table] = (alias == null || _sqlKeywords.contains(alias))
        ? table
        : alias;
  }
  return tables;
}

/// Every repository implementation on disk, path-sorted so the generated test
/// list is stable.
List<String> _repositoryImpls() {
  final dir = Directory(_repoGlobDir);
  final paths =
      dir
          .listSync()
          .whereType<Directory>()
          .map((f) => Directory('${f.path}/data'))
          .where((d) => d.existsSync())
          .expand((d) => d.listSync().whereType<File>())
          .map((f) => f.path)
          .where((p) => p.endsWith(_repoSuffix))
          .toList()
        ..sort();
  return paths;
}

void main() {
  final impls = _repositoryImpls();

  test('the repository glob actually found the repositories', () {
    // A broken glob would make every check below vacuously pass.
    expect(impls.length, greaterThanOrEqualTo(6), reason: 'found: $impls');
  });

  for (final path in impls) {
    final source = blankComments(File(path).readAsStringSync());
    final reason = _excluded[path];
    if (reason != null) {
      test('$path — excluded from the watch rule', () {
        expect(reason, isNotEmpty);
      });
      continue;
    }
    // Opt-out: a repo without a watched query has no watch stream to keep
    // honest (the import repo is commit-only, the vocab repo is search-only).
    if (!source.contains('.watch(')) continue;
    final exempt = _exemptTables[path] ?? const <String>{};

    test('$path — watch SQL covers every load-path table', () {
      final strings = _mergedStrings(source);

      // The watch queries: the first merged string at or after each
      // `.watch(`. AT, not after: a one-line `.watch('SELECT …')` opens its
      // literal at exactly `m.end`, and a strict `>` skipped it and analysed
      // whatever string came next in the file instead.
      final watchSqls = <String>[];
      for (final m in '.watch('.allMatches(source)) {
        final s = strings
            .where((s) => s.offset >= m.end)
            .reduce((a, b) => a.offset < b.offset ? a : b);
        watchSqls.add(s.text);
      }
      expect(watchSqls, isNotEmpty, reason: 'no .watch( query found in $path');

      // Union of tables (and their aliases) across the file's watch queries.
      final watchTables = <String, String>{};
      for (final sql in watchSqls) {
        watchTables.addAll(_tables(sql));

        // Every watched table must contribute a SELECTed column, or SQLite
        // drops its join and PowerSync never sees the table. Aliased columns
        // (`alias.col`) are checked; a bare-`SELECT *`-style single-table
        // query trivially selects from its only table.
        final selectClause = sql.substring(
          0,
          sql.toUpperCase().indexOf(' FROM '),
        );
        final tables = _tables(sql);
        if (tables.length > 1) {
          for (final t in tables.entries) {
            expect(
              selectClause.contains('${t.value}.'),
              isTrue,
              reason:
                  'watch SQL joins `${t.key}` (alias `${t.value}`) without '
                  'selecting a column from it — SQLite will drop the join and '
                  'the watch will miss `${t.key}` changes:\n$sql',
            );
          }
        }
      }

      // Every table any SELECT in the file reads must be watched.
      final loadTables = <String>{};
      for (final s in strings) {
        if (!s.text.trimLeft().toUpperCase().startsWith('SELECT')) continue;
        loadTables.addAll(_tables(s.text).keys);
      }
      final missing = loadTables
          .difference(watchTables.keys.toSet())
          .difference(exempt);
      expect(
        missing,
        isEmpty,
        reason:
            'tables read by $path but absent from its watch SQL '
            '(stale-data bug: changes to them will not re-fire the stream): '
            '$missing',
      );
    });
  }
}
