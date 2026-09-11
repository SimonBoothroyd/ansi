/// The invariant behind `features/ingredients/data/name_holder.dart`: **every
/// writer of an ingredient name or alias asks the one namespace, in SQL,
/// inside its own transaction.**
///
/// Names and aliases share `match_text` (`domain/name_namespace.dart`), and a
/// rule held by only some of the writers is not held at all: one writer that
/// skips it — the import's learning loop taking "extra-firm tofu" onto Super
/// Firm Tofu, which is Extra Firm Tofu's own name — puts one `match_text` on
/// two rows, where the only thing downstream that can still notice is the seed
/// generator refusing the whole snapshot.
///
/// **What it reads:** every file under `lib/` that writes an `ingredient` or
/// `ingredient_alias` row, found by its `INSERT INTO`. Each must call
/// [nameHolderFor] — the one place the question is expressed as SQL.
library;

import 'dart:io';

import 'package:ansi/features/ingredients/data/name_holder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Files whose insert cannot carry a name into the namespace: a plain status
/// or provenance write, never a `canonical_name` / `alias_text`. Empty today,
/// and it should stay that way — an entry here is a claim, not a convenience.
const _exempt = <String>{};

final _insert = RegExp(
  r"INSERT INTO '?(ingredient|ingredient_alias)\b",
  caseSensitive: false,
);

void main() {
  test('every name or alias write asks nameHolderFor', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);

    final writers = <String>[];
    final unchecked = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      if (!_insert.hasMatch(source)) continue;
      final name = file.uri.pathSegments.last;
      if (_exempt.contains(name)) continue;
      writers.add(name);
      if (!source.contains('nameHolderFor(')) unchecked.add(name);
    }

    // The derivation still sees the two writers it was written for.
    expect(
      writers,
      containsAll(<String>[
        'ingredient_repository_impl.dart',
        'import_repository_impl.dart',
      ]),
    );

    expect(
      unchecked,
      isEmpty,
      reason:
          'these files insert an ingredient or an alias without asking the '
          'one namespace — call nameHolderFor inside the write transaction '
          '(features/ingredients/data/name_holder.dart) and, on a hit, refuse '
          'or simply do not write',
    );
    // The rule-holder itself is reachable from here, so the doc reference and
    // the import above cannot rot.
    expect(nameHolderFor, isNotNull);
  });
}
