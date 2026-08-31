// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mise/core/theme/mise_theme.dart';
import 'package:mise/features/import/data/import_providers.dart';
import 'package:mise/features/import/domain/commit_payload.dart';
import 'package:mise/features/import/domain/import_repository.dart';
import 'package:mise/features/import/domain/line_resolution.dart';
import 'package:mise/features/import/domain/line_validation.dart';
import 'package:mise/features/import/domain/reconciliation_payload.dart';
import 'package:mise/features/import/presentation/import_view_models.dart';
import 'package:mise/features/import/presentation/recon_line_card.dart';

/// A fake edge function returning a fixed single-line payload; commit records.
class _FakeRepo implements ImportRepository {
  _FakeRepo(this.payload);
  final ReconciliationPayload payload;
  CommitPayload? committed;

  @override
  Future<ReconciliationPayload> startImport(ImportSource source) async =>
      payload;

  @override
  Future<String> commit(CommitPayload payload) async {
    committed = payload;
    return 'recipe-1';
  }
}

/// One unmatched `none` line — the amount + notes must stay disabled until an
/// ingredient is chosen, and the "needs you" flag must clear once it is.
ReconciliationPayload _nonePayload() => const ReconciliationPayload(
  title: 'T',
  servingsBase: 2,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'mystery spice',
            rawAmount: 'a pinch',
          ),
          band: MatchBand.none,
        ),
      ],
    ),
  ],
);

/// One auto-matched line — resolved on arrival, but (owner refinement) still
/// fully editable.
ReconciliationPayload _autoPayload() => const ReconciliationPayload(
  title: 'T',
  servingsBase: 2,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'spaghetti',
            qty: 200,
            unit: 'g',
            rawAmount: '200g',
          ),
          band: MatchBand.auto,
          candidates: [
            MatchCandidate(
              ingredientId: 'ing-spag',
              canonicalName: 'Spaghetti',
              score: 0.98,
            ),
          ],
        ),
      ],
    ),
  ],
);

/// An auto-matched line whose amount is an unpicked RANGE — the ingredient
/// must lock regardless of the range (round-3 #4).
ReconciliationPayload _autoRangePayload() => const ReconciliationPayload(
  title: 'T',
  servingsBase: 2,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'garlic cloves, sliced',
            qtyLow: 2,
            qtyHigh: 3,
            unit: 'clove',
            rawAmount: '2–3 cloves',
          ),
          band: MatchBand.auto,
          candidates: [
            MatchCandidate(
              ingredientId: 'ing-garlic',
              canonicalName: 'Garlic',
              score: 0.95,
            ),
          ],
        ),
      ],
    ),
  ],
);

Widget _host(ProviderContainer container, {LineValidation? validation}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: FTheme(
          data: miseThemeData(),
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
          controller: ref.read(importControllerProvider.notifier),
          validation: validation,
        ),
      ],
    );
  }
}

/// Forui's text field trips a semantics merge assertion under the test
/// harness (the same one the quantity-sheet tests filter) — not our concern
/// here. Suppress only that assertion.
void _filterSemanticsAssertions() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

void main() {
  testWidgets('an auto line is compact, then expands into the editable card '
      '(re-match + amount + notes)', (tester) async {
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_autoPayload())),
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
    _filterSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_autoPayload())),
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

    final state =
        container.read(importControllerProvider) as ImportReconciling;
    final line0 = state.resolutions.firstWhere((r) => r.lineIndex == 0);
    expect(line0.notes, 'finely chopped');
  });

  testWidgets('an unmatched line disables amount + notes and shows a clear '
      '"needs you" flag that clears once matched', (tester) async {
    _filterSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_nonePayload())),
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
        .updateResolution(0, (r) => r.resolveToNewStub('Mystery spice'));
    await tester.pumpAndSettle();

    expect(find.text('Match an ingredient'), findsNothing);
    expect(find.textContaining('Match an ingredient first'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('an unresolved line renders its candidates as "did you mean" '
      'pills', (tester) async {
    String? picked;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: FTheme(
            data: miseThemeData(),
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
                onResolveStub: (_) {},
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

  testWidgets('an auto line locks its ingredient even with an unpicked range; '
      'only the amount is flagged (round-3 #4)', (tester) async {
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(
          _FakeRepo(_autoRangePayload()),
        ),
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
      'unit chips that apply on tap (round-3 #1b/#2)', (tester) async {
    _filterSemanticsAssertions();
    final container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(_FakeRepo(_autoPayload())),
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

  group('amountLabel (round-3 #1a)', () {
    test('an imprecise unit reads as the clean unit, never the raw phrase', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.none,
        ingredientText: 'chilli',
        isRange: false,
        unit: 'pinch',
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(
            ingredientText: 'chilli',
            rawAmount: 'A good pinch',
          ),
        ),
        'pinch',
      );
    });

    test('an unpicked range shows the printed original for reference', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'garlic',
        isRange: true,
        unit: 'clove',
      );
      expect(
        amountLabel(
          r,
          const RawLineItem(ingredientText: 'garlic', rawAmount: '2–3 cloves'),
        ),
        '2–3 cloves',
      );
    });

    test('a picked quantity + unit reads plainly', () {
      const r = LineResolution(
        lineIndex: 0,
        band: MatchBand.auto,
        ingredientText: 'spaghetti',
        isRange: false,
        unit: 'g',
        quantity: 400,
      );
      expect(amountLabel(r, const RawLineItem(ingredientText: 'x')), '400 g');
    });
  });
}
