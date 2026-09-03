/// The one rule for landing a barcode draft on a row (plan 0025 #8): fill
/// what is empty, leave what a human typed, stamp provenance only where there
/// was none, confirm nothing, and offer — never write — the pack size.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/barcode/ingredient_draft.dart';
import 'package:ansi/features/ingredients/domain/apply_draft.dart';
import 'package:flutter_test/flutter_test.dart';

const _panel = Macros(kcal: 539, protein: 6.3, carb: 57.5, fat: 30.9);

const _nutella = IngredientDraft(
  suggestedName: 'Nutella',
  source: DraftSource.barcode,
  barcode: '3017620422003',
  productName: 'Nutella',
  brand: 'Nutella',
  macros: _panel,
  packSize: DraftPackSize(400, g),
);

void main() {
  group('an empty target takes everything the draft has', () {
    test('name, panel with its basis, provenance, and the pack offer', () {
      final applied = applyDraft(_nutella, target: const DraftTarget());
      expect(applied.name, 'Nutella');
      expect(applied.macros, _panel);
      expect(applied.macrosBasis, MacrosBasis.perG);
      expect(applied.source, 'off:3017620422003');
      expect(applied.packMeasure!.amountInBasis, 400);
      expect(applied.packMeasure!.basis, MacrosBasis.perG);
      expect(applied.skipped, isEmpty);
      expect(applied.fillsSomething, isTrue);
    });

    test('a per-ml panel stays per ml — stored as the label reads (7.7)', () {
      const oat = IngredientDraft(
        suggestedName: 'Oat drink',
        source: DraftSource.barcode,
        barcode: '1',
        macros: Macros(kcal: 46, protein: 1, carb: 7, fat: 1.5),
        macrosBasis: MacrosBasis.perMl,
        packSize: DraftPackSize(1, l),
      );
      final applied = applyDraft(oat, target: const DraftTarget());
      expect(applied.macrosBasis, MacrosBasis.perMl);
      // The pack is bridged into the basis the panel is in: 1 l → 1000 ml.
      expect(applied.packMeasure!.amountInBasis, 1000);
      expect(applied.packMeasure!.basis, MacrosBasis.perMl);
    });
  });

  group('what a human already has stays, and is named', () {
    test('a typed name is not replaced by the shop’s', () {
      final applied = applyDraft(
        _nutella,
        target: const DraftTarget(name: 'Hazelnut spread'),
      );
      expect(applied.name, isNull);
      expect(applied.skipped, contains(DraftSkip.name));
      // Everything else still lands.
      expect(applied.macros, _panel);
    });

    test('an entered panel is not overwritten, whatever the label says', () {
      final applied = applyDraft(
        _nutella,
        target: const DraftTarget(hasMacros: true),
      );
      expect(applied.macros, isNull);
      expect(applied.macrosBasis, isNull);
      expect(applied.skipped, contains(DraftSkip.macros));
    });

    test('a row with a lookup source keeps it — USDA is a source, manual is '
        'not', () {
      for (final kept in ['usda_fdc:11216', 'seed', 'off:999', 'import_stub']) {
        final applied = applyDraft(_nutella, target: DraftTarget(source: kept));
        expect(applied.source, isNull, reason: kept);
        expect(applied.skipped, contains(DraftSkip.provenance), reason: kept);
      }
      for (final free in [null, '', 'manual']) {
        final applied = applyDraft(_nutella, target: DraftTarget(source: free));
        expect(applied.source, 'off:3017620422003', reason: '$free');
      }
    });

    test('a full row takes nothing and says so three times', () {
      final applied = applyDraft(
        _nutella,
        target: const DraftTarget(
          name: 'Nutella',
          hasMacros: true,
          source: 'usda_fdc:1',
        ),
      );
      expect(applied.fillsSomething, isFalse);
      expect(applied.skipped, [
        DraftSkip.name,
        DraftSkip.macros,
        DraftSkip.provenance,
      ]);
      // The pack offer survives: an offer is not a fill.
      expect(applied.packMeasure, isNotNull);
    });
  });

  group('honest gaps stay gaps', () {
    test('a product with no panel fills no macros — never zeros', () {
      const sparse = IngredientDraft(
        suggestedName: 'NESQUIK',
        source: DraftSource.barcode,
        barcode: '3033710065967',
        macrosGap: DraftMacrosGap.noPanel,
      );
      final applied = applyDraft(sparse, target: const DraftTarget());
      expect(applied.name, 'NESQUIK');
      expect(applied.macros, isNull);
      expect(applied.macrosBasis, isNull);
      expect(applied.source, 'off:3033710065967');
      expect(applied.skipped, isEmpty);
    });

    test('the not-found exit stamps nothing — it kept a code but learnt '
        'nothing', () {
      const blank = IngredientDraft.blank(barcode: '000');
      final applied = applyDraft(blank, target: const DraftTarget());
      expect(applied.name, isNull);
      expect(applied.source, isNull);
      expect(applied.fillsSomething, isFalse);
      expect(applied.skipped, isEmpty);
    });

    test('a pack size that cannot be bridged into the basis is not '
        'offered', () {
      // "16 oz" on a per-100 ml row needs a density, and a barcode never
      // carries one.
      const mismatch = IngredientDraft(
        suggestedName: 'Energy drink',
        source: DraftSource.barcode,
        barcode: '1',
        macros: Macros(kcal: 47, protein: 0, carb: 12, fat: 0),
        macrosBasis: MacrosBasis.perMl,
        packSize: DraftPackSize(16, oz),
      );
      expect(
        applyDraft(mismatch, target: const DraftTarget()).packMeasure,
        isNull,
      );
      // The same pack against a row whose per-g panel STAYS is bridged into
      // grams, because that is the basis the row keeps.
      final onGramRow = applyDraft(
        mismatch,
        target: const DraftTarget(hasMacros: true),
      );
      expect(onGramRow.packMeasure!.basis, MacrosBasis.perG);
      expect(onGramRow.packMeasure!.amountInBasis, closeTo(453.6, 0.1));
    });
  });

  group('a per-serving panel (plan 0027 M-D5) takes the macros slot', () {
    const printed = Macros(kcal: 180, protein: 6, carb: 10, fat: 14);
    const panel = DraftServingPanel(
      printed: printed,
      servingAmount: 32,
      servingBasis: MacrosBasis.perG,
      servingSize: '2 Tbsp (32 g)',
    );
    const peanutButter = IngredientDraft(
      suggestedName: 'Peanut butter',
      source: DraftSource.barcode,
      barcode: '0851087000250',
      macrosGap: DraftMacrosGap.perServingPanel,
      servingPanel: panel,
      packSize: DraftPackSize(454, g),
    );

    test('on an empty target it lands as printed, with the serving’s basis '
        '— never converted here', () {
      final applied = applyDraft(peanutButter, target: const DraftTarget());
      expect(applied.servingPanel, panel);
      expect(applied.macros, isNull);
      expect(applied.macrosBasis, MacrosBasis.perG);
      expect(applied.fillsSomething, isTrue);
      // The pack offer is bridged into the basis the row will keep.
      expect(applied.packMeasure!.amountInBasis, 454);
    });

    test('a panel a human already typed stays, and is named — the same rule '
        'as a per-100 panel', () {
      final applied = applyDraft(
        peanutButter,
        target: const DraftTarget(hasMacros: true),
      );
      expect(applied.servingPanel, isNull);
      expect(applied.macrosBasis, isNull);
      expect(applied.skipped, [DraftSkip.macros]);
    });
  });

  test('hasLookupProvenance: null and manual are free, the rest are taken', () {
    expect(hasLookupProvenance(null), isFalse);
    expect(hasLookupProvenance(''), isFalse);
    expect(hasLookupProvenance('manual'), isFalse);
    expect(hasLookupProvenance('seed'), isTrue);
    expect(hasLookupProvenance('usda_fdc:5'), isTrue);
    expect(hasLookupProvenance('off:5'), isTrue);
  });
}
