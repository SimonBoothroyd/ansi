import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/reconciliation_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a clean import shows no notes', () {
    expect(sourceNotes(const ReconciliationPayload(title: 'T')), isEmpty);
  });

  test("the model's own parse warnings are surfaced verbatim", () {
    // These rode all the way to the client and were then never rendered, while
    // the review screen's doc claimed the never-invent flags were shown (0014).
    final notes = sourceNotes(
      const ReconciliationPayload(
        title: 'T',
        parseWarnings: [
          'could not read the oven temperature',
          'the third page was cut off',
        ],
      ),
    );
    expect(notes, [
      'could not read the oven temperature',
      'the third page was cut off',
    ]);
  });

  test('truncation and a degraded photo each add their own note', () {
    final notes = sourceNotes(
      const ReconciliationPayload(
        title: 'T',
        truncated: true,
        imageQuality: ImportImageQuality.degraded,
        parseWarnings: ['an amount was illegible'],
      ),
    );
    expect(notes, hasLength(3));
    expect(notes.first, contains('longer than we could read'));
    expect(notes[1], contains('hard to read'));
    expect(notes.last, 'an amount was illegible');
  });

  test('a poor photo reads more urgently than a degraded one', () {
    final poor = sourceNotes(
      const ReconciliationPayload(
        title: 'T',
        imageQuality: ImportImageQuality.poor,
      ),
    ).single;
    expect(poor, contains('every line'));
  });
}
