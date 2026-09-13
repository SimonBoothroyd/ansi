/// The import review on a desk (design board `Import review`, the
/// `Wide · ≥ 1024` frames): three columns, the panel holding one line's form or
/// the import's own work queue, the commit bar under the lines — and the
/// phone's review, unchanged, below the band.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/commit_payload.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/import_stage.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/import/presentation/reconciliation_view.dart';
import 'package:ansi/features/import/presentation/wide_review_view.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/shared/ansi_layout.dart';
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

/// A desk-width window — the band the three columns belong to. Tall, because
/// the lines column is a long scroll and a short viewport builds only its top.
void _desk(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A half-screen browser window: `medium`, so the phone's review.
void _narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The page as the server read it, and the three lines inside it.
const _page =
    'Weeknight curry. Ingredients: 200 g onion, diced; '
    '2–3 cloves garlic; 1 bunch cilantro, chopped.';

ReconciliationPayload _payload() => reconPayload(
  [
    reconLine(
      'onion',
      qty: 200,
      unit: 'g',
      rawAmount: '200 g',
      ingredientId: onionByWeight.id,
      canonicalName: 'Onion',
      sourceSpan: SourceSpan(
        start: _page.indexOf('200 g'),
        end: _page.indexOf('200 g') + '200 g onion'.length,
      ),
    ),
    // Unmatched: the work queue's `Match an ingredient` group.
    reconLine('garlic cloves', band: MatchBand.none, rawAmount: '2–3 cloves'),
    // Matched, but `bunch` is a word the row cannot carry: `Pick a supported
    // unit`.
    reconLine(
      'bunch of cilantro',
      qty: 1,
      unit: 'bunch',
      rawAmount: '1 bunch',
      ingredientId: cilantro.id,
      canonicalName: 'Cilantro',
    ),
  ],
  title: 'Weeknight curry',
  sourceText: _page,
);

Future<ProviderContainer> _reviewing({
  ReconciliationPayload? payload,
  ImportSource source = const ImportFromUrl('https://example.test/curry'),
}) async {
  final container = _container(FakeImportRepo(payload ?? _payload()));
  await container.read(importControllerProvider.notifier).startImport(source);
  return container;
}

ProviderContainer _container(ImportRepository repo) {
  final container = ProviderContainer(
    overrides: [
      bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
      importRepositoryProvider.overrideWithValue(repo),
      ingredientRepositoryProvider.overrideWithValue(
        FakeIngredientRepo(const [onionByWeight, garlic, cilantro]),
      ),
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
      recipeRepositoryProvider.overrideWithValue(FakeRecipeRepository()),
      usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _host(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: FTheme(data: ansiThemeData(), child: const ImportView()),
  ),
);

void main() {
  group('the review at a desk', () {
    testWidgets('is three columns, in the drawn order', (tester) async {
      filterForuiSemanticsAssertions();
      _desk(tester);
      await tester.pumpWidget(_host(await _reviewing()));
      await tester.pumpAndSettle();

      final source = tester.getRect(find.byKey(kWideSourceKey));
      final lines = tester.getRect(find.byKey(kWideLinesKey));
      final panel = tester.getRect(find.byKey(kWidePanelKey));
      expect(source.right, lines.left);
      expect(lines.right, panel.left);
      // At a 1440 window the columns are drawn at rest, and the page is capped
      // and centred — never stretched across the monitor.
      expect(source.width, kWideSourceWidth);
      expect(lines.width, kWideLinesWidth);
      expect(panel.width, kWidePanelWidth);
      expect(panel.right - source.left, kWideReviewCap - ansiPageGutter * 2);

      // The phone's one-column body is not built at all.
      expect(find.byType(ReconciliationBody), findsNothing);
      // The source column is the page, at a readable measure.
      expect(find.textContaining('Weeknight curry. Ingredients'), findsOne);
    });

    testWidgets('selecting a row fills the panel and lights its span', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      _desk(tester);
      await tester.pumpWidget(_host(await _reviewing()));
      await tester.pumpAndSettle();

      // Nothing selected: no row is lit and nothing is spanned.
      expect(find.byKey(kWideSelectedRowKey), findsNothing);
      expect(find.byKey(kWideSourceSpanKey), findsNothing);

      await tester.tap(find.text('Onion'));
      await tester.pumpAndSettle();

      // The row the panel is reading is lit, in the list, where it was tapped.
      expect(find.byKey(kWideSelectedRowKey), findsOne);
      expect(
        find.descendant(
          of: find.byKey(kWideSelectedRowKey),
          matching: find.text('Onion'),
        ),
        findsOne,
      );
      // …and the panel is the phone's EXPANDED card, beside the list rather
      // than pushing it down: its head says which line, and the card's own
      // `from source:` line and its optional switch are in it.
      expect(find.text('1 of 3'), findsOne);
      final panel = tester.getRect(find.byKey(kWidePanelKey));
      final fromSource = find.descendant(
        of: find.byKey(kWidePanelKey),
        matching: find.text('from source:  200 g onion'),
      );
      expect(fromSource, findsOne);
      expect(tester.getTopLeft(fromSource).dx, greaterThan(panel.left));

      // The span the payload named is lit in the source column, and it is the
      // words the page printed for that line.
      final lit = find.byKey(kWideSourceSpanKey);
      expect(lit, findsOne);
      expect(
        find.descendant(of: lit, matching: find.text('200 g onion')),
        findsOne,
      );
      expect(tester.getRect(lit).right, lessThanOrEqualTo(panel.left));
    });

    testWidgets('a payload with no span lights nothing and still draws the '
        'page', (tester) async {
      filterForuiSemanticsAssertions();
      _desk(tester);
      final bare = reconPayload([
        reconLine(
          'onion',
          qty: 200,
          unit: 'g',
          rawAmount: '200 g',
          ingredientId: onionByWeight.id,
          canonicalName: 'Onion',
        ),
      ], sourceText: _page);
      await tester.pumpWidget(_host(await _reviewing(payload: bare)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Onion'));
      await tester.pumpAndSettle();
      expect(find.byKey(kWideSelectedRowKey), findsOne);
      expect(find.byKey(kWideSourceSpanKey), findsNothing);
      expect(find.textContaining('Weeknight curry. Ingredients'), findsOne);
    });

    testWidgets('the idle panel is the work queue, read from the validation '
        'map', (tester) async {
      filterForuiSemanticsAssertions();
      _desk(tester);
      await tester.pumpWidget(_host(await _reviewing()));
      await tester.pumpAndSettle();

      // The groups are the rows' own `⚠` labels, in the order the gate checks
      // them — and each item is a line that is actually flagged.
      final panel = find.byKey(kWidePanelKey);
      expect(find.text('WHAT STILL NEEDS YOU'), findsOne);
      for (final label in ['Match an ingredient', 'Pick a supported unit']) {
        expect(
          find.descendant(of: panel, matching: find.text(label)),
          findsOne,
          reason: '$label is a heading in the queue',
        );
      }
      expect(
        find.descendant(of: panel, matching: find.text('garlic cloves')),
        findsOne,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Cilantro')),
        findsOne,
      );
      // No new number: the panel's count is the header's count is the gate's.
      expect(find.text('2 to review'), findsOne);
      expect(
        find.descendant(of: panel, matching: find.text('2')),
        findsOne,
        reason: 'the queue counts the same two the header does',
      );
      expect(find.text('2 line(s) need you'), findsOne);

      // Tapping an item selects its line, and the panel becomes the form.
      await tester.tap(
        find.descendant(of: panel, matching: find.text('garlic cloves')),
      );
      await tester.pumpAndSettle();
      expect(find.text('WHAT STILL NEEDS YOU'), findsNothing);
      expect(find.text('THE LINE'), findsOne);
    });

    testWidgets('the commit bar is the LINES column’s footer', (tester) async {
      filterForuiSemanticsAssertions();
      _desk(tester);
      await tester.pumpWidget(_host(await _reviewing()));
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byKey(kWideCommitBarKey));
      final lines = tester.getRect(find.byKey(kWideLinesKey));
      final source = tester.getRect(find.byKey(kWideSourceKey));
      final panel = tester.getRect(find.byKey(kWidePanelKey));
      expect(bar.left, lines.left);
      expect(bar.right, lines.right);
      expect(bar.bottom, lines.bottom);
      // A bar across the source pane would say the page has something to save.
      expect(bar.left, greaterThanOrEqualTo(source.right));
      expect(bar.right, lessThanOrEqualTo(panel.left));
      // It is the phone's own gate, with the phone's own words.
      expect(find.byType(ReviewCommitBar), findsOne);
    });

    testWidgets('a row does not repeat the page — the page is a column away', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      _desk(tester);
      await tester.pumpWidget(_host(await _reviewing()));
      await tester.pumpAndSettle();

      // The cilantro line's unit is refused, which on a phone is exactly when
      // the row prints `from source:` under itself. Here the same words are
      // set larger, five centimetres away, so the duplicate goes.
      expect(find.text('Pick a supported unit'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(kWideLinesKey),
          matching: find.textContaining('from source:'),
        ),
        findsNothing,
      );
      // …and it comes back the moment the source column is not there.
      _narrow(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('from source:'), findsWidgets);
    });
  });

  group('the reading state at a desk', () {
    testWidgets('the source column is already drawn beside the checklist', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      _desk(tester);
      final repo = _StalledImportRepo();
      final container = _container(repo);
      unawaited(
        container
            .read(importControllerProvider.notifier)
            .startImport(const ImportFromUrl('https://example.test/curry')),
      );
      await tester.pumpWidget(_host(container));
      await tester.pump();
      await tester.pump();

      // The page's first state: the source lane stands where it will stand
      // when the review lands, and the streamed checklist is beside it.
      expect(find.byKey(kWideSourceKey), findsOne);
      expect(find.text('https://example.test/curry'), findsOne);
      expect(find.text('Receiving the request…'), findsOne);
      expect(find.text('Ingredients matched'), findsOne);
      // Nothing to review yet, so neither of the other two columns exists.
      expect(find.byKey(kWideLinesKey), findsNothing);
      expect(find.byKey(kWidePanelKey), findsNothing);

      // …and when the review lands, that column does not move: the lines and
      // the panel open beside it.
      repo.answer(_payload());
      await tester.pumpAndSettle();
      expect(find.byKey(kWideSourceKey), findsOne);
      expect(find.byKey(kWideLinesKey), findsOne);
      expect(find.byKey(kWidePanelKey), findsOne);
    });
  });

  group('below the band', () {
    testWidgets('the phone review is what is drawn, unchanged', (tester) async {
      filterForuiSemanticsAssertions();
      _narrow(tester);
      await tester.pumpWidget(_host(await _reviewing()));
      await tester.pumpAndSettle();

      expect(find.byType(ReconciliationBody), findsOne);
      for (final key in [kWideSourceKey, kWideLinesKey, kWidePanelKey]) {
        expect(find.byKey(key), findsNothing);
      }
      // …and the card still expands IN PLACE, which is the whole of the
      // phone's review.
      await tester.tap(find.text('Onion'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Match an ingredient first — then the amount and '
          'notes unlock.',
        ),
        findsNothing,
      );
      expect(find.textContaining('from source:'), findsWidgets);
    });
  });

  group('the shrink policy', () {
    test('at rest the three columns are the drawn widths', () {
      final at = wideReviewColumnWidths(
        kWideSourceWidth + kWideLinesWidth + kWidePanelWidth,
      );
      expect(at.source, kWideSourceWidth);
      expect(at.lines, kWideLinesWidth);
      expect(at.panel, kWidePanelWidth);
    });

    test('the source gives up its width first, then the panel', () {
      // 1180 window ⇒ 1140 of columns: 60 to find, all of it the source's.
      final a = wideReviewColumnWidths(1140);
      expect(a.source, 320);
      expect(a.lines, kWideLinesWidth);
      expect(a.panel, kWidePanelWidth);

      // Past the source's floor the panel starts paying.
      final b = wideReviewColumnWidths(1100);
      expect(b.source, kWideSourceFloor);
      expect(b.panel, 320);
      expect(b.lines, kWideLinesWidth);
    });

    test('the lines are the last to give anything up', () {
      final at = wideReviewColumnWidths(1060);
      expect(at.source, kWideSourceFloor);
      expect(at.panel, kWidePanelFloor);
      expect(at.lines, 460);
      expect(at.lines, greaterThanOrEqualTo(kWideLinesFloor));
    });

    test(
      'under the floors all three shrink together, and nothing overflows',
      () {
        // The bottom of the band: a 1024 window whose rail leaves 920 for the
        // page. The floors do not fit, so they scale.
        final at = wideReviewColumnWidths(920);
        expect(at.source + at.lines + at.panel, closeTo(920, 1e-9));
        expect(at.lines, greaterThan(at.source));
        expect(at.lines, greaterThan(at.panel));
      },
    );
  });
}

/// An import that reports its plan and then never answers — the reading state,
/// held open.
class _StalledImportRepo implements ImportRepository {
  final _answer = Completer<ReconciliationPayload>();

  /// Lets the import finish — which also stops the checklist's clock.
  void answer(ReconciliationPayload payload) => _answer.complete(payload);

  @override
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  }) {
    onProgress?.call(
      const ImportPlanned([
        ImportStage.received,
        ImportStage.fetched,
        ImportStage.sanitised,
        ImportStage.matched,
      ]),
    );
    return _answer.future;
  }

  @override
  Future<String> commit(CommitPayload payload) async => 'recipe-1';
}
