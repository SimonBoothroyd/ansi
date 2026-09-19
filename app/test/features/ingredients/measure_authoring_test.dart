/// Authoring a measure's word — the one rule, held wherever it is authored.
///
/// The measures editor and the receipt's *keep as a measure* toggle are the
/// same act, so ` Can ` and `Can` must not become two rows of one word.
library;

import 'package:ansi/core/units/measure.dart';
import 'package:ansi/features/ingredients/domain/measure_authoring.dart';
import 'package:flutter_test/flutter_test.dart';

const can = Measure(id: 'm-can', label: 'can (14.5 oz)', amount: 411);
const bigCan = Measure(id: 'm-big', label: 'can (28 oz)', amount: 794);
const bag = Measure(id: 'm-bag', label: 'bag', amount: 454, sortOrder: 1);

void main() {
  group('the label as the household wrote it', () {
    test('trimmed, and an inner run of whitespace is one space', () {
      expect(measureLabelAsAuthored('  can (14.5 oz) '), 'can (14.5 oz)');
      expect(measureLabelAsAuthored('can\t\t(14.5  oz)'), 'can (14.5 oz)');
      expect(measureLabelAsAuthored('\n bottle \n'), 'bottle');
      expect(measureLabelAsAuthored('   '), '');
    });

    test('the case is theirs, and nothing here changes it', () {
      // The measures editor has never lower-cased one, and a silent case
      // change is the kind of edit that makes a person doubt the rest.
      expect(measureLabelAsAuthored('Can (14.5 oz)'), 'Can (14.5 oz)');
      expect(measureLabelAsAuthored('Tub'), 'Tub');
    });
  });

  group('a word the row already says', () {
    test('is found however it was capitalised or spaced', () {
      expect(measureAlreadyNamed('can (14.5 oz)', const [can, bag]), can);
      expect(measureAlreadyNamed('  CAN (14.5  OZ) ', const [can, bag]), can);
      expect(measureAlreadyNamed('Bag', const [can, bag]), bag);
    });

    test('is not found where the row says something else', () {
      expect(measureAlreadyNamed('tub', const [can, bag]), isNull);
      // Two sizes of one container ARE two words — that is the house style.
      expect(measureAlreadyNamed('can (28 oz)', const [can, bigCan]), bigCan);
      expect(measureAlreadyNamed('can (28 oz)', const [can, bag]), isNull);
    });

    test('an empty word names nothing', () {
      expect(measureAlreadyNamed('   ', const [can, bag]), isNull);
    });

    test('duplicates resolve to the first, which is sort order', () {
      const older = Measure(id: 'm-1', label: 'tub', amount: 396);
      const newer = Measure(id: 'm-2', label: 'Tub', amount: 400, sortOrder: 1);
      expect(measureAlreadyNamed('tub', const [older, newer]), older);
    });
  });

  group('the same weight', () {
    test('is the app’s one tolerance for it, either side', () {
      expect(isSameMeasureWeight(411, 411), isTrue);
      expect(isSameMeasureWeight(411 * 1.009, 411), isTrue);
      expect(isSameMeasureWeight(411 * 0.991, 411), isTrue);
      expect(isSameMeasureWeight(411 * 1.02, 411), isFalse);
      expect(isSameMeasureWeight(396, 411), isFalse);
    });

    test('nothing is the same weight as nothing', () {
      expect(isSameMeasureWeight(0, 411), isFalse);
      expect(isSameMeasureWeight(411, 0), isFalse);
      expect(isSameMeasureWeight(double.nan, 411), isFalse);
    });
  });

  test('the refusal names both figures and the way out', () {
    final said = measureWordTakenRefusal(
      label: 'can',
      said: '794 g',
      taken: '411 g',
    );
    expect(said, contains('“can” is already 411 g on this row'));
    expect(said, contains('this pack is 794 g'));
    expect(
      said,
      contains('“can (794 g)”'),
      reason: 'the house style is the way out, not just a complaint',
    );
  });
}
