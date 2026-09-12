/// The hard page, end to end on the host: a recipe written in a British
/// kitchen's words against a vocabulary stored in an American one's, which is
/// the import whose answers are only in the picker's search.
///
/// The payload is [peanutStirFryPayloadJson] — the bands the REAL cascade
/// returns for this page against the seeded vocabulary — and the vocabulary
/// below mirrors the seeded rows those bands were computed over. What is
/// asserted here is the BEHAVIOUR the specs promise, line by line: which lines
/// arrive matched, which want the user, and that every one of them can be
/// re-pointed at any vocabulary row — or at a row the review just created —
/// with the choice surviving into the commit.
///
/// The two moves the owner reported as broken are driven through the real
/// widgets, not through the notifier: substituting Cilantro for the merely
/// suggested *coriander* line, and setting *sugar snap peas* to *Frozen Peas*.
library;

// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'dart:convert';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/data/sample_payloads.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/recon_line_card.dart';
import 'package:ansi/features/import/presentation/reconciliation_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_picker.dart';
import 'package:ansi/shared/picker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_import_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';

// --- The seeded rows this recipe's lines can land on -------------------------
//
// Modelled on `supabase/seed/snapshot.jsonl` and the seed's own R1 invariant (a
// volume `default_unit` requires a density), so a line printing `tbsp` or `g`
// is admitted here exactly as the synced row would admit it.

const _cilantro = Ingredient(
  id: 'ing-cilantro',
  canonicalName: 'Cilantro',
  defaultUnit: cup,
  category: 'produce',
  densityGPerMl: 0.068,
  status: IngredientStatus.complete,
);
const _frozenPeas = Ingredient(
  id: 'ing-frozen-peas',
  canonicalName: 'Frozen Peas',
  defaultUnit: lb,
  category: 'produce',
  status: IngredientStatus.complete,
);
const _spinach = Ingredient(
  id: 'ing-spinach',
  canonicalName: 'Spinach',
  defaultUnit: cup,
  category: 'produce',
  densityGPerMl: 0.13,
  status: IngredientStatus.complete,
);
const _groundCoriander = Ingredient(
  id: 'ing-ground-coriander',
  canonicalName: 'Ground Coriander',
  defaultUnit: tsp,
  category: 'spices & seasoning',
  densityGPerMl: 0.34,
  status: IngredientStatus.complete,
);
const _extraFirmTofu = Ingredient(
  id: 'ing-extra-firm-tofu',
  canonicalName: 'Extra Firm Tofu',
  defaultUnit: oz,
  category: 'proteins',
  densityGPerMl: 1.07,
  status: IngredientStatus.complete,
);
const _peanutButter = Ingredient(
  id: 'ing-peanut-butter',
  canonicalName: 'Peanut Butter',
  defaultUnit: tbsp,
  category: 'pantry',
  densityGPerMl: 1.09,
  status: IngredientStatus.complete,
);
const _tamari = Ingredient(
  id: 'ing-tamari',
  canonicalName: 'Tamari',
  defaultUnit: tbsp,
  category: 'pantry',
  densityGPerMl: 1.22,
  status: IngredientStatus.complete,
);
const _limeJuice = Ingredient(
  id: 'ing-lime-juice',
  canonicalName: 'Lime Juice',
  defaultUnit: tbsp,
  category: 'produce',
  densityGPerMl: 1.02,
  status: IngredientStatus.complete,
);
const _peanutOil = Ingredient(
  id: 'ing-peanut-oil',
  canonicalName: 'Peanut Oil',
  defaultUnit: tbsp,
  category: 'fats & oils',
  densityGPerMl: 0.91,
  status: IngredientStatus.complete,
);
const _napaCabbage = Ingredient(
  id: 'ing-napa-cabbage',
  canonicalName: 'Napa Cabbage',
  defaultUnit: pieces,
  category: 'produce',
  densityGPerMl: 0.32,
  status: IngredientStatus.complete,
);
const _seaSalt = Ingredient(
  id: 'ing-sea-salt',
  canonicalName: 'Sea Salt',
  defaultUnit: tsp,
  category: 'spices & seasoning',
  densityGPerMl: 1.2,
  status: IngredientStatus.complete,
);
const _blackPepper = Ingredient(
  id: 'ing-black-pepper',
  canonicalName: 'Black Pepper',
  defaultUnit: tsp,
  category: 'spices & seasoning',
  densityGPerMl: 0.46,
  status: IngredientStatus.complete,
);

const _vocab = [
  _cilantro,
  _frozenPeas,
  _spinach,
  _groundCoriander,
  _extraFirmTofu,
  _peanutButter,
  _tamari,
  _limeJuice,
  _peanutOil,
  _napaCabbage,
  _seaSalt,
  _blackPepper,
];

/// The candidate id the payload's placeholder stands for, by canonical name —
/// the re-point `SqliteImportRepository` does against the real vocab.
const _idByName = {
  'Extra Firm Tofu': 'ing-extra-firm-tofu',
  'Ground Coriander': 'ing-ground-coriander',
  'Peanut Butter': 'ing-peanut-butter',
  'Tamari': 'ing-tamari',
  'Lime Juice': 'ing-lime-juice',
  'Sea Salt': 'ing-sea-salt',
  'Black Pepper': 'ing-black-pepper',
};

ReconciliationPayload _payload() {
  final raw = ReconciliationPayload.fromJson(
    jsonDecode(peanutStirFryPayloadJson) as Map<String, Object?>,
  );
  return raw.copyWith(
    groups: [
      for (final g in raw.groups)
        g.copyWith(
          lines: [
            for (final l in g.lines)
              l.copyWith(
                candidates: [
                  for (final c in l.candidates)
                    c.copyWith(
                      ingredientId:
                          _idByName[c.canonicalName] ?? c.ingredientId,
                    ),
                ],
              ),
          ],
        ),
    ],
  );
}

/// A vocabulary that answers the picker's search by name rather than handing
/// back everything, and — like the real repository — falls through to a
/// GUESSED band when nothing was spelled right.
class _SearchableVocab extends FakeIngredientRepo {
  _SearchableVocab() : super(_vocab);

  /// What the typo tier answers with when nothing spells. Empty by default:
  /// the guarded tier usually finds nothing, and a suite that wants the band
  /// says so.
  List<Ingredient> guesses = const [];

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return (rows: [...rows], guessed: false);
    final spelled = [
      for (final r in rows)
        if (r.canonicalName.toLowerCase().contains(q)) r,
    ];
    if (spelled.isNotEmpty) return (rows: spelled, guessed: false);
    return (rows: guesses, guessed: guesses.isNotEmpty);
  }
}

/// A vocabulary whose bulk read fails — what the Save gate's own check runs
/// on. [broken] is cleared to let a retry succeed.
class _FailingVocab extends _SearchableVocab {
  bool broken = true;

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async {
    if (broken) throw StateError('the vocabulary could not be read');
    return {
      for (final r in rows)
        if (ids.contains(r.id)) r.id: r,
    };
  }
}

/// The review screen, hosted the way `/import` hosts it, with the flesh-out
/// form stubbed to the one thing this suite needs from it: one Save that
/// writes the row and pops with it.
Future<FakeImportRepo> _pumpReview(
  WidgetTester tester, {
  required _SearchableVocab vocab,
}) async {
  filterForuiSemanticsAssertions();
  final importRepo = FakeImportRepo(_payload());
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(importControllerProvider);
            return FScaffold(
              childPad: false,
              child: state is ImportReconciling
                  ? ReconciliationBody(state: state)
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
      GoRoute(
        path: '/ingredients/new',
        builder: (context, state) => FScaffold(
          child: FButton(
            onPress: () async {
              // The form only offers Save once the row would COUNT, and its
              // one write lands the status flip too — so the stand-in carries
              // macros and marks complete, as the real one does.
              final saved = await vocab.saveForm(
                null,
                IngredientFormEdit(
                  row: IngredientEdit(
                    canonicalName: state.uri.queryParameters['name'] ?? '',
                    defaultUnit: g,
                    macrosBasis: MacrosBasis.perG,
                    allowedUnits: {g, kg},
                    macros: const Macros(
                      kcal: 108,
                      protein: 6,
                      carb: 19,
                      fat: 1,
                    ),
                  ),
                  markComplete: true,
                ),
              );
              if (context.mounted) context.pop(saved.valueOrNull);
            },
            child: const Text('one save'),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        importRepositoryProvider.overrideWithValue(importRepo),
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        ingredientRepositoryProvider.overrideWithValue(vocab),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) =>
            FTheme(data: ansiThemeData(), child: child!),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
  await container
      .read(importControllerProvider.notifier)
      .startImport(const ImportFromUrl('x'));
  await tester.pumpAndSettle();
  return importRepo;
}

ImportReconciling _state(WidgetTester tester) =>
    ProviderScope.containerOf(
          tester.element(find.byType(MaterialApp)),
          listen: false,
        ).read(importControllerProvider)
        as ImportReconciling;

Finder _card(int i) => find.byKey(ValueKey('review-line-$i'));

/// Expands review card [i] — the card list is a viewport, so scroll first.
/// The review hosts several scrollables (the header form, the method editor);
/// the outermost one is the card list.
Future<void> _expand(WidgetTester tester, int i) async {
  await tester.scrollUntilVisible(
    _card(i),
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  final open = find.descendant(of: _card(i), matching: find.text('AMOUNT'));
  if (open.evaluate().isNotEmpty) return;
  final pencil = find.descendant(
    of: _card(i),
    matching: find.byIcon(FLucideIcons.pencil),
  );
  await tester.tap(pencil.first);
  await tester.pumpAndSettle();
}

/// Opens line [i]'s resolver sheet, types [query], and taps the row named
/// [pick] — the owner's exact move.
Future<void> _rematch(
  WidgetTester tester,
  int i, {
  required String query,
  required String pick,
}) async {
  await _expand(tester, i);
  final door = find.descendant(
    of: _card(i),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data == 'Find or create ingredient' ||
              w.data == 'Something else' ||
              w.data == 'tap to change'),
    ),
  );
  expect(door, findsWidgets, reason: 'line $i has no way into the picker');
  await tester.ensureVisible(door.first);
  await tester.pumpAndSettle();
  await tester.tap(door.first);
  await tester.pumpAndSettle();
  expect(find.byType(PickerShell), findsOneWidget);

  await tester.enterText(
    find.descendant(
      of: find.byType(PickerShell),
      matching: find.byType(EditableText),
    ),
    query,
  );
  await tester.pumpAndSettle();
  final row = find.descendant(
    of: find.byType(IngredientResultList),
    matching: find.text(pick),
  );
  expect(row, findsOneWidget, reason: 'the picker never offered "$pick"');
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void main() {
  group('the page as the cascade really banded it', () {
    test('three lines arrive unmatched and one arrives merely suggested', () {
      final payload = _payload();
      expect(
        [for (final l in payload.flatLines) l.band],
        const [
          MatchBand.none, // pak choi
          MatchBand.none, // groundnut oil
          MatchBand.auto, // extra firm tofu
          MatchBand.suggest, // coriander
          MatchBand.auto, // peanut butter
          MatchBand.auto, // tamari
          MatchBand.none, // sugar snap peas
          MatchBand.auto, // lime juice
          MatchBand.auto, // Sea salt
          MatchBand.auto, // black pepper
        ],
      );
      // A `none` line carries no candidates at all — §6's third tier. The
      // review screen's only answer for it is the search.
      for (final i in [0, 1, 6]) {
        expect(payload.flatLines[i].candidates, isEmpty);
      }
    });

    test('only the auto lines adopt a match on arrival', () {
      final resolutions = initialResolutions(_payload());
      final matched = {
        for (final r in resolutions)
          if (r.chosenIngredientId != null) r.lineIndex: r.chosenName,
      };
      expect(matched, {
        2: 'Extra Firm Tofu',
        4: 'Peanut Butter',
        5: 'Tamari',
        7: 'Lime Juice',
        8: 'Sea Salt',
        9: 'Black Pepper',
      });
      // The suggested line is NOT adopted: a suggestion the user never saw is
      // not a match.
      expect(resolutions[3].chosenIngredientId, isNull);
    });
  });

  group('every line can be re-pointed, and the choice reaches the commit', () {
    test(
      'the suggested coriander line takes Cilantro, and it sticks',
      () async {
        final container = ProviderContainer(
          overrides: [
            importRepositoryProvider.overrideWithValue(
              FakeImportRepo(_payload()),
            ),
            bookRepositoryProvider.overrideWithValue(
              const FakeBookRepository(),
            ),
            ingredientRepositoryProvider.overrideWithValue(_SearchableVocab()),
            measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(importControllerProvider.notifier);
        await controller.startImport(const ImportFromUrl('x'));

        controller.updateResolution(
          3,
          (r) => r.resolveToIngredient(
            _cilantro.id,
            _cilantro.canonicalName,
            correction: true,
          ),
        );
        final after =
            container.read(importControllerProvider) as ImportReconciling;
        final line = after.resolutions[3];
        expect(line.chosenIngredientId, _cilantro.id);
        expect(line.chosenName, 'Cilantro');
        // The printed word survives the swap: the page said a handful of it.
        expect(line.unit, 'handful');
        expect(line.quantity, isNull);
        // And the printed imprecise word is admitted on its own line, so the
        // line is DONE — not merely matched-and-still-flagged.
        expect(
          lineIssues(line, ingredient: _cilantro),
          isEmpty,
          reason: 'a re-matched line that admits its printed word is clean',
        );
      },
    );

    test('sugar snap peas take Frozen Peas — the vocabulary has no snap peas '
        'row, so the frozen one IS the answer', () async {
      final container = ProviderContainer(
        overrides: [
          importRepositoryProvider.overrideWithValue(
            FakeImportRepo(_payload()),
          ),
          bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
          ingredientRepositoryProvider.overrideWithValue(_SearchableVocab()),
          measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(importControllerProvider.notifier);
      await controller.startImport(const ImportFromUrl('x'));
      controller.updateResolution(
        6,
        (r) => r.resolveToIngredient(
          _frozenPeas.id,
          _frozenPeas.canonicalName,
          correction: true,
        ),
      );
      final line =
          (container.read(importControllerProvider) as ImportReconciling)
              .resolutions[6];
      expect(line.chosenIngredientId, _frozenPeas.id);
      expect(line.unit, 'g');
      expect(lineIssues(line, ingredient: _frozenPeas), isEmpty);
    });

    test('every line resolves, and the commit carries the chosen ids '
        'plus one correction alias per override', () async {
      final repo = FakeImportRepo(_payload());
      final container = ProviderContainer(
        overrides: [
          importRepositoryProvider.overrideWithValue(repo),
          bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
          ingredientRepositoryProvider.overrideWithValue(_SearchableVocab()),
          measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(importControllerProvider.notifier);
      await controller.startImport(const ImportFromUrl('x'));

      // The four lines the review has to answer, each re-pointed at a real
      // vocabulary row — including the `suggest` line, whose one offered chip
      // (Ground Coriander) is the wrong jar.
      const picks = {
        0: _napaCabbage,
        1: _peanutOil,
        3: _cilantro,
        6: _frozenPeas,
      };
      for (final e in picks.entries) {
        controller.updateResolution(
          e.key,
          (r) => r.resolveToIngredient(
            e.value.id,
            e.value.canonicalName,
            correction: true,
          ),
        );
      }
      final state =
          container.read(importControllerProvider) as ImportReconciling;
      expect(state.canCommit, isTrue);

      final byId = {for (final i in _vocab) i.id: i};
      final issues = {
        for (final r in state.resolutions)
          r.lineIndex: lineIssues(r, ingredient: byId[r.chosenIngredientId]),
      };
      expect(
        {
          for (final e in issues.entries)
            if (e.value.isNotEmpty) e.key: e.value,
        },
        isEmpty,
        reason: 'every line of this page should be clean once matched',
      );

      await controller.commit(issuesByLine: issues);
      final committed = repo.committed!;
      final lines = committed.groups.expand((g) => g.lines).toList();
      expect(lines, hasLength(10));
      expect(lines[0].ingredientId, _napaCabbage.id);
      expect(lines[1].ingredientId, _peanutOil.id);
      expect(lines[3].ingredientId, _cilantro.id);
      expect(lines[6].ingredientId, _frozenPeas.id);
      expect(lines[2].ingredientId, _extraFirmTofu.id);
      // The learning loop: each override writes the printed text back as an
      // alias of the row the human chose, so the next import matches it.
      expect(
        {for (final c in committed.corrections) c.aliasText: c.ingredientId},
        {
          'pak choi': _napaCabbage.id,
          'groundnut oil': _peanutOil.id,
          'coriander': _cilantro.id,
          'sugar snap peas': _frozenPeas.id,
        },
      );
    });

    test(
      'any line can be re-pointed at any row, auto matches included',
      () async {
        final container = ProviderContainer(
          overrides: [
            importRepositoryProvider.overrideWithValue(
              FakeImportRepo(_payload()),
            ),
            bookRepositoryProvider.overrideWithValue(
              const FakeBookRepository(),
            ),
            ingredientRepositoryProvider.overrideWithValue(_SearchableVocab()),
            measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(importControllerProvider.notifier);
        await controller.startImport(const ImportFromUrl('x'));

        for (var i = 0; i < 10; i++) {
          controller.updateResolution(
            i,
            (r) => r.resolveToIngredient(
              _spinach.id,
              _spinach.canonicalName,
              correction: true,
            ),
          );
          final r =
              (container.read(importControllerProvider) as ImportReconciling)
                  .resolutions[i];
          expect(
            r.chosenIngredientId,
            _spinach.id,
            reason: 'line $i refused a re-match',
          );
        }
      },
    );
  });

  group("the owner's two moves, through the real card", () {
    testWidgets('substituting Cilantro for coriander lands on the card and in '
        'the controller', (tester) async {
      final vocab = _SearchableVocab();
      await _pumpReview(tester, vocab: vocab);
      expect(_state(tester).resolutions[3].chosenIngredientId, isNull);

      await _rematch(tester, 3, query: 'cilantro', pick: 'Cilantro');

      expect(
        _state(tester).resolutions[3].chosenIngredientId,
        _cilantro.id,
        reason: 'the pick never reached the controller',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _card(3), matching: find.text('Cilantro')),
        findsWidgets,
        reason: 'the card still shows the old identity',
      );
    });

    testWidgets('sugar snap peas can be set to Frozen Peas from an EMPTY '
        'candidate list', (tester) async {
      final vocab = _SearchableVocab();
      await _pumpReview(tester, vocab: vocab);

      await _rematch(tester, 6, query: 'frozen', pick: 'Frozen Peas');

      expect(_state(tester).resolutions[6].chosenIngredientId, _frozenPeas.id);
    });

    testWidgets('an unmatched line can be answered by creating a row through '
        'the form, and the line resolves to it', (tester) async {
      final vocab = _SearchableVocab();
      await _pumpReview(tester, vocab: vocab);

      await _expand(tester, 0);
      final door = find.descendant(
        of: _card(0),
        matching: find.text('Find or create ingredient'),
      );
      await tester.ensureVisible(door);
      await tester.pumpAndSettle();
      await tester.tap(door);
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('as a new ingredient'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('one save'));
      await tester.pumpAndSettle();

      final created = vocab.rows.last;
      expect(created.canonicalName, 'pak choi');
      expect(
        _state(tester).resolutions[0].chosenIngredientId,
        created.id,
        reason: 'the created row never landed on the line',
      );
    });
  });

  group('what the screen says about a line it understood', () {
    // The extractor really returns `unit: "to_taste", unit_mappable: false`
    // for a bare seasoning line: `to_taste` IS a catalog word, and it is also
    // not a measurable unit, so the flag is `false` by the gold convention.
    // Reading that as "we could not read this word" flags two lines of every
    // seasoned recipe for a word the import surface already admits.
    test('an imprecise word the catalog carries is not "needs a look"', () {
      final payload = _payload();
      for (final i in [8, 9]) {
        final raw = payload.flatLines[i].raw;
        expect(raw.unitMappable, isFalse);
        expect(raw.unit, 'to_taste');
        expect(
          unitNeedsALook(raw),
          isFalse,
          reason: 'line $i printed a word the app resolves and admits',
        );
      }
    });

    test('a phrase nothing can resolve still says so', () {
      const raw = RawLineItem(
        ingredientText: 'ginger',
        unit: 'thumb-sized piece',
        unitMappable: false,
        rawAmount: 'a thumb-sized piece of ginger',
      );
      expect(unitNeedsALook(raw), isTrue);
    });

    testWidgets('the two seasoning lines carry no unit flag', (tester) async {
      await _pumpReview(tester, vocab: _SearchableVocab());
      for (final i in [8, 9]) {
        await _expand(tester, i);
        expect(
          find.descendant(
            of: _card(i),
            matching: find.textContaining('needs a look'),
          ),
          findsNothing,
          reason: 'line $i is matched, valid, and wants nothing',
        );
      }
    });

    testWidgets('a Save gate whose check failed says so, and the button is '
        'the retry', (tester) async {
      final vocab = _FailingVocab();
      await _pumpReview(tester, vocab: vocab);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );
      final controller = container.read(importControllerProvider.notifier);
      for (final e in const {
        0: _napaCabbage,
        1: _peanutOil,
        3: _cilantro,
        6: _frozenPeas,
      }.entries) {
        controller.updateResolution(
          e.key,
          (r) => r.resolveToIngredient(e.value.id, e.value.canonicalName),
        );
      }
      await tester.pumpAndSettle();

      // Every line is matched, so the structural count is zero — and saying
      // "0 line(s) need you" over a Save that will not open is a wall.
      final footer = find.textContaining(
        RegExp('Save recipe|need you|check the lines'),
      );
      await tester.scrollUntilVisible(
        footer,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('0 line(s) need you'), findsNothing);
      expect(find.textContaining('Couldn’t check the lines'), findsOneWidget);

      // The button is the door: re-running the read is the whole fix.
      vocab.broken = false;
      // `scrollUntilVisible` stops as soon as the finder MATCHES, and a lazy
      // list builds a little past the fold — so the button can be found and
      // still be a few pixels off-screen, where a tap lands on nothing.
      await tester.ensureVisible(
        find.textContaining('Couldn’t check the lines'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Couldn’t check the lines'));
      await tester.pumpAndSettle();
      expect(find.text('Save recipe'), findsOneWidget);
    });

    testWidgets('a guessed result list is banded in the review picker too', (
      tester,
    ) async {
      final vocab = _SearchableVocab()..guesses = const [_frozenPeas];
      await _pumpReview(tester, vocab: vocab);
      await _expand(tester, 6);
      final door = find.descendant(
        of: _card(6),
        matching: find.text('Find or create ingredient'),
      );
      await tester.ensureVisible(door);
      await tester.pumpAndSettle();
      await tester.tap(door);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(PickerShell),
          matching: find.byType(EditableText),
        ),
        'frozn',
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(DidYouMeanHeader),
        findsOneWidget,
        reason:
            'an unbanded guess in the picker that writes an alias and commits '
            'a recipe is the phone resolving, not offering',
      );
    });
  });
}
