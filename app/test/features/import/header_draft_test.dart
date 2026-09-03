/// The review's header draft (plan 0025 #4, board frame b): prefilled only
/// where the page plainly said it, unset everywhere else.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/header_draft.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'title, servings, a plain yield and the times ride in from the page',
    () {
      final draft = headerDraft(
        const ReconciliationPayload(
          title: 'Sausage Sliders',
          servingsBase: 8,
          yieldRaw: 'MAKES: 8 SLIDERS',
          cookTimeSeconds: TimeRange(lowSeconds: 2100, highSeconds: 2700),
          totalTimeSeconds: TimeRange(lowSeconds: 4200, highSeconds: 4200),
        ),
        bookId: 'b1',
      );
      expect(draft.id, kImportHeaderDraftId);
      expect(draft.title, 'Sausage Sliders');
      expect(draft.servingsBase, 8);
      expect(draft.yields, [(qty: 8.0, unit: pieces)]);
      // The low end of a printed range — what the commit has always written.
      expect(draft.cookTimeSeconds, 2100);
      expect(draft.totalTimeSeconds, 4200);
      expect(draft.bookId, 'b1');
    },
  );

  test('what no page prints starts unset: shelf life, the second '
      'denomination, a section', () {
    final draft = headerDraft(
      const ReconciliationPayload(title: 'T', servingsBase: 4),
      bookId: 'b1',
    );
    expect(draft.keepsForDays, isNull);
    expect(draft.freezable, isFalse);
    expect(draft.freezerDays, isNull);
    expect(draft.yieldQty2, isNull);
    expect(draft.sectionId, isNull);
    expect(draft.cookTimeSeconds, isNull);
    expect(draft.totalTimeSeconds, isNull);
  });

  test('an unclear serving count defaults to 1, and a fancier yield phrase '
      'prefills nothing — never a guess', () {
    final draft = headerDraft(
      const ReconciliationPayload(
        title: 'T',
        yieldRaw: 'MAKES ENOUGH FOR A CROWD',
      ),
      bookId: null,
    );
    expect(draft.servingsBase, 1);
    expect(draft.yields, isEmpty);
    expect(draft.bookId, isNull);
  });
}
