/// **The review stops jumping to the title** (plan 0034, front E).
///
/// The whole review is one `ListView` and the title is an `FTextField` at the
/// very top of it. A focused editable asks its enclosing scrollable to show
/// its caret — on a metrics change (the keyboard arriving or leaving), and
/// again whenever it regains focus. So after typing the title, correcting a
/// line eight cards down threw the page back to the top, and the card the cook
/// was working on was gone.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/recon_amount.dart';
import 'package:ansi/features/import/presentation/reconciliation_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
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

/// Enough lines that the list is much taller than the phone, so a scroll
/// position exists to lose.
ReconciliationPayload _payload() =>
    reconPayload(title: 'Traybake', servingsBase: 4, [
      for (var i = 0; i < 12; i++)
        reconLine(
          'onions $i, thinly sliced',
          qty: 200,
          unit: 'g',
          rawAmount: '200 g onions',
          ingredientId: onionByWeight.id,
          canonicalName: 'Onion',
        ),
    ]);

Future<ProviderContainer> _reviewing() async {
  final container = ProviderContainer(
    overrides: [
      bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
      importRepositoryProvider.overrideWithValue(FakeImportRepo(_payload())),
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

/// The review's own list — the one the title sits at the top of.
ScrollableState _list(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first);

void main() {
  testWidgets('after typing the title, the keyboard arriving does not throw '
      'the page back to the top', (tester) async {
    filterForuiSemanticsAssertions();
    // A phone, not a wall: the list has to be scrollable for there to be a
    // position to lose.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await _reviewing();
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    // 1. The cook names the recipe. The title field now has focus.
    await tester.enterText(find.byType(TextField).first, 'Charred Traybake');
    await tester.pumpAndSettle();

    // 2. They scroll down to a line that needs fixing.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    final scrolled = _list(tester).position.pixels;
    expect(scrolled, greaterThan(100), reason: 'the list really did scroll');

    // 3. A sheet opens and closes, or the keyboard comes and goes — either
    // way the view metrics change, and a focused editable off the top of the
    // screen asks to be shown.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(
      _list(tester).position.pixels,
      scrolled,
      reason: 'the page stayed where the cook left it',
    );
  });

  testWidgets('opening a sheet over a still-focused title leaves the list '
      'where it was', (tester) async {
    filterForuiSemanticsAssertions();
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await _reviewing();
    await tester.pumpWidget(_host(container));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Charred Traybake');
    await tester.pumpAndSettle();
    // Moved WITHOUT a drag, so the list's own dismiss-on-drag never fires and
    // the title is still the focused field — the state a sheet has to survive
    // on its own.
    _list(tester).position.jumpTo(400);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.pencil).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AmountEditor).first);
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget, reason: 'the sheet is open');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(_list(tester).position.pixels, 400);
  });
}
