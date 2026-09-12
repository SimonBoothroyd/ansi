/// **A re-match carries its chips** (plan 0034, front D).
///
/// The review used to answer `relabels()` with `const []` and `substitution()`
/// with null, on the argument that a re-match here re-points by line INDEX so
/// no chip can be *orphaned*. That is true about the ref and silent about the
/// word: swap *coriander* for Cilantro and the method went on saying
/// "coriander", naming a food the recipe no longer contained.
///
/// What is asserted here is the invariant `relabelRefs` exists to hold —
/// **a chip never names something the recipe does not contain** — on the
/// review's own host: the word moves, the refs do not, the notice appears, and
/// *keep the old word* puts the printed word back.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
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
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/recipes/domain/method_draft.dart';
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

const _cilantro = Ingredient(
  id: 'ing-cilantro',
  canonicalName: 'Cilantro',
  defaultUnit: g,
  status: IngredientStatus.complete,
);

/// The owner's page, in miniature: line 0 is the one the method chips (twice —
/// once alone, once inside a collective), line 1 is a line nothing mentions.
ReconciliationPayload _payload() => reconPayload(
  title: 'Peanut Tofu Stir-Fry',
  [
    reconLine(
      'coriander',
      qty: 20,
      unit: 'g',
      rawAmount: '20 g',
      ingredientId: 'ing-coriander',
      canonicalName: 'Coriander',
    ),
    reconLine(
      'onions, thinly sliced',
      qty: 200,
      unit: 'g',
      rawAmount: '200 g onions',
      ingredientId: onionByWeight.id,
      canonicalName: 'Onion',
    ),
  ],
  steps: const [
    payload.Step(
      tokens: [
        TextToken(s: 'Chop the '),
        RefToken(refs: [0], label: 'coriander'),
        TextToken(s: ', then set aside.'),
      ],
    ),
    payload.Step(
      tokens: [
        TextToken(s: 'Scatter the '),
        RefToken(refs: [0, 1], label: 'coriander and onion'),
        TextToken(s: ' over the noodles.'),
      ],
    ),
  ],
);

Future<ProviderContainer> _reviewing() async {
  final container = ProviderContainer(
    overrides: [
      bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
      importRepositoryProvider.overrideWithValue(FakeImportRepo(_payload())),
      ingredientRepositoryProvider.overrideWithValue(
        FakeIngredientRepo(const [onionByWeight, _cilantro]),
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

/// The host the review's step cards edit through, over the current state.
ImportMethodEditing _host(ProviderContainer container) {
  final state = container.read(importControllerProvider) as ImportReconciling;
  return ImportMethodEditing(
    controller: container.read(importControllerProvider.notifier),
    state: state,
    preview: buildPreviewRecipe(
      state.payload,
      state.resolutions,
      servingsBase: state.servings,
    ),
  );
}

/// The one span of [stepIndex] that is a chip.
RefSpan _chip(ImportMethodEditing host, int stepIndex) =>
    host.methodDraft()[stepIndex].spans.single as RefSpan;

String _word(ImportMethodEditing host, int stepIndex) =>
    spanWord(host.methodDraft()[stepIndex], 0);

Widget _reviewHost(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: const FScaffold(child: _Body()),
    ),
  ),
);

/// The step cards' own fields — the review has other text fields (servings,
/// MAKES, each line's notes) above the method.
Finder _stepFields() => find.descendant(
  of: find.byType(MethodStepCard),
  matching: find.byType(EditableText),
);

/// Puts the caret at [offset] of step [step]'s card and fires the field's own
/// `onTap` — which is what a real tap does, after the tap has set the
/// selection.
Future<void> _tapStepAt(
  WidgetTester tester, {
  required int step,
  required int offset,
}) async {
  tester
      .widgetList<EditableText>(_stepFields())
      .elementAt(step)
      .controller
      .selection = TextSelection.collapsed(
    offset: offset,
  );
  tester
      .widget<FTextField>(
        find
            .ancestor(
              of: _stepFields().at(step),
              matching: find.byType(FTextField),
            )
            .first,
      )
      .onTap!();
  await tester.pumpAndSettle();
}

void main() {
  test('a re-match relabels every chip pointing at the line — the word moves, '
      'the refs do not', () async {
    final container = await _reviewing();
    expect(_word(_host(container), 0), 'coriander');

    container
        .read(importControllerProvider.notifier)
        .updateResolution(
          0,
          (r) =>
              r.resolveToIngredient(_cilantro.id, 'Cilantro', correction: true),
        );

    final host = _host(container);
    // The ingredient is stored "Cilantro"; the words it replaces sat
    // mid-sentence in lower case, so that is the case they take.
    expect(_word(host, 0), 'cilantro');
    expect(host.methodDraft()[0].text, 'Chop the cilantro, then set aside.');
    // The ref is untouched — a relabel rewrites the WORD, never the pointer.
    expect(_chip(host, 0).refs, [previewLineId(0)]);
    // The collective moves too, and keeps both of its refs.
    expect(_word(host, 1), 'cilantro');
    expect(_chip(host, 1).refs, [previewLineId(0), previewLineId(1)]);
    // The prose either side is byte-identical: we don't rewrite sentences.
    expect(
      host.methodDraft()[1].text,
      'Scatter the cilantro over the noodles.',
    );
  });

  test('the shipped notice and its per-chip revert are populated', () async {
    final container = await _reviewing();
    container
        .read(importControllerProvider.notifier)
        .updateResolution(
          0,
          (r) => r.resolveToIngredient(_cilantro.id, 'Cilantro'),
        );

    final host = _host(container);
    final substitution = host.substitution()!;
    expect(substitution.oldName, 'Coriander');
    expect(substitution.newName, 'Cilantro');
    expect(substitution.stepIds, {'step-0', 'step-1'});
    expect(host.relabels().map((r) => r.oldWord), [
      'coriander',
      'coriander and onion',
    ]);
  });

  test('keepOldWord puts the printed word back, keeping the ref', () async {
    final container = await _reviewing();
    container
        .read(importControllerProvider.notifier)
        .updateResolution(
          0,
          (r) => r.resolveToIngredient(_cilantro.id, 'Cilantro'),
        );

    final before = _host(container);
    final relabel = before.relabels().first;
    before.keepOldWord(relabel);

    final after = _host(container);
    expect(_word(after, 0), 'coriander');
    expect(_chip(after, 0).refs, [previewLineId(0)]);
    // Only that chip is reverted; the collective keeps the new word, and the
    // notice stands while it does.
    expect(_word(after, 1), 'cilantro');
    expect(after.relabels(), hasLength(1));
    expect(after.substitution(), isNotNull);

    after.keepOldWord(after.relabels().single);
    final done = _host(container);
    expect(_word(done, 1), 'coriander and onion');
    expect(done.relabels(), isEmpty);
    expect(done.substitution(), isNull);
  });

  test('an amount or note edit is not an identity change — nothing relabels, '
      'and the method is still the payload’s own', () async {
    final container = await _reviewing();
    container.read(importControllerProvider.notifier)
      ..updateResolution(0, (r) => r.pickQuantity(30))
      ..updateResolution(0, (r) => r.setNotes('finely chopped'))
      ..updateResolution(0, (r) => r.pickUnit('g'));

    final state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.editedSteps, isNull, reason: 'nobody edited the method');
    expect(_host(container).relabels(), isEmpty);
    expect(_word(_host(container), 0), 'coriander');
  });

  test('only the chips that POINT at the line move', () async {
    final container = await _reviewing();
    // Line 1 is named by the collective and by nothing else.
    container
        .read(importControllerProvider.notifier)
        .updateResolution(
          1,
          (r) => r.resolveToIngredient(_cilantro.id, 'Cilantro'),
        );
    final host = _host(container);
    // The collective names line 1, so it moved…
    expect(_word(host, 1), 'cilantro');
    // …and the solo chip, which names only line 0, did not.
    expect(_word(host, 0), 'coriander');
  });

  testWidgets('renaming a chip in the chip sheet KEEPS the chip (D-D3d)', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await _reviewing();
    await tester.pumpWidget(_reviewHost(container));
    await tester.pumpAndSettle();

    // A tap inside "coriander" — [9, 18) of step 1's sentence.
    await _tapStepAt(tester, step: 0, offset: 13);
    expect(find.text('WORD'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).last, 'fresh herbs');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.x).first);
    await tester.pumpAndSettle();

    final host = _host(container);
    // The sentence reads with the new word…
    expect(host.methodDraft()[0].text, 'Chop the fresh herbs, then set aside.');
    // …and the chip is still there, pointing where it always did. Before the
    // echo loop was closed, the rename deleted the chip it renamed and left
    // the typed text as prose.
    expect(_chip(host, 0).refs, [previewLineId(0)]);
    expect(_word(host, 0), 'fresh herbs');
  });

  testWidgets('the notice and "keep the old word" render on the review, with '
      'no new UI', (tester) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await _reviewing();
    await tester.pumpWidget(_reviewHost(container));
    await tester.pumpAndSettle();
    expect(find.textContaining('was “coriander”'), findsNothing);

    container
        .read(importControllerProvider.notifier)
        .updateResolution(
          0,
          (r) => r.resolveToIngredient(_cilantro.id, 'Cilantro'),
        );
    await tester.pumpAndSettle();

    expect(find.textContaining('2 steps mentioned Coriander'), findsOneWidget);
    expect(find.text('was “coriander”'), findsOneWidget);
    expect(find.text('keep the old word'), findsNWidgets(2));

    await tester.tap(find.text('keep the old word').first);
    await tester.pumpAndSettle();
    expect(find.text('was “coriander”'), findsNothing);
    expect(find.text('Chop the coriander, then set aside.'), findsWidgets);
  });

  testWidgets('the relabelled method is what commits', (tester) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = FakeImportRepo(_payload());
    final container = ProviderContainer(
      overrides: [
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
        importRepositoryProvider.overrideWithValue(repo),
        ingredientRepositoryProvider.overrideWithValue(
          FakeIngredientRepo(const [onionByWeight, _cilantro]),
        ),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('x'));
    container
        .read(importControllerProvider.notifier)
        .updateResolution(
          0,
          (r) => r.resolveToIngredient(_cilantro.id, 'Cilantro'),
        );

    await tester.pumpWidget(_reviewHost(container));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save recipe').first);
    await tester.pumpAndSettle();

    final steps = repo.committed!.steps;
    // The label rode through to the commit, and the ref is back to a LINE
    // INDEX — the chip still points at the same line it always did.
    expect(
      steps[0].tokens[1],
      const StepToken.ref(refs: [0], label: 'cilantro'),
    );
    expect(
      steps[1].tokens[1],
      const StepToken.ref(refs: [0, 1], label: 'cilantro'),
    );
  });
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
