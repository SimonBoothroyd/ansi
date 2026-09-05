/// **The review's structure is editable** (plan 0034, fronts A and B), on the
/// real screen: a section renamed, a section deleted without losing a line, a
/// section added, and a line the page never printed added into it.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/recon_line_card.dart';
import 'package:ansi/features/import/presentation/reconciliation_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
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

const _sugar = Ingredient(
  id: 'ing-sugar',
  canonicalName: 'Granulated Sugar',
  defaultUnit: g,
  status: IngredientStatus.complete,
);

ReconLine _onion(String text) => reconLine(
  text,
  qty: 200,
  unit: 'g',
  rawAmount: '200 g',
  ingredientId: onionByWeight.id,
  canonicalName: 'Onion',
);

/// Two named sections, two lines then one.
ReconciliationPayload _payload() => ReconciliationPayload(
  title: 'Traybake',
  servingsBase: 4,
  groups: [
    ReconGroup(
      name: 'For the pasta',
      lines: [_onion('onions'), _onion('shallots')],
    ),
    ReconGroup(name: 'For the dressing', lines: [_onion('spring onions')]),
  ],
);

Future<ProviderContainer> _reviewing([ReconciliationPayload? payload]) async {
  final container = ProviderContainer(
    overrides: [
      bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
      importRepositoryProvider.overrideWithValue(
        FakeImportRepo(payload ?? _payload()),
      ),
      ingredientRepositoryProvider.overrideWithValue(
        FakeIngredientRepo(const [onionByWeight, _sugar]),
      ),
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
      recipeRepositoryProvider.overrideWithValue(FakeRecipeRepository()),
      usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
    ],
  );
  addTearDown(container.dispose);
  await container
      .read(importControllerProvider.notifier)
      .startImport(const ImportFromUrl('x'));
  return container;
}

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    return ReconciliationBody(state: state);
  }
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: const FScaffold(child: _Body()),
    ),
  ),
);

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

ImportReconciling _state(ProviderContainer c) =>
    c.read(importControllerProvider) as ImportReconciling;

/// The heading field showing [name].
Finder _headingField(String name) => find.byWidgetPredicate(
  (w) => w is EditableText && w.controller.text == name,
);

void main() {
  testWidgets('each section heads with an editable field, and renaming one '
      'writes through', (tester) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing();
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(_headingField('For the pasta'), findsOneWidget);
    expect(_headingField('For the dressing'), findsOneWidget);

    await tester.enterText(_headingField('For the pasta'), 'For the noodles');
    await tester.pumpAndSettle();

    expect(_state(container).sections.first.name, 'For the noodles');
    // The PAYLOAD is untouched: `from source:` has to keep telling the truth.
    expect(_state(container).payload.groups.first.name, 'For the pasta');
  });

  testWidgets('a single UNNAMED section shows no heading row at all', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(reconPayload([_onion('onions')]));
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.text('Section name (optional)'), findsNothing);
    // …and `＋ section` is the way out of it.
    await tester.tap(find.text('section'));
    await tester.pumpAndSettle();
    expect(find.text('Section name (optional)'), findsNWidgets(2));
  });

  testWidgets('deleting a heading keeps every line — they move up', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing();
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewLineCard), findsNWidgets(3));
    // The second section's bin (a collapsed line card shows no bin of its
    // own) — the delete asks no confirm, because nothing is lost.
    await tester.tap(find.byIcon(FLucideIcons.trash2).last);
    await tester.pumpAndSettle();

    expect(find.text('For the dressing'), findsNothing);
    expect(
      find.byType(ReviewLineCard),
      findsNWidgets(3),
      reason: 'the line it held is still on screen',
    );
    final sections = _state(container).sections;
    expect(sections, hasLength(1));
    expect(sections.single.lines, [0, 1, 2]);
  });

  testWidgets('＋ section then ＋ ingredient adds a line the page never '
      'printed, and it says so', (tester) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing();
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('section'));
    await tester.pumpAndSettle();
    expect(_state(container).sections, hasLength(3));

    await tester.tap(find.text('ingredient'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'sugar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Granulated Sugar').last);
    await tester.pumpAndSettle();
    // Out of the quantity sheet without setting one: the line still lands.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final state = _state(container);
    // Minted past the payload's last, and filed into the section just added.
    expect(state.sections.last.lines, [3]);
    final added = state.resolutions.last;
    expect(added.lineIndex, 3);
    expect(added.addedAtReview, isTrue);
    expect(added.chosenIngredientId, 'ing-sugar');
    expect(added.isCorrection, isFalse);

    expect(find.byType(ReviewLineCard), findsNWidgets(4));
    // The honesty rule cuts both ways: no `from source:`, and it says why.
    expect(find.text(kAddedHereNote), findsWidgets);
  });

  testWidgets('a minted line opens and edits like any other — it has no page '
      'line behind it, and nothing indexes off the end', (tester) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing();
    container
        .read(importControllerProvider.notifier)
        .addLine(
          'g1',
          name: 'Granulated Sugar',
          ingredientId: _sugar.id,
          quantity: 1,
          unit: 'tsp',
        );
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.pencil).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The full editable card, with the honest note where `from source:` goes.
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text(kAddedHereNote), findsWidgets);
    expect(find.textContaining('from source:'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'sifted');
    await tester.pumpAndSettle();
    expect(_state(container).resolutions.last.notes, 'sifted');
  });
}
