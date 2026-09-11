/// The reading screen's checklist model: the wire ids, and how the server's
/// cumulative elapsed times become one duration per row.
library;

import 'package:ansi/features/import/domain/import_stage.dart';
import 'package:flutter_test/flutter_test.dart';

List<StageProgress> _rows({
  List<ImportStage> plan = const [
    ImportStage.received,
    ImportStage.transcribed,
    ImportStage.sanitised,
    ImportStage.matched,
  ],
  Map<ImportStage, Duration> finished = const {},
  Duration elapsed = Duration.zero,
}) => stageChecklist(plan: plan, finished: finished, elapsed: elapsed);

void main() {
  test('the wire ids round-trip, and an id this build does not know is not '
      'guessed at', () {
    for (final stage in ImportStage.values) {
      expect(ImportStage.byId(stage.id), stage);
    }
    expect(ImportStage.byId('embedded'), isNull);
    expect(ImportStage.byId(''), isNull);
  });

  test('only the first row differs by door — from a link there are no photos '
      'to name', () {
    expect(
      ImportStage.received.label(fromPhotos: true),
      isNot(ImportStage.received.label(fromPhotos: false)),
    );
    for (final stage in ImportStage.values.skip(1)) {
      expect(
        stage.label(fromPhotos: true),
        stage.label(fromPhotos: false),
        reason: '${stage.id} should read the same through either door',
      );
    }
  });

  test('nothing said yet: the first row is running and the rest are pending, '
      'with no duration invented for them', () {
    final rows = _rows(elapsed: const Duration(seconds: 3));
    expect(rows.map((r) => r.status), [
      StageStatus.active,
      StageStatus.pending,
      StageStatus.pending,
      StageStatus.pending,
    ]);
    expect(rows.first.elapsed, const Duration(seconds: 3));
    expect(rows.skip(1).map((r) => r.elapsed), everyElement(isNull));
  });

  test("a row's time is its OWN, not the server's running total", () {
    // The server reports cumulative elapsed; a row shows the slice it owns.
    final rows = _rows(
      finished: const {
        ImportStage.received: Duration(seconds: 4),
        ImportStage.transcribed: Duration(seconds: 22),
      },
      elapsed: const Duration(seconds: 30),
    );
    expect(rows[0].status, StageStatus.done);
    expect(rows[0].elapsed, const Duration(seconds: 4));
    expect(rows[1].status, StageStatus.done);
    expect(rows[1].elapsed, const Duration(seconds: 18)); // 22 - 4
    // The running row ticks on from where the last finished one ended.
    expect(rows[2].status, StageStatus.active);
    expect(rows[2].elapsed, const Duration(seconds: 8)); // 30 - 22
    expect(rows[3].status, StageStatus.pending);
  });

  test('every stage done leaves the last row done — nothing is left ticking '
      'while the payload is on the wire', () {
    final rows = _rows(
      finished: const {
        ImportStage.received: Duration(seconds: 1),
        ImportStage.transcribed: Duration(seconds: 20),
        ImportStage.sanitised: Duration(seconds: 44),
        ImportStage.matched: Duration(seconds: 45),
      },
      elapsed: const Duration(seconds: 50),
    );
    expect(rows.map((r) => r.status), everyElement(StageStatus.done));
    expect(rows.last.elapsed, const Duration(seconds: 1)); // 45 - 44
  });

  test('a clock that went backwards prints zero, never a negative wait', () {
    final rows = _rows(
      finished: const {
        ImportStage.received: Duration(seconds: 30),
        ImportStage.transcribed: Duration(seconds: 12),
      },
    );
    expect(rows[1].elapsed, Duration.zero);
    expect(rows[2].elapsed, Duration.zero);
  });

  test('the link plan has no transcribe row — a link import makes one model '
      'call, not two', () {
    final rows = _rows(
      plan: const [
        ImportStage.received,
        ImportStage.fetched,
        ImportStage.sanitised,
        ImportStage.matched,
      ],
    );
    expect(rows.map((r) => r.stage), isNot(contains(ImportStage.transcribed)));
  });

  test('a plan with nothing in it draws nothing', () {
    expect(_rows(plan: const []), isEmpty);
  });

  test('durations read m:ss', () {
    expect(formatStageDuration(Duration.zero), '0:00');
    expect(formatStageDuration(const Duration(seconds: 7)), '0:07');
    expect(formatStageDuration(const Duration(seconds: 65)), '1:05');
    expect(formatStageDuration(const Duration(minutes: 12)), '12:00');
    // Sub-second is 0:00, not a rounded-up lie.
    expect(formatStageDuration(const Duration(milliseconds: 900)), '0:00');
  });
}
