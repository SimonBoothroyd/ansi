/// The loading ladder itself: the rungs a URL and a photo import climb, and
/// the rule that picks one from an elapsed time.
library;

import 'package:ansi/features/import/domain/import_stage.dart';
import 'package:flutter_test/flutter_test.dart';

String _url(int seconds) =>
    importStageAt(Duration(seconds: seconds), fromPhotos: false).label;

String _photos(int seconds) =>
    importStageAt(Duration(seconds: seconds), fromPhotos: true).label;

void main() {
  test('both ladders start at their first rung and never run backwards', () {
    for (final fromPhotos in [false, true]) {
      final stages = importStages(fromPhotos: fromPhotos);
      expect(stages.first.after, Duration.zero);
      expect(
        importStageAt(Duration.zero, fromPhotos: fromPhotos).label,
        stages.first.label,
      );
      // Strictly increasing thresholds: two rungs sharing a moment would make
      // "which sentence is showing" depend on list order rather than on time.
      for (var i = 1; i < stages.length; i++) {
        expect(stages[i].after, greaterThan(stages[i - 1].after));
      }
      // Every rung is reachable, and the last one holds however long the call
      // runs past it.
      for (final stage in stages) {
        expect(
          importStageAt(stage.after, fromPhotos: fromPhotos).label,
          stage.label,
        );
      }
      expect(
        importStageAt(
          const Duration(minutes: 30),
          fromPhotos: fromPhotos,
        ).label,
        stages.last.label,
      );
    }
  });

  test('a URL import climbs fetch → read → still reading → match', () {
    expect(_url(0), 'Fetching the page…');
    expect(_url(4), 'Fetching the page…');
    expect(_url(6), 'Reading the recipe…');
    expect(_url(24), 'Reading the recipe…');
    expect(_url(30), startsWith('Still reading'));
    expect(_url(60), 'Matching the ingredients…');
  });

  test('a photo import names the vision pass and the extraction pass '
      'separately — it makes two model calls, not one', () {
    expect(_photos(0), 'Sending the photos…');
    expect(_photos(10), 'Reading the photos…');
    expect(_photos(40), 'Writing out the recipe…');
    expect(_photos(80), startsWith('Still working'));
    expect(_photos(120), 'Matching the ingredients…');
  });

  test('the rung at a moment is one INSTANCE, so a caller can skip a rebuild '
      'with identical()', () {
    final a = importStageAt(const Duration(seconds: 10), fromPhotos: false);
    final b = importStageAt(const Duration(seconds: 11), fromPhotos: false);
    expect(identical(a, b), isTrue);
  });
}
