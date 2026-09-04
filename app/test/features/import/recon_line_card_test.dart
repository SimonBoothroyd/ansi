// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/recon_amount.dart';
import 'package:ansi/features/import/presentation/recon_line_card.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_chip.dart';
import 'package:ansi/shared/picker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_import_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';
import '_fixtures.dart';

/// One unmatched `none` line — the amount + notes must stay disabled until an
/// ingredient is chosen, and the "needs you" flag must clear once it is.
final _none = reconPayload([
  reconLine('mystery spice', band: MatchBand.none, rawAmount: 'a pinch'),
]);

/// One auto-matched line — resolved on arrival, but (owner refinement) still
/// fully editable.
final _auto = reconPayload([
  reconLine(
    'spaghetti',
    qty: 200,
    unit: 'g',
    rawAmount: '200g',
    ingredientId: 'ing-spag',
    canonicalName: 'Spaghetti',
    score: 0.98,
  ),
]);

/// An auto-matched line whose amount is an unpicked RANGE — the ingredient
/// must lock regardless of the range.
final _autoRange = reconPayload([
  reconLine(
    'garlic cloves, sliced',
    qtyLow: 2,
    qtyHigh: 3,
    unit: 'clove',
    rawAmount: '2–3 cloves',
    ingredientId: garlic.id,
    canonicalName: 'Garlic',
    score: 0.95,
  ),
]);

/// A matched line whose printed unit the ingredient cannot carry (`ml` on a
/// density-less garlic) — the "pick a supported unit" case.
final _unitMismatch = reconPayload([
  reconLine(
    'garlic',
    qty: 2,
    unit: 'ml',
    rawAmount: '2 ml',
    ingredientId: garlic.id,
    canonicalName: 'Garlic',
    score: 0.95,
  ),
]);

/// A printed cross-reference the server matched against a household recipe
/// TITLE, offered beside an ingredient candidate.
final _recipeOffer = reconPayload(title: 'Sausage Sliders', servingsBase: 8, [
  reconLine(
    'Romesco Aioli (page 38)',
    qty: 0.25,
    unit: 'cup',
    rawAmount: '¼ cup',
    band: MatchBand.suggest,
    ingredientId: 'ing-aioli',
    canonicalName: 'Aioli, jarred',
    score: 0.7,
    recipeCandidates: const [
      RecipeCandidate(recipeId: 'r-aioli', title: 'Romesco Aioli', score: 1),
    ],
  ),
]);

/// A `piece` line on a row whose measure names the thing. Post-curation (plan
/// 0022) `piece` is not in the row's `allowed_units`, so the shipped
/// `unitNotAllowed` machinery finally reaches this line.
ReconciliationPayload _piecePayload(String name, String ingredientId) =>
    reconPayload([
      reconLine(
        '1 large ripe $name',
        qty: 1,
        unit: 'piece',
        rawAmount: '1 large',
        ingredientId: ingredientId,
        canonicalName: name,
      ),
    ]);

/// "1 bunch cilantro, chopped" — the source named a THING the row does not
/// carry. Today's flag stands; the default answers a number and no thing.
final _bunch = reconPayload([
  reconLine(
    '1 bunch cilantro, chopped',
    qty: 1,
    unit: 'bunch',
    rawAmount: '1 bunch',
    ingredientId: cilantro.id,
    canonicalName: 'Cilantro',
  ),
]);

/// The household's recipes, as the component sheet reads them: one aioli that
/// says what a batch makes.
/// The one recipe a line may resolve to as a component, with the yield the
/// card divides by.
FakeRecipeRepository _recipeRepo() => FakeRecipeRepository(
  summaries: const [
    RecipeSummary(
      id: 'r-aioli',
      title: 'Romesco Aioli',
      servingsBase: 4,
      yieldQty: 1,
      yieldUnit: cup,
    ),
  ],
);

Widget _host(ProviderContainer container, {LineValidation? validation}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: FScaffold(child: _Body(validation: validation)),
        ),
      ),
    );

/// Renders the single expandable card for line 0 of the reconciling state.
/// Watching the provider at the top keeps the (autoDispose) controller alive.
class _Body extends ConsumerWidget {
  const _Body({this.validation});

  final LineValidation? validation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    return ListView(
      children: [
        ReviewLineCard(
          line: state.payload.flatLines[0],
          resolution: state.resolutions.firstWhere((r) => r.lineIndex == 0),
          validation: validation,
        ),
      ],
    );
  }
}

/// The card wired to the REAL validation provider (the review screen's own
/// wiring), so the ingredient + its measures resolve exactly as on device.
class _LiveBody extends ConsumerWidget {
  const _LiveBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    final byLine = ref.watch(importValidationProvider).value;
    return ListView(
      children: [
        ReviewLineCard(
          line: state.payload.flatLines[0],
          resolution: state.resolutions.firstWhere((r) => r.lineIndex == 0),
          validation: byLine?[0],
        ),
      ],
    );
  }
}

void main() {
  testWidgets('an auto line is compact, then expands into the editable card '
      '(re-match + amount + notes)', (tester) async {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(FakeImportRepo(_auto)),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // Compact by default: amount + name, no editors yet.
    expect(find.text('200 g'), findsOneWidget);
    expect(find.text('Spaghetti'), findsOneWidget);
    expect(find.text('NOTES'), findsNothing);

    // Tapping the pencil expands the same line in place.
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // The full editable card: re-match affordance + amount + notes.
    // (an auto line is re-matchable too)
    expect(find.text('tap to change'), findsOneWidget);
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.text('NOTES'), findsOneWidget);
  });

  testWidgets('editing the NOTES field writes through to the resolution', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(FakeImportRepo(_auto)),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'finely chopped');
    await tester.pumpAndSettle();

    final state = container.read(importControllerProvider) as ImportReconciling;
    final line0 = state.resolutions.firstWhere((r) => r.lineIndex == 0);
    expect(line0.notes, 'finely chopped');
  });

  testWidgets('an unmatched line disables amount + notes and shows a clear '
      '"needs you" flag that clears once matched', (tester) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(FakeImportRepo(_none)),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // Unmatched: a clear label (not a bare dot) + the fields locked.
    expect(find.text('Match an ingredient'), findsOneWidget);
    expect(
      find.textContaining('Match an ingredient first'),
      findsOneWidget, // the unlock hint under the disabled fields
    );
    final notesField = tester.widget<TextField>(find.byType(TextField));
    expect(notesField.enabled, isFalse);

    // Match it → the flag clears and notes unlock.
    container
        .read(importControllerProvider.notifier)
        .updateResolution(
          0,
          (r) => r.resolveToIngredient('ing-mystery', 'Mystery spice'),
        );
    await tester.pumpAndSettle();

    expect(find.text('Match an ingredient'), findsNothing);
    expect(find.textContaining('Match an ingredient first'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('an auto line locks its ingredient even with an unpicked range; '
      'only the amount is flagged', (tester) async {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(FakeImportRepo(_autoRange)),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // Ingredient LOCKED (not gated on the amount) — the re-match affordance
    // shows, and there is no "match an ingredient" prompt.
    expect(find.text('tap to change'), findsOneWidget);
    expect(find.text('Match an ingredient'), findsNothing);
    // The unpicked range is flagged separately.
    expect(find.text('Set the amount'), findsWidgets);
    // And the amount editor is live (matched → enabled).
    expect(find.byType(AmountEditor), findsOneWidget);
  });

  testWidgets('an unsupported unit is flagged (not shown ok) and offers valid '
      'unit chips that apply on tap', (tester) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(FakeImportRepo(_auto)),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));
    await tester.pumpWidget(
      _host(
        container,
        validation: const LineValidation(
          issues: [LineIssue.unitNotAllowed],
          unitChoices: [
            UnitSuggestion(token: 'g', label: 'g'),
            UnitSuggestion(token: 'piece', label: 'piece'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Flagged as needing a fix — never silently "ok".
    expect(find.text('Pick a supported unit'), findsWidgets);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // Inline unit chips, parallel to the ingredient pills.
    expect(find.text('UNIT'), findsOneWidget);
    expect(find.text('piece'), findsOneWidget);

    await tester.tap(find.text('piece'));
    await tester.pumpAndSettle();
    final updated =
        container.read(importControllerProvider) as ImportReconciling;
    expect(updated.resolutions.first.unit, 'piece');
  });

  testWidgets('the unit chips show five and fold the rest, expanding in place '
      'without losing the selection', (tester) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(FakeImportRepo(_auto)),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));
    await tester.pumpWidget(
      _host(
        container,
        validation: const LineValidation(
          issues: [LineIssue.unitNotAllowed],
          unitChoices: [
            UnitSuggestion(token: 'g', label: 'g'),
            UnitSuggestion(token: 'kg', label: 'kg'),
            UnitSuggestion(token: 'clove', label: 'clove'),
            UnitSuggestion(token: 'tsp', label: 'tsp'),
            UnitSuggestion(token: 'tbsp', label: 'tbsp'),
            UnitSuggestion(token: 'cup', label: 'cup'),
            UnitSuggestion(token: 'pinch', label: 'pinch'),
            UnitSuggestion(token: 'to_taste', label: 'to taste'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // Five chips, and the imprecise tail is behind the fold.
    expect(find.text('+3 more'), findsOneWidget);
    expect(find.text('to taste'), findsNothing);
    expect(find.text('pinch'), findsNothing);

    // The fold expands IN PLACE — same card, no sheet.
    await tester.tap(find.text('+3 more'));
    await tester.pumpAndSettle();
    expect(find.text('to taste'), findsOneWidget);
    expect(find.text('fewer'), findsOneWidget);

    // Picking a folded chip writes through, and the choice survives the fold.
    await tester.tap(find.text('to taste'));
    await tester.pumpAndSettle();
    final updated =
        container.read(importControllerProvider) as ImportReconciling;
    expect(updated.resolutions.first.unit, 'to_taste');
    expect(find.text('to taste'), findsOneWidget);
  });

  testWidgets('an inadmissible unit opens the amount editor on the '
      'ingredient’s count measure — one confirm tap resolves it', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(
          FakeImportRepo(_unitMismatch),
        ),
        ingredientRepositoryProvider.overrideWithValue(
          const OneRowIngredientRepo(garlic),
        ),
        measureRepositoryProvider.overrideWithValue(
          FakeMeasureRepo(const [garlicClove]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: const FScaffold(child: _LiveBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Flagged: "ml" is not a unit density-less garlic can carry.
    expect(find.text('Pick a supported unit'), findsWidgets);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AmountEditor));
    await tester.pumpAndSettle();

    // The sheet opened ON the measure — confirming adopts it, no chip hunt.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final updated =
        container.read(importControllerProvider) as ImportReconciling;
    expect(updated.resolutions.single.unit, 'clove');
    expect(updated.resolutions.single.quantity, 2);
    // And the flag clears now that the unit is one the ingredient carries.
    expect(find.text('Pick a supported unit'), findsNothing);
  });

  testWidgets('the '
      "amount sheet's Optional switch writes the line fact back onto the "
      'resolution', (tester) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(
          FakeImportRepo(_unitMismatch),
        ),
        ingredientRepositoryProvider.overrideWithValue(
          const OneRowIngredientRepo(garlic),
        ),
        measureRepositoryProvider.overrideWithValue(
          FakeMeasureRepo(const [garlicClove]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: const FScaffold(child: _LiveBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AmountEditor));
    await tester.pumpAndSettle();

    // The same sheet the editor uses, so the review gets the row for free.
    expect(find.text('Optional'), findsOneWidget);
    await tester.tap(find.byType(FSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final updated =
        container.read(importControllerProvider) as ImportReconciling;
    expect(updated.resolutions.single.optional, isTrue);
  });

  // --- plan 0022 / ADR-0010 · the board's frame (a) -------------------------
  //
  // "1 large ripe avocado" extracts as unit="piece" and used to commit as a
  // bare count that the macro engine honestly excluded — while the vocab held
  // avocado = 201 g. Nothing new is built for it: taking `piece` out of the
  // row's admission list is what finally switches the shipped machinery on.

  Future<void> pumpPieceLine(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: const FScaffold(child: _LiveBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // --- plan 0024 · seam D2 + D3 · the board's frames (a) and (b) ------------

  /// Where a `piece` line lands on arrival, by the shape of the row's measure
  /// set. `preselectedMeasure` used to pre-select the SHEET and never the
  /// LINE, so a sole-measure row stayed flagged until somebody opened and
  /// confirmed it. Writing the LINE means a line that named a number and no
  /// thing arrives on its curated default — or its sole measure — clean, with
  /// the fact said out loud on the card.
  ///
  /// The other three rows are the cases where arriving on something would be
  /// a lie: a set with no dominant member, a set of three equals, and a line
  /// that PRINTED a word of its own (cilantro's default IS `sprig` at 2.22 g
  /// and a bunch is ~25 of them, so applying it would be a silent 25× error).
  /// The model can say "I don't know", which a rule never can.
  final arrivals =
      <
        ({
          String what,
          ReconciliationPayload payload,
          Ingredient row,
          List<Measure> measures,
          String unit,
          String? countsAs,
        })
      >[
        (
          what: 'a sized row arrives on its curated default',
          payload: _piecePayload('Red Pepper', pepper.id),
          row: pepper,
          measures: pepperSizes,
          unit: 'pepper, medium',
          countsAs: 'counts as  pepper, medium · 119 g',
        ),
        (
          what: 'a SOLE-measure row arrives on it too',
          payload: _piecePayload('Cucumber', cucumber.id),
          row: cucumber,
          measures: const [cucumberMeasure],
          unit: 'cucumber',
          countsAs: 'counts as  cucumber · 301 g',
        ),
        (
          what: 'a fragment set has no default and stays flagged',
          payload: _piecePayload('Broccoli', broccoli.id),
          row: broccoli,
          measures: broccoliParts,
          unit: 'piece',
          countsAs: null,
        ),
        (
          what: 'three sizes pre-select nothing',
          payload: _piecePayload('Gold Potato', potato.id),
          row: potato,
          measures: potatoSizes,
          unit: 'piece',
          countsAs: null,
        ),
        (
          what: 'a line that PRINTED a word the row refuses is untouched',
          payload: _bunch,
          row: cilantro,
          measures: const [cilantroSprig],
          unit: 'bunch',
          countsAs: null,
        ),
      ];

  ProviderContainer pieceLineContainer(
    ReconciliationPayload payload,
    Ingredient row,
    List<Measure> measures, {
    FakeImportRepo? repo,
  }) {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(
          repo ?? FakeImportRepo(payload),
        ),
        ingredientRepositoryProvider.overrideWithValue(
          OneRowIngredientRepo(row),
        ),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo(measures)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  for (final c in arrivals) {
    testWidgets('${c.what} — it reads `${c.unit}`, and the alternatives are '
        'beside it', (tester) async {
      filterForuiSemanticsAssertions();
      final container = pieceLineContainer(c.payload, c.row, c.measures);
      await pumpPieceLine(tester, container);

      final resolved = c.countsAs != null;
      expect(
        find.text('Pick a supported unit'),
        resolved ? findsNothing : findsWidgets,
      );
      final state =
          container.read(importControllerProvider) as ImportReconciling;
      expect(state.resolutions.single.unit, c.unit);
      expect(state.resolutions.single.unitFromDefault, resolved);

      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      // The sentence that makes a default honest, shown at the moment it is
      // applied — and absent when nothing was applied.
      if (c.countsAs case final sentence?) {
        expect(find.textContaining(sentence), findsOne);
      } else {
        expect(find.textContaining('counts as'), findsNothing);
      }

      // The chips stay VISIBLE — the choice made for you, beside the ones you
      // could make instead. Hiding them would make tap-to-change invisible.
      expect(find.text('UNIT'), findsOneWidget);
      for (final m in c.measures) {
        expect(find.text(m.label), findsWidgets);
      }
      expect(find.text('piece'), findsNothing);
    });
  }

  testWidgets('one tap changes the size, and the card stops claiming the '
      'default answered', (tester) async {
    filterForuiSemanticsAssertions();
    final container = pieceLineContainer(
      _piecePayload('Red Pepper', pepper.id),
      pepper,
      pepperSizes,
    );
    await pumpPieceLine(tester, container);
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    await tester.tap(find.text('pepper, large').last);
    await tester.pumpAndSettle();
    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'pepper, large');
    expect(state.resolutions.single.unitFromDefault, isFalse);
    expect(find.textContaining('counts as'), findsNothing);
    expect(find.text('Pick a supported unit'), findsNothing);
  });

  testWidgets('a default the user never touched commits as a tapped chip would '
      '— the label rides through, with no provenance of its own', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    final repo = FakeImportRepo(_piecePayload('Cucumber', cucumber.id));
    final container = pieceLineContainer(
      _piecePayload('Cucumber', cucumber.id),
      cucumber,
      const [cucumberMeasure],
      repo: repo,
    );
    await pumpPieceLine(tester, container);

    await container
        .read(importControllerProvider.notifier)
        .commit(issuesByLine: const {0: []});
    expect(repo.committed!.groups.single.lines.single.unit, 'cucumber');
  });

  testWidgets('Save stays gated until the user picks one of three sizes — no '
      'medium tie-break, no first-in-sort_order guess', (tester) async {
    filterForuiSemanticsAssertions();
    final container = pieceLineContainer(
      _piecePayload('Gold Potato', potato.id),
      potato,
      potatoSizes,
    );
    await pumpPieceLine(tester, container);
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // Confirming the sheet without picking resolves NOTHING.
    await tester.tap(find.byType(AmountEditor));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    var state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'piece');
    expect(find.text('Pick a supported unit'), findsWidgets);

    // The user picks. That is the whole interaction.
    await tester.tap(find.text('potato, large'));
    await tester.pumpAndSettle();
    state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'potato, large');
    expect(find.text('Pick a supported unit'), findsNothing);
  });

  testWidgets('the bin drops the line into an "as deleted" card, and undo '
      'brings it back untouched', (tester) async {
    filterForuiSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(FakeImportRepo(_auto)),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.trash2));
    await tester.pumpAndSettle();

    // Greyed, labelled, and out of the editing surface entirely.
    expect(find.text('removed — this line will not be saved'), findsOneWidget);
    expect(find.text('AMOUNT'), findsNothing);
    final dropped =
        container.read(importControllerProvider) as ImportReconciling;
    expect(dropped.resolutions.single.isDropped, isTrue);
    // It stops being work: no flag, and nothing left unresolved.
    expect(dropped.unresolvedCount, 0);

    await tester.tap(find.text('undo'));
    await tester.pumpAndSettle();
    final back = container.read(importControllerProvider) as ImportReconciling;
    expect(back.resolutions.single.isDropped, isFalse);
    expect(back.resolutions.single.chosenName, 'Spaghetti');
    expect(find.text('200 g'), findsOneWidget);
  });

  // --- Step 8.6 / D6 · board frame (e) -------------------------------------

  group('a recipe offered at review, never auto-linked', () {
    Future<ProviderContainer> reviewing() async {
      final container = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
          importRepositoryProvider.overrideWithValue(
            FakeImportRepo(_recipeOffer),
          ),
          recipeRepositoryProvider.overrideWithValue(_recipeRepo()),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(importControllerProvider.notifier)
          .startImport(const ImportFromUrl('x'));
      return container;
    }

    testWidgets('the offer rides the did-you-mean row BESIDE the ingredient '
        'candidates — and nothing is linked until it is tapped', (
      tester,
    ) async {
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();

      // Arrival: unlinked, and the tag names both doors.
      final arrived =
          container.read(importControllerProvider) as ImportReconciling;
      expect(arrived.resolutions.single.isComponent, isFalse);
      expect(
        find.text('Match an ingredient — or link your recipe'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      // One chip row, both kinds of answer in it.
      expect(find.text('Did you mean'), findsOneWidget);
      expect(find.text('your recipe · Romesco Aioli'), findsOneWidget);
      expect(find.text('Aioli, jarred'), findsOneWidget);
      expect(find.byIcon(kSubRecipeIcon), findsOneWidget);
      // Still nothing linked by rendering it.
      expect(
        (container.read(importControllerProvider) as ImportReconciling)
            .resolutions
            .single
            .isComponent,
        isFalse,
      );
    });

    testWidgets('tapping the chip links the line: recipe chip, no ingredient, '
        'no allowed-units gate, valid for Save', (tester) async {
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      await tester.tap(find.text('your recipe · Romesco Aioli'));
      await tester.pumpAndSettle();

      final linked =
          (container.read(importControllerProvider) as ImportReconciling)
              .resolutions
              .single;
      expect(linked.linkedRecipeId, 'r-aioli');
      expect(linked.chosenIngredientId, isNull);
      // Its amount was already printed, so it is valid the moment it links.
      expect(linked.isResolved, isTrue);
      expect(lineIssues(linked), isEmpty);

      // The card says the two rules a linked line lives by…
      expect(find.textContaining('no ingredient match needed'), findsOneWidget);
      // …and the identity cell is lane U's recipe chip, with the unlink beside
      // it. (Two: the expanded card's cell — the collapsed row is not built.)
      expect(find.text('Romesco Aioli'), findsWidgets);
      expect(find.text('unlink'), findsOneWidget);
      // No ingredient prompt survives.
      expect(find.text('Match an ingredient'), findsNothing);
      expect(
        find.text('Match an ingredient — or link your recipe'),
        findsNothing,
      );
    });

    testWidgets('the link is reversible before Save — unlink puts the line '
        'back exactly as it arrived', (tester) async {
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();
      await tester.tap(find.text('your recipe · Romesco Aioli'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('unlink'));
      await tester.pumpAndSettle();

      final back =
          (container.read(importControllerProvider) as ImportReconciling)
              .resolutions
              .single;
      expect(back.isComponent, isFalse);
      expect(back.quantity, 0.25); // the printed amount is not disturbed
      // The offer is on the card again, unanswered.
      expect(find.text('your recipe · Romesco Aioli'), findsOneWidget);
      expect(
        find.text('Match an ingredient — or link your recipe'),
        findsOneWidget,
      );
    });

    testWidgets('a linked line with no amount is flagged "Set the amount" — '
        'its only gate', (tester) async {
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      container
          .read(importControllerProvider.notifier)
          .updateResolution(
            0,
            (r) => r.linkToRecipe('r-aioli', 'Romesco Aioli').setAmount(),
          );
      await tester.pumpAndSettle();

      expect(find.text('Set the amount'), findsWidgets);
      expect(
        (container.read(importControllerProvider) as ImportReconciling)
            .canCommit,
        isFalse,
      );
    });

    testWidgets('editing a linked amount opens the COMPONENT sheet — batch '
        'chips against the target’s yield, not an ingredient’s units', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      final container = await reviewing();
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();
      await tester.tap(find.text('your recipe · Romesco Aioli'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AmountEditor));
      await tester.pumpAndSettle();

      // Lane U's sheet, reading the target's yields off the local repository.
      expect(find.text('makes 1 cup · your recipe'), findsOneWidget);
      expect(find.textContaining('0.25 of a batch'), findsOneWidget);
      expect(find.text('batch'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final saved =
          (container.read(importControllerProvider) as ImportReconciling)
              .resolutions
              .single;
      expect(saved.quantity, 0.25);
      expect(saved.unit, 'cup');
    });
  });

  group(
    'a pick lands even when the card is gone by the time the sheet closes',
    () {
      // The review is a viewport. On a phone the search sheet's keyboard
      // shrinks it, and the card that opened the sheet can scroll out and
      // UNMOUNT while the sheet is still open. Riverpod 3 throws on a
      // `WidgetRef` used after unmount, so the pick was lost (owner field
      // report, 2026-09-03: "swapped wild garlic for kale, it didn't set") —
      // and the amount sheets share the shape. The pick must land regardless
      // of what happened to the card underneath.
      testWidgets('the search sheet resolves the line through the controller, '
          'not the unmounted card', (tester) async {
        filterForuiSemanticsAssertions();
        const kale = Ingredient(
          id: 'ing-kale',
          canonicalName: 'Kale',
          defaultUnit: g,
          status: IngredientStatus.complete,
        );
        final container = ProviderContainer(
          overrides: [
            bookRepositoryProvider.overrideWithValue(
              const FakeBookRepository(),
            ),
            importRepositoryProvider.overrideWithValue(FakeImportRepo(_none)),
            ingredientRepositoryProvider.overrideWithValue(
              FakeIngredientRepo(const [kale]),
            ),
            measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
            usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
          ],
        );
        addTearDown(container.dispose);
        await container
            .read(importControllerProvider.notifier)
            .startImport(const ImportFromUrl('x'));

        final showCard = ValueNotifier(true);
        addTearDown(showCard.dispose);
        await tester.pumpWidget(_toggleHost(container, showCard));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(FLucideIcons.pencil));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Find or create ingredient'));
        await tester.pumpAndSettle();
        expect(find.byType(PickerShell), findsOneWidget);

        // The card leaves the tree while the sheet is up.
        showCard.value = false;
        await tester.pumpAndSettle();
        expect(find.byType(ReviewLineCard), findsNothing);
        expect(find.byType(PickerShell), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byType(PickerShell),
            matching: find.text('Kale'),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final state = container.read(importControllerProvider);
        final line = (state as ImportReconciling).resolutions.single;
        expect(line.chosenIngredientId, 'ing-kale');
        expect(line.chosenName, 'Kale');
        expect(
          line.isCorrection,
          isTrue,
          reason: 'a search pick is a correction',
        );
      });
    },
  );

  group('the expanded card heads with what the line IS (C-D1)', () {
    /// The card's HEADING specifically — the identity chip below it prints
    /// the same word one point smaller, so plain `find.text` cannot tell the
    /// heading from the thing it is supposed to agree with.
    Finder heading(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.data == text && w.style?.fontSize == 15,
    );

    Future<ProviderContainer> reviewing(ReconciliationPayload payload) async {
      final container = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
          importRepositoryProvider.overrideWithValue(FakeImportRepo(payload)),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(importControllerProvider.notifier)
          .startImport(const ImportFromUrl('x'));
      return container;
    }

    testWidgets('a re-matched line reads as its new identity, and '
        '"from source" still prints the page’s words', (tester) async {
      filterForuiSemanticsAssertions();
      final container = await reviewing(_auto);
      // The move the owner reported: the page said "spaghetti", the cook
      // re-matched it to something else entirely.
      container
          .read(importControllerProvider.notifier)
          .updateResolution(
            0,
            (r) => r.resolveToIngredient('ing-kale', 'Kale', correction: true),
          );

      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      expect(heading('Kale'), findsOneWidget);
      // The old words are NOT the heading any more…
      expect(heading('spaghetti'), findsNothing);
      // …but they are still on the card, where the page's words belong.
      expect(find.text('from source:  200g spaghetti'), findsOneWidget);
    });

    testWidgets('an untouched line still heads with the page’s own words', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      final container = await reviewing(_none);
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      // No identity yet, so the heading falls back to the source text — and
      // the `from source:` line under it prints the amount too.
      expect(heading('mystery spice'), findsOneWidget);
      expect(find.text('from source:  a pinch mystery spice'), findsOneWidget);
    });
  });
}

/// [_host], but the card can be removed from the tree mid-flow — the state
/// stays watched at the top so the (autoDispose) controller lives on.
Widget _toggleHost(ProviderContainer container, ValueNotifier<bool> show) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: FScaffold(
            child: ValueListenableBuilder<bool>(
              valueListenable: show,
              builder: (_, visible, _) =>
                  visible ? const _Body() : const _Watcher(),
            ),
          ),
        ),
      ),
    );

/// Keeps the controller alive without rendering a card.
class _Watcher extends ConsumerWidget {
  const _Watcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(importControllerProvider);
    return const SizedBox.shrink();
  }
}
