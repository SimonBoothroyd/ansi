/// The invariant behind `naturalKeysByTable` in `core/sync/connector.dart`:
/// **every unique key a synced table holds beside its id is either merged
/// on upload or cannot be hit by a phone's write.**
///
/// A PUT is an upsert by id. Two phones that each make the row for one
/// natural key offline give it two ids, and the second PUT hits the key
/// (`23505`). Unhandled, the connector drops it and the phones diverge: the
/// owner's partner saw exactly that on `week_recipe_line_override`. This test
/// reads every unique key the migrations declare, so a new one cannot land
/// without a decision here.
///
/// **What it reads:** `unique (…)` inside a `create table` block, an inline
/// `… unique` column, and `create unique index … on t (…)`, less any index a
/// later migration drops.
library;

import 'dart:io';

import 'package:ansi/core/sync/connector.dart';
import 'package:ansi/core/sync/schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unique keys on synced tables that no phone's write can collide on, and
/// why. Short, and every entry a reason.
const _cannotCollide = {
  // Rows are made by the server's claim and join functions; a phone only
  // patches its own member's portion factor, which never touches the key.
  'household_member(household_id,auth_user_id)',
  // Partial indexes over the template household's rows, which RLS lets no
  // phone write.
  'ingredient(match_text)',
  'ingredient_alias(ingredient_id,match_text)',
};

/// `table(col,col)` for every unique key the migrations still declare.
Set<String> uniqueKeysInMigrations(List<File> files) {
  final keys = <String, String>{}; // index name (or a synthetic one) → key
  final createTable = RegExp(
    r'create\s+table\s+(?:if\s+not\s+exists\s+)?(\w+)\s*\((.*?)\n\);',
    caseSensitive: false,
    dotAll: true,
  );
  final tableUnique = RegExp(r'^\s*unique\s*\(([^)]*)\)', multiLine: true);
  final inlineUnique = RegExp(
    r'^\s*(\w+)\s+\w+[^,\n]*\bunique\b',
    multiLine: true,
    caseSensitive: false,
  );
  final uniqueIndex = RegExp(
    r'create\s+unique\s+index\s+(?:if\s+not\s+exists\s+)?(\w+)\s+on\s+(\w+)'
    r'\s*\(([^)]*)\)',
    caseSensitive: false,
  );
  final dropIndex = RegExp(
    r'drop\s+index\s+(?:if\s+exists\s+)?(\w+)',
    caseSensitive: false,
  );
  String key(String table, String columns) =>
      '$table(${columns.split(',').map((c) => c.trim()).join(',')})';

  files.sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    // Comments carry the word "unique" freely.
    final source = file
        .readAsStringSync()
        .split('\n')
        .map((l) => l.replaceFirst(RegExp('--.*'), ''))
        .join('\n');
    for (final t in createTable.allMatches(source)) {
      final table = t.group(1)!;
      for (final u in tableUnique.allMatches(t.group(2)!)) {
        final k = key(table, u.group(1)!);
        keys[k] = k;
      }
      for (final c in inlineUnique.allMatches(t.group(2)!)) {
        final k = key(table, c.group(1)!);
        keys[k] = k;
      }
    }
    for (final i in uniqueIndex.allMatches(source)) {
      keys[i.group(1)!] = key(i.group(2)!, i.group(3)!);
    }
    for (final d in dropIndex.allMatches(source)) {
      keys.remove(d.group(1));
    }
  }
  return keys.values.toSet();
}

void main() {
  test('every unique key on a synced table is merged on upload, or cannot '
      'be hit by a phone', () {
    final files = Directory('../supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList();
    final synced = {for (final t in schema.tables) t.name};
    final onSynced = {
      for (final k in uniqueKeysInMigrations(files))
        if (synced.contains(k.substring(0, k.indexOf('(')))) k,
    };
    // The derivation still sees the keys it was written for.
    expect(onSynced, contains('week_plan(household_id,week_start_date)'));

    final merged = {
      for (final MapEntry(key: t, value: cols) in naturalKeysByTable.entries)
        '$t(${cols.join(',')})',
    };
    expect(onSynced.difference(_cannotCollide), merged);
    expect(_cannotCollide.difference(onSynced), isEmpty, reason: 'stale');
    // A parent a write can point at is one whose key merges.
    for (final parent in naturalKeyParents.values) {
      expect(naturalKeysByTable, contains(parent));
    }
  });
}
