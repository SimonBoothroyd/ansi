/// The wide review panel's idle state: the import's outstanding work, grouped
/// by what each line WANTS — and rows created here listed apart, out of the
/// count.
library;

import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/domain/work_queue.dart';
import 'package:flutter_test/flutter_test.dart';

import '_fixtures.dart';

LineResolution _line(
  int index, {
  String text = 'onion',
  String? ingredientId,
  String? unit,
  bool createdHere = false,
  bool dropped = false,
}) => LineResolution(
  lineIndex: index,
  band: MatchBand.auto,
  ingredientText: text,
  isRange: false,
  unit: unit,
  chosenIngredientId: ingredientId,
  chosenName: ingredientId == null ? null : 'Onion',
  createdHere: createdHere,
  isDropped: dropped,
);

ReconLine Function(int) _lines(Map<int, String> printed) =>
    (i) => reconLine('t', rawAmount: printed[i] ?? '');

void main() {
  group('workFor', () {
    test('an unmatched line is a match, whatever else it is flagged for', () {
      expect(
        workFor(const [LineIssue.unmatched, LineIssue.unitNotAllowed]),
        ImportWork.match,
      );
    });

    test('a refused unit outranks an unpicked range', () {
      expect(
        workFor(const [LineIssue.rangeUnpicked, LineIssue.unitNotAllowed]),
        ImportWork.unit,
      );
    });

    test('both amount flags land in the same group', () {
      expect(workFor(const [LineIssue.rangeUnpicked]), ImportWork.amount);
      expect(workFor(const [LineIssue.amountMissing]), ImportWork.amount);
    });

    test('a clean line wants nothing', () {
      expect(workFor(const []), isNull);
    });
  });

  group('importWorkQueue', () {
    test('groups come back in the order the gate checks them', () {
      final queue = importWorkQueue(
        resolutions: [
          _line(0, ingredientId: 'ing-cilantro', unit: 'bunch'),
          _line(1, text: 'garlic cloves'),
          _line(2, ingredientId: 'ing-onion'),
        ],
        byLine: const {
          0: LineValidation(issues: [LineIssue.unitNotAllowed]),
          1: LineValidation(issues: [LineIssue.unmatched]),
          2: LineValidation(issues: [LineIssue.rangeUnpicked]),
        },
        lineAt: _lines({1: '2–3 cloves', 2: '2–3'}),
      );
      expect(queue.map((g) => g.work), [
        ImportWork.match,
        ImportWork.amount,
        ImportWork.unit,
      ]);
      expect(queue.map((g) => g.work.label), [
        'Match an ingredient',
        'Set the amount',
        'Pick a supported unit',
      ]);
    });

    test('the unit group prints the refused WORD, the others what the page '
        'printed', () {
      final queue = importWorkQueue(
        resolutions: [
          _line(0, ingredientId: 'ing-cilantro', unit: 'bunch'),
          _line(1, text: 'garlic cloves'),
        ],
        byLine: const {
          0: LineValidation(issues: [LineIssue.unitNotAllowed]),
          1: LineValidation(issues: [LineIssue.unmatched]),
        },
        lineAt: _lines({0: '1 bunch', 1: '2–3 cloves'}),
      );
      expect(
        queue.firstWhere((g) => g.work == ImportWork.unit).items.single.printed,
        '“bunch”',
      );
      expect(
        queue
            .firstWhere((g) => g.work == ImportWork.match)
            .items
            .single
            .printed,
        '2–3 cloves',
      );
    });

    test('a count with no piece weight is the ordinary unit gate, and its one '
        'door is the ROW', () {
      final queue = importWorkQueue(
        resolutions: [_line(0, ingredientId: 'ing-pepper')],
        byLine: const {
          0: LineValidation(
            issues: [LineIssue.unitNotAllowed],
            pieceWeightMissing: true,
          ),
        },
        lineAt: _lines(const {}),
      );
      final item = queue.single.items.single;
      expect(queue.single.work, ImportWork.unit);
      expect(item.openIngredientId, 'ing-pepper');
    });

    test('a clean import has no queue, and a dropped line is never in one', () {
      expect(
        importWorkQueue(
          resolutions: [
            _line(0, ingredientId: 'ing-onion'),
            _line(1, dropped: true),
          ],
          // A dropped line reports no issues by construction — it is leaving.
          byLine: const {
            0: LineValidation(issues: []),
            1: LineValidation(issues: []),
          },
          lineAt: _lines(const {}),
        ),
        isEmpty,
      );
    });

    test('a line the validation has not answered for yet is not invented into '
        'the queue', () {
      expect(
        importWorkQueue(
          resolutions: [_line(0)],
          byLine: const {},
          lineAt: _lines(const {}),
        ),
        isEmpty,
      );
    });
  });

  group('createdHereItems', () {
    test('lists the rows this review made, and says what they are', () {
      final items = createdHereItems(
        resolutions: [
          _line(0, ingredientId: 'ing-dragon', createdHere: true),
          _line(1, ingredientId: 'ing-onion'),
        ],
        byLine: const {
          0: LineValidation(issues: [], rowIsStub: true),
          1: LineValidation(issues: []),
        },
      );
      expect(items, hasLength(1));
      expect(items.single.lineIndex, 0);
      expect(items.single.printed, 'stub');
    });

    test('a created row somebody has since completed says so', () {
      final items = createdHereItems(
        resolutions: [_line(0, ingredientId: 'ing-dragon', createdHere: true)],
        byLine: const {0: LineValidation(issues: [])},
      );
      expect(items.single.printed, 'complete');
    });

    test('a dropped line is not listed — it is leaving', () {
      expect(
        createdHereItems(
          resolutions: [
            _line(0, ingredientId: 'ing-x', createdHere: true, dropped: true),
          ],
          byLine: const {0: LineValidation(issues: [])},
        ),
        isEmpty,
      );
    });
  });
}
