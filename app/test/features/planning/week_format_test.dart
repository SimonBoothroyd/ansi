import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime.utc(2026, 8, 27);

  group('formatLastPlanned (7.7 picker recency)', () {
    test('same day is today', () {
      expect(formatLastPlanned(DateTime.utc(2026, 8, 27), today), 'today');
    });

    test('under a week is in days', () {
      expect(formatLastPlanned(DateTime.utc(2026, 8, 24), today), '3d ago');
      expect(formatLastPlanned(DateTime.utc(2026, 8, 21), today), '6d ago');
    });

    test('under four weeks is in weeks', () {
      expect(formatLastPlanned(DateTime.utc(2026, 8, 13), today), '2w ago');
      expect(formatLastPlanned(DateTime.utc(2026, 8, 6), today), '3w ago');
    });

    test('further back is in months, never 0mo', () {
      expect(formatLastPlanned(DateTime.utc(2026, 7, 29), today), '1mo ago');
      expect(formatLastPlanned(DateTime.utc(2026, 5, 27), today), '3mo ago');
    });

    test('a meal planned ahead reads as upcoming, honestly scaled', () {
      // The old label called ANY future date "this week" — wrong for next
      // month's plan.
      expect(formatLastPlanned(DateTime.utc(2026, 8, 29), today), 'in 2d');
      expect(formatLastPlanned(DateTime.utc(2026, 9, 2), today), 'in 6d');
      expect(formatLastPlanned(DateTime.utc(2026, 9, 17), today), 'in 3w');
      expect(formatLastPlanned(DateTime.utc(2026, 10, 27), today), 'in 2mo');
    });
  });
}
