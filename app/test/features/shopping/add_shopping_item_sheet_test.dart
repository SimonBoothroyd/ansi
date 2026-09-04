/// The Shop's "Add to list" sheet — the top-up host of the add-new chain
/// (plan 0025 D3). It embeds the picker's footer row directly, so the form is
/// pushed over THIS sheet; when it pops, the row arrives re-read and the
/// quantity sheet opens on the units the form set.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
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
        path: '/ingredients/new',
        builder: (context, state) => FScaffold(
          child: FButton(
            onPress: () async {
              // What ONE Save does (plan 0029 C2): the row and everything the
              // form set, then pop with it.
              final saved = await repo.saveForm(
                null,
                IngredientFormEdit(
                  row: IngredientEdit(
                    canonicalName: state.uri.queryParameters['name'] ?? '',
                    defaultUnit: g,
                    macrosBasis: MacrosBasis.perG,
                    allowedUnits: {g, kg},
                  ),
                ),
              );
              if (context.mounted) context.pop(saved);
            },
            child: const Text('create'),
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
  testWidgets('top up ▸ add-new: the form, then the quantity sheet on the row '
      'its one Save produced', (tester) async {
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
    // The FORM is up over the Add-to-list sheet — one screen, not a sheet
    // and then a form — and no quantity sheet yet.
    expect(find.text('create'), findsOneWidget);
    expect(find.text('Add top-up'), findsNothing);

    await tester.tap(find.text('create'));
    await tester.pumpAndSettle();

    // Its pop landed on the top-up, which continued into the quantity sheet
    // on the row that Save produced, so the chip the form admitted is
    // offered.
    expect(find.text('Add top-up'), findsOneWidget);
    expect(find.text('Curry leaves'), findsWidgets);
    expect(find.text('kg'), findsOneWidget);
  });
}
