/// Structural test: nothing in `lib/` awaits `.future` on an autoDispose
/// provider.
///
/// An autoDispose provider only lives while somebody is listening to it. A
/// one-shot `await ref.read(fooProvider(id).future)` is not listening: it
/// creates the element, asks for its first value and lets go. Every read
/// provider in this app is backed by PowerSync's `watch`, which does NOT emit
/// synchronously, so the element is disposed before that first emission ever
/// lands and the future completes with `StateError: the provider … was
/// disposed during loading state`. The screen does not get a slow answer, it
/// gets a throw — and only for the async sources, which is why it survives
/// every test that stubs the data in.
///
/// It has shipped twice. The import review turned the throw into "no
/// measures", so "1 clove" of a garlic row carrying a `clove` measure
/// validated against an empty list and was flagged "Pick a supported unit";
/// the Week's add-an-ingredient flow let it escape as a red screen the first
/// time somebody planned frozen edamame.
///
/// The fix is one of two shapes: read the repository directly
/// (`ref.read(measureRepositoryProvider).measuresByIngredients({id})` — a
/// plain call has no element to lose), or `.future` a provider somebody is
/// genuinely watching, where the element outlives the read.
///
/// **What it checks.** Across `lib/` (generated sources aside) it collects
/// every autoDispose provider — a lowercase `@riverpod` annotation, or an
/// `@Riverpod(...)` whose arguments do not say `keepAlive: true`, on a
/// function or a class — and names it the way the generator does: a function
/// `foo` and a class `Foo` both become `fooProvider`. It then fails on any
/// `fooProvider.future` or `fooProvider(…).future` anywhere in `lib/`.
/// Comments and string literals are blanked first ([blankNonCode]), so prose
/// about the trap can neither trip it nor silence it.
///
/// **What it can be defeated by**, stated plainly because a regex over source
/// text should be honest about its reach: a provider aliased into a local
/// (`final p = fooProvider(id); await ref.read(p.future);`), a `.future`
/// reached through a helper that is handed the provider, and a family whose
/// argument list spans a `)` inside a nested call — the argument list is
/// matched by balancing one level of parentheses, not by parsing. It stops
/// the ordinary omission, not a determined author, which is the same reach
/// `no_ref_after_await_test.dart` claims and for the same reason.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

/// `@riverpod` (auto-dispose) or `@Riverpod(…)` (auto-dispose only when the
/// arguments do not say `keepAlive: true`), followed by the declaration it
/// annotates. Group 1 is the annotation's argument list, group 2 the declared
/// name — a class name or a function name, whichever the declaration is.
final _annotated = RegExp(
  r'@[Rr]iverpod\s*(\([^)]*\))?\s*'
  r'(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*'
  r'(?:class\s+(\w+)|(?:[\w<>,?\s.]+?\s+)?(\w+)\s*\()',
);

/// The provider name the generator gives a declaration called [declared]:
/// `Foo` → `fooProvider`, `foo` → `fooProvider`.
String providerNameOf(String declared) =>
    '${declared[0].toLowerCase()}${declared.substring(1)}Provider';

/// The autoDispose provider names declared in [source].
Set<String> autoDisposeProvidersIn(String source) {
  final text = blankNonCode(source);
  final names = <String>{};
  for (final m in _annotated.allMatches(text)) {
    final args = m.group(1) ?? '';
    if (args.contains('keepAlive:') && args.contains('true')) continue;
    final declared = m.group(2) ?? m.group(3);
    if (declared == null || declared.isEmpty) continue;
    names.add(providerNameOf(declared));
  }
  return names;
}

/// The offsets in [text] where one of [providers] is followed by `.future`,
/// with an optional balanced family argument list in between.
List<int> _futureReadsIn(String text, Set<String> providers) {
  final found = <int>[];
  final name = RegExp(r'\b([a-z]\w*Provider)\b');
  for (final m in name.allMatches(text)) {
    if (!providers.contains(m.group(1))) continue;
    var i = m.end;
    if (i < text.length && text[i] == '(') {
      var depth = 0;
      while (i < text.length) {
        if (text[i] == '(') depth++;
        if (text[i] == ')') {
          depth--;
          if (depth == 0) {
            i++;
            break;
          }
        }
        i++;
      }
    }
    if (text.startsWith('.future', i)) found.add(m.start);
  }
  return found;
}

void main() {
  test('the scan names autoDispose providers and skips kept-alive ones', () {
    const source = r'''
@riverpod
Stream<List<Measure>> ingredientMeasures(Ref ref, String id) => x;

@Riverpod(keepAlive: true)
MeasureRepository measureRepository(Ref ref) => y;

@riverpod
class IngredientForm extends _$IngredientForm {
  @override
  Draft build(String? id) => z;
}

@Riverpod(dependencies: [])
Future<int> pantryCount(Ref ref) async => 0;
''';
    expect(autoDisposeProvidersIn(source), {
      'ingredientMeasuresProvider',
      'ingredientFormProvider',
      'pantryCountProvider',
    });
  });

  test('the scan catches the shape it exists for, and accepts the fix', () {
    const providers = {'ingredientMeasuresProvider', 'vocabularyProvider'};

    const bad = '''
Future<Measure?> seed(WidgetRef ref, Ingredient ing) async {
  final all = await ref.read(ingredientMeasuresProvider(ing.id).future);
  final vocab = await ref.read(vocabularyProvider.future);
  return all.firstOrNull;
}
''';
    expect(_futureReadsIn(blankNonCode(bad), providers), hasLength(2));

    const fixed = '''
/// Never `ingredientMeasuresProvider(id).future` — see the library doc.
Future<Measure?> seed(MeasureRepository repo, Ingredient ing) async {
  final byId = await repo.measuresByIngredients({ing.id});
  return byId[ing.id]?.firstOrNull;
}
''';
    expect(_futureReadsIn(blankNonCode(fixed), providers), isEmpty);

    // A kept-alive provider's `.future` is not this bug, and neither is a
    // watched autoDispose provider read without `.future`.
    const allowed = '''
final repo = await ref.read(measureRepositoryProvider.future);
final live = ref.watch(ingredientMeasuresProvider(ing.id));
''';
    expect(_futureReadsIn(blankNonCode(allowed), providers), isEmpty);
  });

  test('no `.future` on an autoDispose provider anywhere in lib/', () {
    final files = dartFiles(Directory('lib'));
    expect(files, isNotEmpty, reason: 'no lib sources found — broken glob?');

    final sources = {for (final f in files) f.path: f.readAsStringSync()};
    final providers = <String>{
      for (final source in sources.values) ...autoDisposeProvidersIn(source),
    };
    expect(
      providers,
      isNotEmpty,
      reason: 'found no autoDispose providers — the annotation has drifted',
    );

    final violations = <String>[];
    for (final entry in sources.entries) {
      final text = blankNonCode(entry.value);
      for (final at in _futureReadsIn(text, providers)) {
        violations.add('${entry.key}:${lineOf(text, at)}');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'a one-shot `.future` on an autoDispose provider. Nobody is '
          "listening, PowerSync's watch does not emit synchronously, and the "
          'element is disposed before its first emission — the future '
          'completes with a StateError. Read the repository instead:'
          '\n${violations.join('\n')}',
    );
  });
}
