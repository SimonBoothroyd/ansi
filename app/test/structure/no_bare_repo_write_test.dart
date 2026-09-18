/// The invariant behind `lib/shared/write.dart`: **every repository write
/// reached from a widget goes through `ref.write(context, what, action)`.**
///
/// The rule is mechanical rather than stylistic because a stylistic rule does
/// not catch the next omission: an unguarded write is invisible at the call
/// site — the code compiles, the spinner stops, and only a user finds out. A
/// paragraph in `AGENTS.md` cannot fail a build; this does, in `make test`.
///
/// **The write set is derived, not listed.** It is every `Future`-returning
/// method declared on a `domain/*_repository.dart` interface minus the named
/// read verbs below — so a repository method added tomorrow is covered the day
/// it is *declared*, which is the whole point.
///
/// **What it can be defeated by**, stated plainly because a regex over source
/// text should be honest about its reach: an aliased receiver whose call is
/// nested inside something other than the guard, a stored function reference
/// (`final f = repo.deleteSection; f(id);`), and anything inside a string
/// literal containing parentheses. It exists to stop the *ordinary* omission —
/// the one that happened 37 times — not a determined author.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// Interface methods that *read*. Everything else a repository declares is a
/// write and must go through the guard.
const _readVerbs = {
  'countLinesUsing',
  'countRecipesIn',
  'search',
  'recentlyUsed',
  'byId',
  'byIds',
  'aliases',
  'nameIndex',
  'measuresByIngredients',
  'usedIn',
  'mostRecentWeekBefore',
  'componentLinkWouldCycle',
};

/// Deliberate exceptions, keyed `<path>:<method>`, each with its reason.
///
/// Keyed by method rather than by line so an edit above it does not silently
/// move the exemption onto a different call.
const _allowed = <String, String>{
  'lib/features/recipes/presentation/recipe_view_models.dart:saveRecipe':
      'held by the editor notifier; its only caller — the editor Save button '
      '— wraps `notifier.save` in ref.write, so the guard is one frame out.',
  'lib/features/recipes/presentation/recipe_view_models.dart:ensureDefaultBook':
      "inside the editor provider's build: a failure is an AsyncError the "
      'screen already renders with a reason and a retry.',
  'lib/features/import/presentation/import_view_models.dart:startImport':
      'the import controller maps every failure to ImportFailed, which the '
      'intake form renders inline with the reason (D8: already honest).',
  'lib/features/import/presentation/import_view_models.dart:ensureDefaultBook':
      'inside the same startImport try: the header draft is filed into the '
      'default book on arrival, and a failure is the same ImportFailed.',
  'lib/features/import/presentation/import_view_models.dart:commit':
      'same — ImportFailed with the reason, under the review screen.',
  'lib/features/receipts/presentation/receipt_view_models.dart:readReceipt':
      'the scan controller maps every failure to ReceiptScanFailed, which the '
      'intake form renders inline with the reason — the same posture the '
      'import controller holds one folder over.',
  'lib/features/receipts/presentation/receipt_view_models.dart:saveReceipt':
      'same — ReceiptScanFailed with the reason, under the review screen.',
  'lib/features/import/presentation/import_view.dart:startImport':
      'the ImportController method, not the repository: it cannot throw.',
  'lib/features/import/presentation/reconciliation_view.dart:commit':
      'the ImportController method, not the repository: it cannot throw.',
  'lib/features/ingredients/presentation/ingredient_view_models.dart:saveForm':
      'held by the form notifier; every caller — the docked Save, Mark '
      'complete, the stranded-default repair — wraps `form.save` in '
      'ref.write, so the guard is one frame out.',
  'lib/features/ingredients/presentation/ingredient_view_models.dart:unconfirm':
      'same: the `⋯` item wraps `form.unconfirm` in ref.writeOk.',
  'lib/features/ingredients/presentation/ingredient_view_models.dart:softDelete':
      'same: the `⋯` item wraps `form.delete` in ref.write, and the refusal '
      'the notifier reports is a state, not a failure.',
  'lib/features/ingredients/presentation/ingredient_view_models.dart:'
          'declineUsdaPrefill':
      'same: the provenance card wraps `form.declineUsda` in ref.writeOk.',
  'lib/features/planning/presentation/week_variant_view_models.dart:'
          'saveOverrides':
      'held by the week-mode draft notifier; its only caller — the editor '
      'Save button — wraps `notifier.save` in ref.write, so the guard is one '
      'frame out.',
  'lib/features/planning/presentation/week_variant_view_models.dart:'
          'loadOverrides':
      "inside the draft provider's build: a failure is an AsyncError the "
      'screen already renders with a reason and a retry.',
};

/// Declarations on a repository interface: two-space indent, a `Future<…>`
/// return type, a name, an open paren.
final _declaration = RegExp(r'^  Future<.*>\s+(\w+)\s*\(', multiLine: true);

/// Whether the invocation starting at [index] is lexically an argument of a
/// `ref.write(` / `guardedWrite(` call.
///
/// Walks outward through the enclosing unclosed parentheses and asks what each
/// one belongs to, so a write nested a level deeper inside the guard's closure
/// still counts as guarded.
bool _insideGuard(String source, int index) {
  final head = RegExp(
    r'(?:\bguardedWrite(?:Ok)?|\.write(?:Ok)?)\s*(?:<[^<>()]*>)?\s*$',
  );
  var depth = 0;
  for (var i = index - 1; i >= 0; i--) {
    final c = source[i];
    if (c == ')') {
      depth++;
    } else if (c == '(') {
      if (depth > 0) {
        depth--;
        continue;
      }
      if (head.hasMatch(source.substring(0, i))) return true;
    }
  }
  return false;
}

void main() {
  late final Set<String> writeMethods;

  setUpAll(() {
    final interfaces = Directory('lib/features')
        .listSync()
        .whereType<Directory>()
        .map((f) => Directory('${f.path}/domain'))
        .where((d) => d.existsSync())
        .expand(dartFiles)
        .where((f) => f.path.endsWith('_repository.dart'));

    writeMethods = {
      for (final file in interfaces)
        for (final m in _declaration.allMatches(
          blankNonCode(file.readAsStringSync()),
        ))
          m.group(1)!,
    }..removeAll(_readVerbs);
  });

  test('the write set is derived from the repository interfaces', () {
    // A sanity check on the derivation: if the regex or the interface layout
    // drifts, this fails loudly instead of passing over an empty set.
    expect(
      writeMethods,
      containsAll(<String>{
        'createBook',
        'deleteSection',
        'saveRecipe',
        'addEntry',
        'setEntryChecked',
        'saveForm',
      }),
      reason: 'the derivation stopped seeing known write methods',
    );
    expect(
      writeMethods.intersection(_readVerbs),
      isEmpty,
      reason: 'a read verb leaked into the write set',
    );
  });

  test('every repository write in a view goes through ref.write', () {
    final violations = <String>[];
    var guarded = 0;
    var scanned = 0;

    for (final dir in widgetDirs()) {
      for (final file in dartFiles(dir)) {
        scanned++;
        final source = blankNonCode(file.readAsStringSync());
        final path = file.path;
        for (final m in RegExp(r'\.(\w+)\s*\(').allMatches(source)) {
          final name = m.group(1)!;
          if (!writeMethods.contains(name)) continue;
          if (_allowed.containsKey('$path:$name')) continue;
          if (_insideGuard(source, m.start)) {
            guarded++;
            continue;
          }
          final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          violations.add('$path:$line — .$name(');
        }
      }
    }

    expect(scanned, greaterThan(0), reason: 'nothing scanned — broken glob?');
    expect(
      guarded,
      greaterThan(0),
      reason:
          'no guarded writes found in the scanned features — either the sweep '
          'was reverted or `ref.write` was renamed',
    );
    expect(
      violations,
      isEmpty,
      reason:
          'a repository write is called straight from a view. A throw there '
          'is invisible: the spinner stops and the user is told nothing. '
          'Wrap it:\n'
          "    ref.write(context, 'delete that section', "
          '() => repo.deleteSection(id))\n'
          'or add a `<path>:<method>` entry to _allowed with the reason.\n'
          '${violations.join('\n')}',
    );
  });

  test('allow-list entries still point at something', () {
    for (final key in _allowed.keys) {
      final path = key.substring(0, key.lastIndexOf(':'));
      final method = key.substring(key.lastIndexOf(':') + 1);
      expect(File(path).existsSync(), isTrue, reason: '$key: no such file');
      expect(
        File(path).readAsStringSync().contains('.$method('),
        isTrue,
        reason: '$key: the exempted call is gone — drop the entry',
      );
    }
  });
}
