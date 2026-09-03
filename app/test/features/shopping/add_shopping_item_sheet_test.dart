/// The Shop's "Add to list" sheet — the top-up host of the add-new chain
/// (plan 0025 D3). It embeds the picker's footer row directly, so the form is
/// pushed over THIS sheet; when it pops, the row arrives re-read and the
/// quantity sheet opens on the units the form set.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/shopping/presentation/add_shopping_item_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';

const _onion = Ingredient(
  id: 'i-onion',
  canonicalName: 'Onion',
  defaultUnit: pieces,
  status: IngredientStatus.complete,
);

Widget _host(FakeIngredientRepo repo) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => FScaffold(
          child: Builder(
            builder: (context) => FButton(
              onPress: () => showAddShoppingItemSheet(context),
              child: const Text('add'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/ingredients/:id',
        builder: (context, state) => FScaffold(
          child: FButton(
            onPress: () => context.pop(),
            child: Text('form ${state.pathParameters['id']}'),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      ingredientRepositoryProvider.overrideWithValue(repo),
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
      usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}

void main() {
  testWidgets('top up ▸ add-new: sheet → form → back → the quantity sheet '
      'opens on the re-read row', (tester) async {
    filterForuiSemanticsAssertions();
    final repo = FakeIngredientRepo(const [_onion]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top up an ingredient'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Curry leaves');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('add "Curry leaves"'));
    await tester.pumpAndSettle();
    expect(find.text('New ingredient'), findsOneWidget);
    await tester.tap(find.text('Create & flesh out'));
    await tester.pumpAndSettle();

    // The form is up over the Add-to-list sheet; no quantity sheet yet.
    final created = repo.rows.last;
    expect(find.text('form ${created.id}'), findsOneWidget);
    expect(find.text('Add top-up'), findsNothing);

    // What the form did: admitted a second unit.
    repo.rows[repo.rows.length - 1] = created.copyWith(allowedUnits: [g, kg]);
    await tester.tap(find.text('form ${created.id}'));
    await tester.pumpAndSettle();

    // Back landed on the top-up, which continued into the quantity sheet —
    // on the re-read row, so the chip the form admitted is offered.
    expect(find.text('Add top-up'), findsOneWidget);
    expect(find.text('Curry leaves'), findsWidgets);
    expect(find.text('kg'), findsOneWidget);
  });
}
