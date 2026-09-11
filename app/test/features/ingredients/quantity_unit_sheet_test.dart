// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies

import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/measure_repository.dart';
import 'package:ansi/features/ingredients/presentation/piece_weight_entry.dart';
import 'package:ansi/features/ingredients/presentation/quantity_unit_sheet.dart';
import 'package:ansi/features/ingredients/presentation/unit_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';

const _large = Measure(
  id: 'm-large',
  label: 'potato, large',
  amount: 299,
  source: 'manual',
);

/// A measure a line can reference while merge-on-read hides it from the
/// watched list (duplicate label, newer row).
const _hidden = Measure(id: 'm-hidden', label: 'potato, large', amount: 300);

/// A weighed count row: `piece` is sayable on it because something weighs one
/// (ADR-0015), which is what puts the chip in the row at all.
const _potato = Ingredient(
  id: 'i-potato',
  canonicalName: 'Potato',
  defaultUnit: pieces,
  status: IngredientStatus.complete,
  pieceBasisAmount: 213.5,
  pieceSource: 'manual',
);

/// The same row before anybody weighed one — a stranded count default, which
/// is the state the manage state's piece-weight sentence exists to clear.
const _unweighedPotato = Ingredient(
  id: 'i-potato',
  canonicalName: 'Potato',
  defaultUnit: pieces,
  status: IngredientStatus.complete,
);

/// A row said in grams: nothing there is counted, so the piece weight has no
/// business appearing.
const _flour = Ingredient(
  id: 'i-flour',
  canonicalName: 'Flour',
  defaultUnit: g,
  status: IngredientStatus.complete,
);

/// In-memory [MeasureRepository]: live list + a re-firing watch, so the
/// editor sees adds/deletes exactly like the PowerSync-backed stream.
class _FakeMeasureRepo implements MeasureRepository {
  _FakeMeasureRepo(List<Measure> initial) : _measures = [...initial];

  final List<Measure> _measures;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) async* {
    yield [..._measures];
    yield* _changes.stream.map((_) => [..._measures]);
  }

  @override
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async => {
    for (final id in ids) id: [..._measures],
  };

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) async {
    final m = Measure(id: 'm-added', label: label, amount: amount);
    _measures.add(m);
    _changes.add(null);
    return m;
  }

  @override
  Future<void> softDeleteMeasure(String measureId) async {
    _measures.removeWhere((m) => m.id == measureId);
    _changes.add(null);
  }
}

Widget _host({
  required _FakeMeasureRepo repo,
  required ValueChanged<QuantitySaved> onDone,
  UnitChoice? initialChoice,
  bool? initialOptional,
  Ingredient ingredient = _potato,
  FakeIngredientRepo? vocab,
}) => ProviderScope(
  overrides: [
    measureRepositoryProvider.overrideWithValue(repo),
    // The manage state writes the piece weight through the vocabulary — this
    // host has no Save of its own.
    ingredientRepositoryProvider.overrideWithValue(
      vocab ?? FakeIngredientRepo([ingredient]),
    ),
  ],
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: FScaffold(
        child: QuantityUnitEditor(
          ingredient: ingredient,
          initialQuantity: 2,
          initialChoice: initialChoice,
          initialOptional: initialOptional,
          onDone: onDone,
        ),
      ),
    ),
  ),
);

void main() {
  group('the sheet opens on the ROW’S DEFAULT UNIT (ADR-0015: there is no '
      'default measure to seed from any more)', () {
    testWidgets('a caller with no choice opens on the default unit, and that '
        'seed is not a pick', (tester) async {
      filterForuiSemanticsAssertions();
      QuantitySaved? saved;
      await tester.pumpWidget(
        _host(repo: _FakeMeasureRepo(const [_large]), onDone: (s) => saved = s),
      );
      await tester.pumpAndSettle();

      // The measure is offered beside the units, never instead of them: what
      // a bare count means is the row's piece weight now.
      expect(
        find.descendant(
          of: find.byType(UnitChipRow),
          matching: find.text('potato, large'),
        ),
        findsOneWidget,
      );
      expect(find.text('potato, large (299 g)'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.choice, const UnitOption(pieces));
      expect(saved!.unitPicked, isFalse);
    });

    testWidgets('a sole measure is never taken as the opening choice — one '
        'measure is not a statement about what a count means', (tester) async {
      filterForuiSemanticsAssertions();
      QuantitySaved? saved;
      await tester.pumpWidget(
        _host(repo: _FakeMeasureRepo(const [_large]), onDone: (s) => saved = s),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.choice, isNot(const MeasureOption(_large)));
    });

    testWidgets('a caller’s own choice still wins', (tester) async {
      filterForuiSemanticsAssertions();
      QuantitySaved? saved;
      await tester.pumpWidget(
        _host(
          repo: _FakeMeasureRepo(const [_large]),
          initialChoice: const MeasureOption(_large),
          onDone: (s) => saved = s,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.choice, const MeasureOption(_large));
      expect(saved!.unitPicked, isFalse);
    });
  });

  group('the manage state carries the piece weight (ADR-0015)', () {
    testWidgets('an unweighed count row is asked what one weighs, and the tap '
        'WRITES — this host has no Save', (tester) async {
      filterForuiSemanticsAssertions();
      final vocab = FakeIngredientRepo([_unweighedPotato]);
      await tester.pumpWidget(
        _host(
          repo: _FakeMeasureRepo(const [_large]),
          ingredient: _unweighedPotato,
          vocab: vocab,
          onDone: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();

      expect(find.text('PIECE WEIGHT'), findsOneWidget);
      expect(find.text('1 piece weighs'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('piece-weight-field')),
          matching: find.byType(EditableText),
        ),
        '213.5',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('piece-weight-save')));
      await tester.pumpAndSettle();

      final row = await vocab.byId('i-potato');
      expect(row!.pieceBasisAmount, 213.5);
      expect(row.pieceSource, 'manual');
      // …and the write unlocks the chip in the same act.
      expect(row.allowedUnits, contains(pieces));
    });

    testWidgets('a stated weight folds to its headline rather than asking '
        'again', (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(
        _host(repo: _FakeMeasureRepo(const [_large]), onDone: (_) {}),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();

      expect(find.text('213 1/2 g'), findsOneWidget);
      expect(find.text('1 piece weighs'), findsNothing);
    });

    testWidgets('a row said in grams is never asked — piece shows only where '
        'the row is counted', (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(
        _host(
          repo: _FakeMeasureRepo(const [_large]),
          ingredient: _flour,
          onDone: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();

      expect(find.text('PIECE WEIGHT'), findsNothing);
      expect(find.byType(PieceWeightEntry), findsNothing);
    });

    testWidgets('adding a measure picks it and asks NOTHING — the "still offer '
        'piece?" question is gone', (tester) async {
      filterForuiSemanticsAssertions();
      QuantitySaved? saved;
      await tester.pumpWidget(
        _host(repo: _FakeMeasureRepo(const []), onDone: (s) => saved = s),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();

      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'potato, medium');
      await tester.enterText(fields.at(1), '213');
      await tester.pump();
      await tester.tap(find.text('Save').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Still offer'), findsNothing);
      // Straight back to the chip row with the new measure selected.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.choice, isA<MeasureOption>());
      expect(saved!.unitPicked, isTrue);
    });
  });

  testWidgets('no raw ＋ glyph anywhere on the sheet (the tofu rule)', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    // U+FF0B is missing from the bundled fonts and renders as tofu; the
    // manage chip and the add-measure heading must use FLucideIcons.plus.
    await tester.pumpWidget(
      _host(repo: _FakeMeasureRepo(const [_large]), onDone: (_) {}),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('＋'), findsNothing);

    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();
    expect(find.text('Measures'), findsOneWidget); // manage state open
    expect(find.textContaining('＋'), findsNothing);
    expect(find.text('ADD MEASURE'), findsOneWidget);
  });

  testWidgets('an orphaned (merge-hidden) stored measure stays reachable, '
      'highlighted, and flagged as off-filter', (tester) async {
    filterForuiSemanticsAssertions();
    // The line references m-hidden, which the merged watch list omits.
    await tester.pumpWidget(
      _host(
        repo: _FakeMeasureRepo(const [_large]),
        initialChoice: const MeasureOption(_hidden),
        onDone: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    // The stored selection reads as the current choice…
    expect(find.text('potato, large (300 g)'), findsOneWidget);
    // …and its chip is offered, subtly marked as outside the filter.
    expect(find.text('not in filter'), findsOneWidget);

    // Tapping another chip and coming BACK must work (the review repro:
    // once left, the orphan could never be re-selected). The `piece` chip
    // carries what one weighs (ADR-0015) — never a bare count beside a
    // measure that explains itself.
    await tester.tap(find.text('piece (213 1/2 g)'));
    await tester.pumpAndSettle();
    expect(find.text('piece'), findsWidgets); // now the current choice
    final offFilterChip = find.descendant(
      of: find.byType(UnitChipRow),
      matching: find.text('potato, large'),
    );
    // Two 'potato, large' chips exist (the live one and the admitted
    // orphan, which trails the row) — the orphan is the flagged one.
    await tester.tap(offFilterChip.last);
    await tester.pumpAndSettle();
    expect(find.text('potato, large (300 g)'), findsOneWidget);
  });

  testWidgets('deleting the selected measure reconciles the choice', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    QuantitySaved? saved;
    await tester.pumpWidget(
      _host(
        repo: _FakeMeasureRepo(const [_large]),
        initialChoice: const MeasureOption(_large),
        onDone: (s) => saved = s,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('potato, large (299 g)'), findsOneWidget);

    // Manage → delete the selected measure → back. (Unfocus the add form
    // first: deleting rebuilds the subtree under a focused EditableText,
    // which trips a benign composing-rect assert in the test binding.)
    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.trash2));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.chevronLeft));
    await tester.pumpAndSettle();

    // The choice fell back to the default unit, visibly.
    expect(find.textContaining('deleted — back to piece'), findsOneWidget);
    expect(find.text('potato, large (299 g)'), findsNothing);

    // Done writes the reconciled unit — never the tombstoned measure_id.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.choice, const UnitOption(pieces));
    expect(saved!.unitPicked, isTrue);
  });

  testWidgets('deleting an unselected measure leaves the choice alone', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    await tester.pumpWidget(
      _host(
        repo: _FakeMeasureRepo(const [_large]),
        initialChoice: const UnitOption(pieces),
        onDone: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.trash2));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.chevronLeft));
    await tester.pumpAndSettle();

    expect(find.textContaining('deleted — back to'), findsNothing);
  });

  testWidgets('the add form redirects a volume-unit label into density entry, '
      'plural included', (tester) async {
    filterForuiSemanticsAssertions();
    await tester.pumpWidget(
      _host(repo: _FakeMeasureRepo(const []), onDone: (_) {}),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();

    // The manage state now holds the add form (label + amount) AND the
    // density entry's field — target the add form's two leading fields and
    // its own Save (the first).
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'Cups');
    await tester.enterText(fields.at(1), '226');
    await tester.pump();
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();

    // Refused as a measure — and REDIRECTED: the one-line explanation
    // points at the density entry (ADR-0008: a volume-named weight mapping
    // IS a density)…
    expect(
      find.textContaining('is a unit — that mapping is the density'),
      findsOneWidget,
    );
    // …which switches to the spoon phrasing with that spoon pre-picked
    // ("cup" chip selected in the spoon row alongside tsp/tbsp).
    expect(find.text('weighs'), findsOneWidget);
    expect(find.text('cup'), findsOneWidget);
  });

  testWidgets('the Optional row is offered only to a recipe-line host — a '
      'shopping top-up has no such fact', (tester) async {
    filterForuiSemanticsAssertions();
    await tester.pumpWidget(
      _host(repo: _FakeMeasureRepo(const [_large]), onDone: (_) {}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Optional'), findsNothing);
    expect(find.byType(FSwitch), findsNothing);
  });

  testWidgets('the Optional switch rides Done, with both consequences named '
      'under it', (tester) async {
    filterForuiSemanticsAssertions();
    QuantitySaved? saved;
    await tester.pumpWidget(
      _host(
        repo: _FakeMeasureRepo(const [_large]),
        initialOptional: false,
        onDone: (s) => saved = s,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Optional'), findsOneWidget);
    expect(
      find.text(
        'left out of macros and the shop list, and named where it left',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(FSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(saved!.optional, isTrue);
    expect(saved!.quantity, 2); // a fact about the line, not its amount
    expect(saved!.unitPicked, isFalse);
  });

  testWidgets('a line that arrives optional opens on the switch set', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    QuantitySaved? saved;
    await tester.pumpWidget(
      _host(
        repo: _FakeMeasureRepo(const [_large]),
        initialOptional: true,
        onDone: (s) => saved = s,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saved!.optional, isTrue);
  });
}
