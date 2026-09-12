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

/// One unmatched line the page itself flagged optional — the seed the card's
/// pill opens on.
final _rawOptional = reconPayload([
  reconLine(
    'coriander, to serve',
    band: MatchBand.none,
    rawAmount: 'a handful',
    optional: true,
  ),
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

/// A `piece` line on a row whose measure names the thing. `piece` is not in
/// the row's `allowed_units` — and on an unweighed row it could not be — so
/// the shipped `unitNotAllowed` machinery reaches this line.
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

/// The owner's field-test line: "1 whole lime". The source's word is no unit
/// the row can carry, so the amount slot must stay EMPTY rather than print a
/// "1 whole" that reads as already filled.
final _wholeLime = reconPayload([
  reconLine(
    'lime',
    qty: 1,
    unit: 'whole',
    rawAmount: '1 whole',
    ingredientId: lime.id,
    canonicalName: 'Lime',
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

    // And the collapsed row prints it in the ONE note grammar — the same
    // `name · note` the recipe page and the editor's row print.
    await tester.tap(find.byIcon(FLucideIcons.chevronUp));
    await tester.pumpAndSettle();
    expect(
      find.text('Spaghetti  ·  finely chopped', findRichText: true),
      findsOneWidget,
    );
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

  testWidgets('a unit the matched row cannot carry leaves the AMOUNT SLOT '
      'empty and keeps the source line in both states', (tester) async {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(FakeImportRepo(_wholeLime)),
        ingredientRepositoryProvider.overrideWithValue(
          const OneRowIngredientRepo(lime),
        ),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
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

    // Compact: the slot reads as unset, the flag says what is owed, and the
    // page's own words are still on the row.
    expect(find.text('1 whole'), findsNothing);
    expect(find.text('\u2014'), findsOneWidget);
    expect(find.text('Pick a supported unit'), findsOneWidget);
    expect(find.text('from source:  1 whole lime'), findsOneWidget);

    await tester.tap(find.byIcon(FLucideIcons.pencil).first);
    await tester.pumpAndSettle();

    // Expanded: the same three facts, in the card's own vocabulary.
    expect(find.text('1 whole'), findsNothing);
    expect(find.text('set amount'), findsOneWidget);
    expect(find.text('Pick a supported unit'), findsOneWidget);
    expect(find.text('from source:  1 whole lime'), findsOneWidget);

    // The number the source printed is not discarded - the sheet opens on it.
    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.quantity, 1);
    expect(state.resolutions.single.unit, 'whole');
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

  testWidgets('a match at a row this device cannot find reads as UNMATCHED — '
      'the pick cell, not a check over a row that is gone', (tester) async {
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(FakeImportRepo(_auto)),
        // The row was retired between the server's match and this review, so
        // the vocabulary hands nothing back for the id the line still carries
        // — `byIds` skips the dead.
        ingredientRepositoryProvider.overrideWithValue(
          FakeIngredientRepo(const []),
        ),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
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

    // The same words a line the cascade could not match wears.
    expect(find.text('Match an ingredient'), findsWidgets);

    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    // The identity cell asks for a pick…
    expect(find.text('Did you mean'), findsOneWidget);
    // …and the amount and notes stay locked behind it, as they do on any
    // unmatched line: a unit means nothing with no allowed set to read.
    expect(find.byType(AmountEditor), findsNothing);
    expect(
      find.text(
        'Match an ingredient first — then the amount and notes unlock.',
      ),
      findsOneWidget,
    );
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

  // --- ADR-0015 · the piece-weight gate on a counted line -------------------
  //
  // Nothing writes a line from the row any more. A count — a printed `piece`,
  // or a number and no word — is either a `piece` the row admits, weighed by
  // its piece weight, or a flag. Where the flag is the row's MISSING weight,
  // the card says so and opens the row: the number is the ingredient's fact,
  // so the card never offers to type it here.

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

  /// Which flagged lines get the door, by the shape of the row behind them.
  /// The first three are the gap the door exists for — a count on a row that
  /// says nothing about what one weighs. The last is the near miss it must
  /// not claim: a line that printed a word of its own, which is no count at
  /// all.
  final gate =
      <
        ({
          String what,
          ReconciliationPayload payload,
          Ingredient row,
          String name,
          List<Measure> measures,
          String unit,
          bool door,
        })
      >[
        (
          what: 'a sized row with no piece weight',
          payload: _piecePayload('Red Pepper', pepper.id),
          row: pepper,
          name: 'Red Pepper',
          measures: pepperSizes,
          unit: 'piece',
          door: true,
        ),
        (
          what: 'a sole-measure row with no piece weight',
          payload: _piecePayload('Cucumber', cucumber.id),
          row: cucumber,
          name: 'Cucumber',
          measures: const [cucumberMeasure],
          unit: 'piece',
          door: true,
        ),
        (
          what: 'a fragment set with no piece weight',
          payload: _piecePayload('Broccoli', broccoli.id),
          row: broccoli,
          name: 'Broccoli',
          measures: broccoliParts,
          unit: 'piece',
          door: true,
        ),
        (
          what: 'a line that PRINTED a word of its own — no count, no gap',
          payload: _bunch,
          row: cilantro,
          name: 'Cilantro',
          measures: const [cilantroSprig],
          unit: 'bunch',
          door: false,
        ),
      ];

  for (final c in gate) {
    testWidgets('${c.what} — the printed word stands, and the piece-weight '
        'door is ${c.door ? 'on' : 'off'} the card', (tester) async {
      filterForuiSemanticsAssertions();
      final container = pieceLineContainer(c.payload, c.row, c.measures);
      await pumpPieceLine(tester, container);

      // Nothing rewrote the line on arrival: it says what the page said, and
      // it is flagged for it.
      final state =
          container.read(importControllerProvider) as ImportReconciling;
      expect(state.resolutions.single.unit, c.unit);
      expect(find.text('Pick a supported unit'), findsWidgets);

      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      final door = find.byKey(ValueKey('piece-weight-door-${c.row.id}'));
      expect(door, c.door ? findsOneWidget : findsNothing);
      // Named after the line's own identity — the card heads with what the
      // line resolved TO, and the door must agree with the heading above it.
      expect(
        find.textContaining('${c.name} has no piece weight yet'),
        c.door ? findsOneWidget : findsNothing,
      );
      // The card never tells a line what it "counts as" any more.
      expect(find.textContaining('counts as'), findsNothing);

      // The chips are the offer either way — the door is a second way out,
      // never the only one, which is what its own sentence promises.
      expect(find.text('UNIT'), findsOneWidget);
      for (final m in c.measures) {
        expect(find.text(m.label), findsWidgets);
      }
      expect(find.text('piece'), findsNothing);
    });
  }

  testWidgets('a weighed count row asks for nothing: the line is clean, with '
      'no flag, no chips and no door', (tester) async {
    filterForuiSemanticsAssertions();
    final container = pieceLineContainer(
      _piecePayload('Onion', onionByPiece.id),
      onionByPiece,
      const [],
    );
    await pumpPieceLine(tester, container);
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    expect(find.text('Pick a supported unit'), findsNothing);
    expect(
      find.byKey(ValueKey('piece-weight-door-${onionByPiece.id}')),
      findsNothing,
    );
    expect(find.text('UNIT'), findsNothing);
  });

  testWidgets('a weighed count row says its OWN default even where the stored '
      'list forgot it', (tester) async {
    filterForuiSemanticsAssertions();
    // The same sized row as above, weighed, with an explicit list that does
    // not name `piece`. The row is bought in pieces and says what one weighs,
    // so `1 large Red Pepper` stands rather than being flagged for the word
    // the page printed.
    final container = pieceLineContainer(
      _piecePayload('Red Pepper', pepperWeighed.id),
      pepperWeighed,
      pepperSizes,
    );
    await pumpPieceLine(tester, container);

    expect(find.text('Pick a supported unit'), findsNothing);
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('piece-weight-door-${pepperWeighed.id}')),
      findsNothing,
    );
  });

  testWidgets('the door opens the INGREDIENT — the weight is the row’s fact, '
      'and the card never offers to type it here', (tester) async {
    filterForuiSemanticsAssertions();
    final container = pieceLineContainer(
      _piecePayload('Red Pepper', pepper.id),
      pepper,
      pepperSizes,
    );
    await pumpPieceLine(tester, container);
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    expect(find.text('open Red Pepper ›'), findsOneWidget);
    // No weight field, no "how much does one weigh" prompt on this card.
    expect(find.textContaining('what one weighs'), findsNothing);
  });

  testWidgets('one tap on a size resolves the line, and the door goes with '
      'the flag', (tester) async {
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
    expect(find.text('Pick a supported unit'), findsNothing);
    expect(
      find.byKey(ValueKey('piece-weight-door-${pepper.id}')),
      findsNothing,
    );
  });

  testWidgets('the sole-measure sheet still opens PRE-SELECTED, so Done alone '
      'resolves the line and commits the label', (tester) async {
    filterForuiSemanticsAssertions();
    final repo = FakeImportRepo(_piecePayload('Cucumber', cucumber.id));
    final container = pieceLineContainer(
      _piecePayload('Cucumber', cucumber.id),
      cucumber,
      const [cucumberMeasure],
      repo: repo,
    );
    await pumpPieceLine(tester, container);
    await tester.tap(find.byIcon(FLucideIcons.pencil));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AmountEditor));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.resolutions.single.unit, 'cucumber');
    expect(
      find.byKey(ValueKey('piece-weight-door-${cucumber.id}')),
      findsNothing,
    );

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
        (container.read(
          importControllerProvider,
        ) as ImportReconciling).resolutions.single.isComponent,
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

      final linked = (container.read(
        importControllerProvider,
      ) as ImportReconciling).resolutions.single;
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

      final back = (container.read(
        importControllerProvider,
      ) as ImportReconciling).resolutions.single;
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
        (container.read(
          importControllerProvider,
        ) as ImportReconciling).canCommit,
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
      expect(find.textContaining('¼ of a batch'), findsOneWidget);
      expect(find.text('batch'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      final saved = (container.read(
        importControllerProvider,
      ) as ImportReconciling).resolutions.single;
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
      // `WidgetRef` used after unmount, so the pick was lost (the owner's
      // field report: a swap made in the sheet never set) — and the amount
      // sheets share the shape. The pick must land regardless
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

  group('optional is a first-class control on the card', () {
    Future<ProviderContainer> reviewing(
      ReconciliationPayload payload,
      FakeImportRepo repo,
    ) async {
      final container = ProviderContainer(
        overrides: [
          bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
          importRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(importControllerProvider.notifier)
          .startImport(const ImportFromUrl('x'));
      return container;
    }

    testWidgets('an UNMATCHED line can be made optional, and it lands on the '
        'committed line', (tester) async {
      filterForuiSemanticsAssertions();
      final repo = FakeImportRepo(_none);
      final container = await reviewing(_none, repo);
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      // The amount sheet is the one door that never opens here — the line has
      // no ingredient to admit a unit — so the pill is the whole interaction.
      expect(find.text('optional'), findsOneWidget);
      await tester.tap(find.text('optional'));
      await tester.pumpAndSettle();

      final state =
          container.read(importControllerProvider) as ImportReconciling;
      expect(state.resolutions.single.optional, isTrue);

      // Matching it afterwards is what lets it be saved at all, and the flag
      // the cook set before the match rides through it.
      container
          .read(importControllerProvider.notifier)
          .updateResolution(
            0,
            (r) => r.resolveToIngredient('ing-mystery', 'Mystery spice'),
          );
      await container
          .read(importControllerProvider.notifier)
          .commit(issuesByLine: const {0: []});
      expect(repo.committed!.groups.single.lines.single.optional, isTrue);
    });

    testWidgets('the tag reads the LINE, not the page: an extractor flag the '
        'cook turns off stays off', (tester) async {
      filterForuiSemanticsAssertions();
      final repo = FakeImportRepo(_rawOptional);
      final container = await reviewing(_rawOptional, repo);
      await tester.pumpWidget(_host(container));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.pencil));
      await tester.pumpAndSettle();

      // Seeded on from the raw flag…
      expect(
        (container.read(
          importControllerProvider,
        ) as ImportReconciling).resolutions.single.optional,
        isTrue,
      );

      await tester.tap(find.text('optional'));
      await tester.pumpAndSettle();

      // …and the tag follows the resolution down, not the raw line up.
      expect(find.text('optional'), findsOneWidget);
      expect(
        (container.read(
          importControllerProvider,
        ) as ImportReconciling).resolutions.single.optional,
        isFalse,
      );

      container
          .read(importControllerProvider.notifier)
          .updateResolution(
            0,
            (r) => r.resolveToIngredient('ing-coriander', 'Coriander'),
          );
      await container
          .read(importControllerProvider.notifier)
          .commit(issuesByLine: const {0: []});
      expect(repo.committed!.groups.single.lines.single.optional, isFalse);
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
