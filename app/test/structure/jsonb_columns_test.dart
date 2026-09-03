/// The invariant behind `jsonbColumnsByTable` in `core/sync/connector.dart`:
/// **every `jsonb` column on a synced table is decoded before upload.**
///
/// PowerSync's local SQLite holds JSON as TEXT; a column the connector does
/// not decode reaches Postgres as a jsonb *string* and every server-side
/// `?`, `||` and `jsonb_array_elements` over it is silently wrong.
/// `ingredient.allowed_units` (0012) lived outside the map from the day it
/// was declared until 2026-09-03, when pgTAP over smoke-created rows caught
/// it (0028 repairs the stored rows). A column is declared once, in a
/// migration; this test reads the declarations so the map cannot fall behind
/// a second time.
///
/// **What it reads:** every `supabase/migrations/*.sql`, for a column
/// declared `jsonb` inside a `create table` block and for an `alter table …
/// add column … jsonb`. Tables that never sync to a device (`usda_food`,
/// ADR-0005) are excluded by name — the exclusion list is the only thing
/// here that is not derived, and it must stay short.
library;

import 'dart:io';

import 'package:ansi/core/sync/connector.dart';
import 'package:flutter_test/flutter_test.dart';

/// Server-only tables: never in `schema.dart`, never through the connector.
const _serverOnly = {'usda_food'};

Map<String, Set<String>> jsonbColumnsInMigrations(Iterable<File> files) {
  final found = <String, Set<String>>{};
  final createTable = RegExp(
    r'create\s+table\s+(?:if\s+not\s+exists\s+)?(\w+)\s*\((.*?)\n\);',
    caseSensitive: false,
    dotAll: true,
  );
  final column = RegExp(r'^\s*(\w+)\s+jsonb\b', multiLine: true);
  final alter = RegExp(
    r'alter\s+table\s+(\w+)\s+add\s+column\s+(?:if\s+not\s+exists\s+)?(\w+)\s+jsonb\b',
    caseSensitive: false,
  );
  for (final file in files) {
    final source = file.readAsStringSync();
    for (final t in createTable.allMatches(source)) {
      for (final c in column.allMatches(t.group(2)!)) {
        found.putIfAbsent(t.group(1)!, () => {}).add(c.group(1)!);
      }
    }
    for (final a in alter.allMatches(source)) {
      found.putIfAbsent(a.group(1)!, () => {}).add(a.group(2)!);
    }
  }
  found.removeWhere((table, _) => _serverOnly.contains(table));
  return found;
}

void main() {
  test('the connector decodes every jsonb column the migrations declare', () {
    final files = Directory('../supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList();
    expect(files, isNotEmpty);

    final declared = jsonbColumnsInMigrations(files);
    // The derivation still sees the columns it was written for.
    expect(
      declared['ingredient'],
      containsAll(<String>['macros', 'allowed_units']),
    );
    expect(declared['recipe'], contains('steps'));
    expect(declared['plan_entry'], contains('eaters'));

    expect(
      jsonbColumnsByTable,
      equals(declared),
      reason:
          'a jsonb column declared in supabase/migrations is not decoded by '
          'the connector (or the map names one the migrations do not) — '
          'add it to jsonbColumnsByTable in core/sync/connector.dart',
    );
  });
}
