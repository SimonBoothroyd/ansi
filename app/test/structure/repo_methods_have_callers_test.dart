/// Every method a `domain/*_repository.dart` interface declares is called
/// from somewhere in `lib/` other than the interface and its own impl.
///
/// A repository method with no caller is not idle, it is *load-bearing on
/// tests*: ten of them survived two plans that replaced their doors, kept
/// alive by ~200 lines of test asserting contracts nothing in the app holds
/// any more. That is worse than dead code — it reads as a live contract, and
/// the next author writes against it. The rule is cheap to state and the
/// deletion is cheap to do the day the last caller goes.
///
/// **What it can be defeated by**, stated plainly because a regex over source
/// text should be honest about its reach: it matches `.<name>(` anywhere in
/// `lib/` outside the interfaces and the `*_repository_impl.dart` files, so a
/// *different* class with a same-named method counts as a caller, and a call
/// made through
/// a stored function reference (`final f = repo.deleteSection;`) does not
/// count at all. It exists to catch the ordinary case — a door replaced and
/// the old one left standing — not a determined author. Same reach, and the
/// same source-text approach, as `no_bare_repo_write_test.dart`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// Declarations on an interface: two-space indent, a return type, a name, an
/// open paren. Getters, fields and constructors do not match.
final _declaration = RegExp(
  r'^  (?:Future|Stream)<.*>\s+(\w+)\s*\(',
  multiLine: true,
);

/// Doors whose CALLER is deliberately not written yet, keyed `<path>:<method>`,
/// each with the reason and the release that deletes the entry.
///
/// This is the one shape the rule above cannot tell from dead code: a data
/// layer that ships **before** its own screens, on purpose. A build that cannot
/// read a measured component line crashes on one or drops it silently, so the
/// seam has to be on every device in the household a release before the
/// authoring UI exists to write one. The methods are covered by the repository
/// tests and by nothing in `lib/` until that UI lands.
///
/// It is an audit trail, not a place to silence a failure: an entry states who
/// will call it and when, and the day that door is built the entry goes with
/// the omission. An entry that outlives its release is the dead code this test
/// exists to find — by then the method has no future caller either.
const _callerPending = <String, String>{
  'lib/features/recipes/domain/recipe_measure_repository.dart:'
          'reorderRecipeMeasures':
      'the measures list’s grip. Drawn but not gestured in the first slice '
      '(ADR-0018, "out of the first slice"), so this one waits on the pass '
      'that adds the drag.',
};

void main() {
  test('every declared repository method has a caller in lib/', () {
    final interfaces = Directory('lib/features')
        .listSync()
        .whereType<Directory>()
        .map((f) => Directory('${f.path}/domain'))
        .where((d) => d.existsSync())
        .expand(dartFiles)
        .where((f) => f.path.endsWith('_repository.dart'))
        .toList();
    expect(interfaces, isNotEmpty, reason: 'no interfaces found — moved?');

    // The interfaces and the impls are not callers: an impl overriding a
    // method proves nothing about whether the app uses it. Everything else
    // under lib/ counts — the `data/*_providers.dart` files above all, which
    // are where the read doors actually call the watched queries.
    final declared = <String, String>{};
    for (final file in interfaces) {
      for (final m in _declaration.allMatches(
        blankNonCode(file.readAsStringSync()),
      )) {
        declared[m.group(1)!] = file.path;
      }
    }

    final callers = <String>{};
    for (final file in dartFiles(Directory('lib'))) {
      if (file.path.endsWith('_repository.dart') ||
          file.path.endsWith('_repository_impl.dart')) {
        continue;
      }
      final source = blankNonCode(file.readAsStringSync());
      for (final m in RegExp(r'\.(\w+)\s*\(').allMatches(source)) {
        callers.add(m.group(1)!);
      }
    }

    final orphans = [
      for (final entry in declared.entries)
        if (!callers.contains(entry.key) &&
            !_callerPending.containsKey('${entry.value}:${entry.key}'))
          '${entry.value}: ${entry.key}',
    ]..sort();

    expect(
      orphans,
      isEmpty,
      reason:
          'a repository method nothing in lib/ calls. Either the door it '
          'belongs to is gone — delete the declaration, the impl, the fakes '
          'and its tests — or its caller was never written:\n'
          '${orphans.join('\n')}',
    );
  });

  test('every _callerPending entry is still waiting on its door', () {
    // The exemption expires by itself: the day the door is built, the entry is
    // a lie and this fails, which is what keeps the list from becoming the
    // place orphans go to live.
    final built = <String>[];
    for (final key in _callerPending.keys) {
      final method = key.split(':').last;
      for (final file in dartFiles(Directory('lib'))) {
        if (file.path.endsWith('_repository.dart') ||
            file.path.endsWith('_repository_impl.dart')) {
          continue;
        }
        if (blankNonCode(file.readAsStringSync()).contains('.$method(')) {
          built.add('$key — now called from ${file.path}');
          break;
        }
      }
    }
    expect(
      built,
      isEmpty,
      reason:
          'a pending door has its caller now — drop its _callerPending entry, '
          'so the rule holds it like every other method:\n${built.join('\n')}',
    );
  });
}
