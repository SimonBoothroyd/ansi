// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/recon_resolver.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/shared/picker_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';

void main() {
  testWidgets('an unresolved line renders its candidates as "did you mean" '
      'pills', (tester) async {
    String? picked;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: FScaffold(
              child: Resolver(
                candidates: const [
                  MatchCandidate(
                    ingredientId: 'ing-garlic',
                    canonicalName: 'Garlic',
                  ),
                  MatchCandidate(
                    ingredientId: 'ing-gran',
                    canonicalName: 'Garlic granules',
                  ),
                ],
                resolution: const LineResolution(
                  lineIndex: 0,
                  band: MatchBand.suggest,
                  ingredientText: 'garlic cloves',
                  isRange: false,
                  unit: null,
                ),
                onResolveExisting: (id, name, {required correction}) =>
                    picked = id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Did you mean'), findsOneWidget);
    expect(find.text('Garlic'), findsOneWidget);
    expect(find.text('Garlic granules'), findsOneWidget);

    await tester.tap(find.text('Garlic'));
    await tester.pumpAndSettle();
    expect(picked, 'ing-garlic');
  });

  // The other moment a wrong food is cheap to catch (plan 0040 A-D2).
  group('the matched row’s source, in the identity cell', () {
    Widget host({required LineResolution resolution, String? sourceLine}) =>
        ProviderScope(
          child: MaterialApp(
            home: FTheme(
              data: ansiThemeData(),
              child: FScaffold(
                child: Resolver(
                  candidates: const [],
                  resolution: resolution,
                  sourceLine: sourceLine,
                  onResolveExisting: (_, _, {required correction}) {},
                ),
              ),
            ),
          ),
        );

    const matched = LineResolution(
      lineIndex: 0,
      band: MatchBand.auto,
      ingredientText: 'chex cereal',
      isRange: false,
      unit: 'g',
      chosenIngredientId: 'ing-chex',
      chosenName: 'Chex Cereal',
    );

    testWidgets('a matched row names the food behind it, under the name it '
        'matched to', (tester) async {
      await tester.pumpWidget(
        host(
          resolution: matched,
          sourceLine: 'usda · Cereals ready-to-eat, GENERAL MILLS, Corn CHEX',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chex Cereal'), findsOneWidget);
      expect(
        find.text('usda · Cereals ready-to-eat, GENERAL MILLS, Corn CHEX'),
        findsOneWidget,
      );
      // The cell is still the re-match affordance it was.
      expect(find.text('tap to change'), findsOneWidget);
    });

    testWidgets('an edited row leads with EDITED here too', (tester) async {
      await tester.pumpWidget(
        host(resolution: matched, sourceLine: 'edited · usda · Kale, raw'),
      );
      await tester.pumpAndSettle();
      expect(find.text('edited · usda · Kale, raw'), findsOneWidget);
    });

    testWidgets('a row no lookup filled adds no line at all', (tester) async {
      await tester.pumpWidget(host(resolution: matched));
      await tester.pumpAndSettle();
      expect(find.text('Chex Cereal'), findsOneWidget);
      expect(find.textContaining('usda'), findsNothing);
    });
  });

  group('create-new at review is the one add flow', () {
    testWidgets('the footer opens the form seeded with the line’s text, pushed '
        'over the search sheet, and resolves the line to the re-read row as an '
        'existing ingredient', (tester) async {
      filterForuiSemanticsAssertions();
      final repo = FakeIngredientRepo(const []);
      final picks = <ReconcilePick?>[];
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => FScaffold(
              child: Builder(
                builder: (context) => FButton(
                  onPress: () async => picks.add(
                    await showReconcileIngredientSheet(
                      context,
                      seedName: 'curry leaves',
                    ),
                  ),
                  child: const Text('match'),
                ),
              ),
            ),
          ),
          // The flesh-out form's stand-in: pops on tap, like back does.
          GoRoute(
            path: '/ingredients/new',
            builder: (context, state) => FScaffold(
              child: FButton(
                onPress: () async {
                  // What ONE Save does (plan 0029 C2): the row and everything
                  // the form set, then pop with it.
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ingredientRepositoryProvider.overrideWithValue(repo),
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
      await tester.tap(find.text('match'));
      await tester.pumpAndSettle();

      // The row reads in the picker footer's voice, seeded with the line's
      // own text — no "add as stub" (round-3 detail 9).
      final create = find.text('create "curry leaves" as a new ingredient');
      expect(create, findsOneWidget);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(repo.rows, isEmpty, reason: 'tapping the row writes nothing');
      // The FORM opens, seeded with the line's own text (plan 0029 C2) — one
      // screen, and still nothing written.
      expect(find.text('create'), findsOneWidget);
      expect(picks, isEmpty, reason: 'the line resolves after the form pops');

      await tester.tap(find.text('create'));
      await tester.pumpAndSettle();
      final created = repo.rows.single;

      // Resolved as the ordinary matched state, on the row the form's one
      // Save produced; the search sheet has closed with it.
      expect(picks.single, isA<PickExisting>());
      final row = (picks.single! as PickExisting).ingredient;
      expect(row.id, created.id);
      expect(row.canonicalName, 'curry leaves');
      expect(row.allowedUnits, [g, kg]);
      expect(row.status, IngredientStatus.stub);
      expect(find.byType(PickerShell), findsNothing);
    });
  });
}
