/// The review screen edits the method with the shipped editor v2 step cards
/// (seam **D4**, board frame c). The screen most likely to need a method fix
/// used to be the only one that could not make it — behind a note claiming
/// "Method is read-only in v1", which the step cards had already made false.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/preview_recipe.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart'
    hide Step;
import 'package:ansi/features/import/domain/reconciliation_payload.dart'
    as payload
    show Step;
import 'package:ansi/features/import/presentation/import_method_editing.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/reconciliation_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/presentation/method_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_import_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_fixtures.dart';

/// One clean auto-matched line and a two-step method whose first step chips
/// it — so Save is open and the method is the only thing under test.
ReconciliationPayload _payload() => reconPayload(
  title: 'Charred Pepper Traybake',
  servingsBase: 4,
  [
    reconLine(
      'onions, thinly sliced',
      qty: 200,
      unit: 'g',
      rawAmount: '200 g onions',
      ingredientId: onionByWeight.id,
      canonicalName: 'Onion',
      score: 0,
    ),
  ],
  steps: const [
    payload.Step(
      tokens: [
        TextToken(s: 'Toss the '),
        RefToken(refs: [0], label: 'onions'),
        TextToken(s: ' with the oil.'),
      ],
    ),
    payload.Step(tokens: [TextToken(s: 'Roast until charred.')]),
  ],
);

class _Body extends ConsumerWidget {
  const _Body();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    return ReconciliationBody(state: state);
  }
}

Future<ProviderContainer> _reviewing(FakeImportRepo repo) async {
  final container = ProviderContainer(
    overrides: [
      bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
      importRepositoryProvider.overrideWithValue(repo),
      ingredientRepositoryProvider.overrideWithValue(
        const OneRowIngredientRepo(onionByWeight),
      ),
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
    ],
  );
  addTearDown(container.dispose);
  await container
      .read(importControllerProvider.notifier)
      .startImport(const ImportFromUrl('x'));
  return container;
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

/// The step card's own field, found by the sentence it is showing — the
/// review screen has other text fields (servings, MAKES) above the method.
Finder _stepField(String text) => find.byWidgetPredicate(
  (w) => w is EditableText && w.controller.text == text,
);

/// The review screen is one long ListView, and a ListView only builds what is
/// on screen — Save lives past the method. Give the harness a tall viewport
/// rather than driving a scroll in every test.
void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the step cards render at review, and the "read-only in v1" '
      'notice is gone', (tester) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing(FakeImportRepo(_payload()));
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    expect(find.byType(MethodStepCard), findsNWidgets(2));
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Step 2'), findsOneWidget);
    expect(find.text('Add a step'), findsOneWidget);
    expect(find.textContaining('read-only in v1'), findsNothing);
    expect(find.textContaining('editing lands later'), findsNothing);
  });

  testWidgets('typing in a step lands in the draft and survives the rebuild', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final repo = FakeImportRepo(_payload());
    final container = await _reviewing(repo);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.enterText(
      _stepField('Roast until charred.'),
      'Roast until properly charred.',
    );
    await tester.pumpAndSettle();

    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.editedSteps![1].text, 'Roast until properly charred.');
    // The card is showing what the state holds — no stale controller.
    expect(find.text('Roast until properly charred.'), findsWidgets);
  });

  testWidgets('the edit rides the commit, and the chip is still keyed to its '
      'line index', (tester) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final repo = FakeImportRepo(_payload());
    final container = await _reviewing(repo);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.enterText(
      _stepField('Roast until charred.'),
      'Roast until properly charred.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe').first);
    await tester.pumpAndSettle();

    final steps = repo.committed!.steps;
    expect(steps, hasLength(2));
    // Step 1 is untouched, chip and all — refs are back to LINE INDEXES.
    expect(steps[0].tokens[1], const StepToken.ref(refs: [0], label: 'onions'));
    expect(
      steps[1].tokens.single,
      const TextToken(s: 'Roast until properly charred.'),
    );
  });

  testWidgets('an untouched method commits the payload steps byte-for-byte', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final repo = FakeImportRepo(_payload());
    final container = await _reviewing(repo);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save recipe').first);
    await tester.pumpAndSettle();

    expect(repo.committed!.steps, _payload().steps);
    // Nothing was stored either: the common path holds no draft at all.
    expect(
      (container.read(importControllerProvider) as ImportCommitted).recipeId,
      'recipe-1',
    );
  });

  testWidgets('the chip picker’s add-a-line door is OPEN at review, and the '
      'line it mints is chippable at once', (tester) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final repo = FakeImportRepo(_payload());
    final container = await _reviewing(repo);
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    final state = container.read(importControllerProvider) as ImportReconciling;
    final host = ImportMethodEditing(
      controller: container.read(importControllerProvider.notifier),
      state: state,
      preview: buildPreviewRecipe(
        state.payload,
        state.resolutions,
        servingsBase: state.servings,
        sections: state.sections,
      ),
    );
    expect(host.canAddLine, isTrue);
    expect(host.addLineReason, isNull);

    // The chain the picker's footer runs: a group to land in, then the line.
    final before = host.lineById().keys.toSet();
    host.addLineItem(host.ensureGroupId(), garlic, quantity: 2);
    final added = host.lineById().keys.toSet().difference(before);
    expect(added, hasLength(1), reason: 'pickOrAddLine finds it by this diff');
    expect(host.lineById()[added.single]!.ingredientName, 'Garlic');
  });
}
