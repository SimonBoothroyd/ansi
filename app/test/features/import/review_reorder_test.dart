/// Moving a line on the import review — the editor's gesture, over the
/// review's own state.
///
/// The structural claim under test is that **order and identity have stopped
/// being the same number**: a moved line keeps its flat INDEX (what
/// resolutions are keyed by and what every step chip points at) and changes
/// only its POSITION (what commits as `sort_order`).
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart'
    hide Step;
import 'package:ansi/features/import/domain/reconciliation_payload.dart'
    as payload
    show Step;
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/recon_line_card.dart';
import 'package:ansi/features/import/presentation/reconciliation_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/presentation/ingredient_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_import_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';
import '_fixtures.dart';

ReconLine _line(String text) => reconLine(
  text,
  qty: 200,
  unit: 'g',
  rawAmount: '200 g',
  ingredientId: onionByWeight.id,
  canonicalName: 'Onion',
);

/// Two named sections — two lines, then one — and a method step whose chip
/// points at the line that is about to move.
ReconciliationPayload _payload() => ReconciliationPayload(
  title: 'Traybake',
  servingsBase: 4,
  groups: [
    ReconGroup(name: 'For the pasta', lines: [_line('onions'), _line('kale')]),
    ReconGroup(name: 'For the dressing', lines: [_line('oil')]),
  ],
  steps: const [
    payload.Step(
      tokens: [
        TextToken(s: 'Wilt the '),
        RefToken(refs: [1], label: 'kale'),
        TextToken(s: '.'),
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
        FakeIngredientRepo(const [onionByWeight]),
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
  child: const MaterialApp(home: Scaffold(body: _Body())),
);

ImportReconciling _state(ProviderContainer c) =>
    c.read(importControllerProvider) as ImportReconciling;

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a line dragged under another heading is filed there, and its '
      'index — the thing chips point at — does not move', (tester) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing();
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    final grips = find.byType(LineDragGrip);
    expect(grips, findsNWidgets(3), reason: 'one per line, none on a heading');

    // Rows: 0 heading · 1 onions · 2 kale · 3 heading · 4 oil. Take the kale
    // row's grip down past the second heading.
    final kaleGrip = tester.getCenter(grips.at(1));
    final oilRow = tester.getCenter(find.byType(ReviewLineCard).last);
    final drag = await tester.startGesture(kaleGrip);
    await tester.pump(const Duration(milliseconds: 200));
    await drag.moveTo(Offset(kaleGrip.dx, oilRow.dy + 120));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    final sections = _state(container).sections;
    expect(sections.first.lines, [0]);
    expect(sections.last.lines, [2, 1]);
    // The INDEX is untouched — 1 is still the second line the page printed,
    // and the step chip that names it still resolves.
    expect(_state(container).resolutions.map((r) => r.lineIndex), [
      0,
      1,
      2,
    ], reason: 'nothing renumbers');
    expect(find.textContaining('Wilt the'), findsOneWidget);
  });

  testWidgets('an open card has no grip, and closes when a drag starts '
      'elsewhere', (tester) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing();
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // Open the first card: it becomes a form, so its handle goes.
    await tester.tap(find.byType(ReviewLineCard).first);
    await tester.pumpAndSettle();
    expect(find.text('AMOUNT'), findsOneWidget);
    expect(find.byType(LineDragGrip), findsNWidgets(2));

    // A drag starting on another row closes it: what crosses the list is a
    // row like every other row.
    final grip = tester.getCenter(find.byType(LineDragGrip).last);
    final drag = await tester.startGesture(grip);
    await tester.pump(const Duration(milliseconds: 200));
    await drag.moveTo(Offset(grip.dx, grip.dy - 60));
    await tester.pump();
    expect(find.text('AMOUNT'), findsNothing);
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.byType(LineDragGrip), findsNWidgets(3));
  });

  testWidgets('a section emptied by a move keeps its heading', (tester) async {
    filterForuiSemanticsAssertions();
    _tallViewport(tester);
    final container = await _reviewing();
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    container.read(importControllerProvider.notifier).moveLine(4, 1);
    await tester.pumpAndSettle();

    final sections = _state(container).sections;
    expect(sections.last.lines, isEmpty);
    expect(find.text('For the dressing'), findsOneWidget);
  });
}
