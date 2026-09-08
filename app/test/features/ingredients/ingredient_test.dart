/// The provenance predicates and the one source line two surfaces print.
///
/// The rule under all of it: a row says WHICH food filled it, by name. The key
/// inside the stamp — an FDC id, a barcode — is never what a reader is handed,
/// and a row that cannot name its food says nothing at all.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

/// A row wearing [source] and, when it has one, [sourceLabel].
Ingredient row({String? source, String? sourceLabel, bool edited = false}) =>
    Ingredient(
      id: 'i',
      canonicalName: 'Hazelnut spread',
      defaultUnit: g,
      status: IngredientStatus.stub,
      source: source,
      sourceLabel: sourceLabel,
      sourceEdited: edited,
    );

void main() {
  group('what filled the row is named, never keyed', () {
    test('a USDA pick reads usda · the description', () {
      expect(
        sourceProvenanceLine(
          row(source: 'usda_fdc:11216', sourceLabel: 'Curry leaves, raw'),
        ),
        'usda · Curry leaves, raw',
      );
    });

    test('a barcode scan reads barcode · the pack, not the code', () {
      final line = sourceProvenanceLine(
        row(source: 'off:3017620422003', sourceLabel: 'Ferrero Nutella'),
      );
      expect(line, 'barcode · Ferrero Nutella');
      expect(line, isNot(contains('3017620422003')));
    });

    test('`edited ·` leads either kind, so a scan down a list shows which rows '
        'are no longer the machine’s first', () {
      expect(
        sourceProvenanceLine(
          row(
            source: 'off:3017620422003',
            sourceLabel: 'Ferrero Nutella',
            edited: true,
          ),
        ),
        'edited · barcode · Ferrero Nutella',
      );
      expect(
        sourceProvenanceLine(
          row(
            source: 'usda_fdc:11216',
            sourceLabel: 'Curry leaves, raw',
            edited: true,
          ),
        ),
        'edited · usda · Curry leaves, raw',
      );
    });
  });

  group('no label, no line', () {
    test('a stamp of either kind with no name says nothing', () {
      expect(sourceProvenanceLine(row(source: 'usda_fdc:11216')), isNull);
      expect(sourceProvenanceLine(row(source: 'off:5000')), isNull);
      // An empty string is a missing name, not a blank one.
      expect(
        sourceProvenanceLine(row(source: 'off:5000', sourceLabel: '')),
        isNull,
      );
    });

    test('a provenance nothing looked up says nothing, label or not', () {
      for (final quiet in [null, 'manual', 'seed', 'import_stub']) {
        expect(
          sourceProvenanceLine(row(source: quiet, sourceLabel: 'Kale, raw')),
          isNull,
          reason: '$quiet',
        );
      }
    });

    test('a DECLINED row keeps its label and still says nothing — its numbers '
        'are gone, so there is no fill to name', () {
      expect(
        sourceProvenanceLine(
          row(source: usdaDeclinedSource, sourceLabel: 'Curry leaves, raw'),
        ),
        isNull,
      );
    });
  });

  group('the predicates', () {
    test('a barcode stamp is a barcode stamp, and both are lookups', () {
      expect(isBarcodeFilled('off:5000'), isTrue);
      expect(isBarcodeFilled('usda_fdc:1'), isFalse);
      expect(isBarcodeFilled(null), isFalse);
      expect(isLookupFilled('off:5000'), isTrue);
      expect(isLookupFilled('usda_fdc:1'), isTrue);
      for (final not in [null, 'manual', 'seed', usdaDeclinedSource]) {
        expect(isLookupFilled(not), isFalse, reason: '$not');
      }
    });

    test('the FDC id is readable off a USDA stamp alone', () {
      expect(usdaFdcId('usda_fdc:11216'), 11216);
      expect(usdaFdcId('off:11216'), isNull);
      expect(usdaFdcId('usda_fdc:not-a-number'), isNull);
    });
  });
}
