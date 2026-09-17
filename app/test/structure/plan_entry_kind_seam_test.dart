/// The seam every derivation of a planned meal stands on: **the kind is
/// asked, and all three answers are given.**
///
/// A plan entry is a recipe, a bare ingredient, or a meal eaten out. Before
/// there was an enum there were two nullable columns, and the standing bug of
/// that shape is that a null `recipe_id` reads as "skip" — a meal silently
/// missing from a total, a list or a plan, with nothing anywhere saying it was
/// left out. [PlanEntryKind] exists so the compiler refuses that: a `switch`
/// over an enum must name every case.
///
/// The compiler can be talked out of it, though, in exactly two ways, and this
/// guard is about those two:
///
///  1. **a wildcard.** `default:` or `_ =>` inside a switch over the kind
///     makes it exhaustive without making it complete — a fourth kind would
///     land in the catch-all, which is the same silent skip wearing a newer
///     hat. So a switch that mentions the kind must name all three and carry
///     no wildcard.
///  2. **asking the columns instead.** `entry.recipeId == null` is a kind test
///     written by hand: it answers "ingredient" for a meal eaten out, which is
///     wrong in a way nothing fails on. Anywhere under `lib/features/` that
///     knows what a [PlanEntry] is, the kind is read through [PlanEntry.kind].
///
/// And one thing the enum cannot hold at all: the cook plan and the shopping
/// list branch in **SQL**, where there is no compiler to help. Each states the
/// kind it takes in its own `WHERE` clause — redundantly beside its join, on
/// purpose — so this guard reads those clauses too.
///
/// **What it can be defeated by**, stated plainly because a string-level scan
/// should be honest about its reach: a kind test hidden behind a helper that
/// takes the id rather than the entry, a switch assembled from a variable, and
/// SQL built by concatenation somewhere other than these two files. It stops
/// the ordinary omission, which is the one that has actually shipped here.
library;

import 'dart:io';

import 'package:ansi/features/planning/domain/planning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// The three cases, spelled the way the code spells them.
const _kinds = [
  'PlanEntryKind.recipe',
  'PlanEntryKind.ingredient',
  'PlanEntryKind.out',
];

/// The two derivations that branch in SQL, and the clause each one states its
/// kind with. Listed rather than derived because there are two of them and
/// they are the whole set: a third would be a new derivation, which is a
/// change to this test as much as to the code.
const _sqlDerivations = {
  'lib/features/cook_plan/data/cook_plan_repository_impl.dart': [
    'pe.recipe_id IS NOT NULL',
  ],
  'lib/features/shopping/data/shopping_repository_impl.dart': [
    'pe.recipe_id IS NOT NULL',
    'pe.ingredient_id IS NOT NULL',
  ],
};

/// The column-as-kind tests: a null check against one of the three target
/// columns.
///
/// `recipeId` and `ingredientId` are caught bare as well as through a
/// receiver, because nothing else in this app is called either. `label` is
/// caught only through a receiver — a measure's label, a chip's label and a
/// slot's label are all ordinary locals, and a guard that shouted at those
/// would be turned off within a week.
final _nullKindTest = RegExp(
  r'(?:(?:\.|\b)(?:recipeId|ingredientId)|\.label)\s*[!=]=\s*null',
);

/// The one file allowed to read the columns: [PlanEntry.kind] is where the
/// three nulls are turned into the one question, and it has to ask them
/// somewhere.
const _kindIsDefinedIn = 'lib/features/planning/domain/planning.dart';

/// Every `switch` body in [source] (comments and literals already blanked),
/// as `(offset, text)` of the braced block.
List<(int, String)> switchBodies(String source) {
  final found = <(int, String)>[];
  for (final match in RegExp(r'\bswitch\s*\(').allMatches(source)) {
    // Past the scrutinee's parentheses, balancing as we go — a switch over
    // `f(x)` has a `)` in the middle of its own.
    var depth = 0;
    var i = match.end - 1;
    for (; i < source.length; i++) {
      if (source[i] == '(') depth++;
      if (source[i] == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    final open = source.indexOf('{', i);
    if (open < 0) continue;
    depth = 0;
    var j = open;
    for (; j < source.length; j++) {
      if (source[j] == '{') depth++;
      if (source[j] == '}') {
        depth--;
        if (depth == 0) break;
      }
    }
    found.add((match.start, source.substring(open, j + 1)));
  }
  return found;
}

void main() {
  final lib = dartFiles(Directory('lib'));

  test('a switch over the kind names all three, and wildcards none', () {
    final offenders = <String>[];
    for (final file in lib) {
      final source = file.readAsStringSync();
      final code = blankNonCode(source);
      for (final (offset, body) in switchBodies(code)) {
        if (!body.contains('PlanEntryKind.')) continue;
        final where = '${file.path}:${lineOf(source, offset)}';
        final missing = _kinds.where((k) => !body.contains(k));
        if (missing.isNotEmpty) {
          offenders.add('$where: does not name ${missing.join(', ')}');
        }
        // `_ =>` in a pattern switch, `default:` in a statement one. A `_`
        // that is part of an identifier does not count, so the match is
        // anchored on the arrow and the colon.
        if (RegExp(r'(^|[\s(,])_\s*(=>|:)').hasMatch(body) ||
            RegExp(r'\bdefault\s*:').hasMatch(body)) {
          offenders.add('$where: answers the kind with a wildcard');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a switch over PlanEntryKind names recipe, ingredient and out, and '
          'never a catch-all — the catch-all is how a fourth kind gets '
          'silently skipped:\n${offenders.join('\n')}',
    );
  });

  test('no file that knows a PlanEntry tests a column for the kind', () {
    final offenders = <String>[];
    for (final file in lib) {
      if (!file.path.startsWith('lib/features/')) continue;
      if (file.path == _kindIsDefinedIn) continue;
      final source = file.readAsStringSync();
      final code = blankNonCode(source);
      // Only files that handle plan entries: `recipeId == null` is an honest
      // question about a route parameter in the recipe editor, and about a
      // resolution's target in the import review.
      if (!code.contains('PlanEntry')) continue;
      for (final match in _nullKindTest.allMatches(code)) {
        offenders.add(
          '${file.path}:${lineOf(source, match.start)}: ${match.group(0)}',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'read PlanEntry.kind — a null column answers the wrong question the '
          'moment there are three kinds:\n${offenders.join('\n')}',
    );
  });

  test('the SQL derivations state the kind they take', () {
    for (final entry in _sqlDerivations.entries) {
      // Comments only: the clause being looked for lives INSIDE the string
      // literals this file builds its query from.
      final sql = blankComments(File(entry.key).readAsStringSync());
      for (final clause in entry.value) {
        expect(
          sql.contains(clause),
          isTrue,
          reason:
              '${entry.key} derives from plan_entry without saying which kind '
              'it takes ($clause) — a join that happens to drop the other '
              'kinds is not a branch',
        );
      }
    }
  });

  test('the scan catches the shapes it exists for', () {
    const wildcard = '''
      String f(PlanEntry e) => switch (e.kind) {
        PlanEntryKind.recipe => 'a dish',
        _ => 'something else',
      };
    ''';
    final bodies = switchBodies(blankNonCode(wildcard));
    expect(bodies, hasLength(1));
    expect(bodies.single.$2.contains('PlanEntryKind.out'), isFalse);
    expect(RegExp(r'(^|[\s(,])_\s*(=>|:)').hasMatch(bodies.single.$2), isTrue);

    // A switch whose scrutinee carries parentheses of its own is still one
    // block, and a complete one passes both halves.
    const complete = '''
      String f(PlanEntry e) => switch (kindOf(e)) {
        PlanEntryKind.recipe => 'a dish',
        PlanEntryKind.ingredient => 'a snack',
        PlanEntryKind.out => 'eaten out',
      };
    ''';
    final good = switchBodies(blankNonCode(complete));
    expect(good, hasLength(1));
    for (final kind in _kinds) {
      expect(good.single.$2.contains(kind), isTrue);
    }

    expect(_nullKindTest.hasMatch('if (entry.recipeId == null) return;'), true);
    expect(_nullKindTest.hasMatch('if (e.ingredientId != null) x();'), true);
    // Bare, as it reads inside the class — only planning.dart may write this.
    expect(_nullKindTest.hasMatch('final snack = ingredientId != null;'), true);
    // A local called `label` is not a kind test; a meal's label is.
    expect(_nullKindTest.hasMatch('if (label == null) return null;'), false);
    expect(_nullKindTest.hasMatch('if (entry.label == null) return;'), true);
    // Not a kind test: a comparison against another value.
    expect(_nullKindTest.hasMatch('e.recipeId == recipe.id'), false);
  });
}
