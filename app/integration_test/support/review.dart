/// Driving the import REVIEW screen on a device: finding a line's card,
/// opening it, and answering it the three ways the screen offers — a "did you
/// mean" chip, the picker's search, and the create-new chain.
///
/// Shared by every import scenario, because a review card is a viewport child
/// with a collapsed and an expanded face and three different doors into the
/// same picker; a file that re-derives that walks into the same traps twice.
library;

import 'package:ansi/core/text/name_clean.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart'
    show kFormSaveKey;
import 'package:ansi/features/ingredients/presentation/ingredient_picker.dart'
    show IngredientResultList;
import 'package:ansi/shared/picker_shell.dart' show PickerShell;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'drive.dart';

/// The review card for flattened line [i] (`ValueKey('review-line-$i')`).
Finder reviewCard(int i) => find.byKey(ValueKey('review-line-$i'));

/// Expands card [i] if it is still compact. The collapsed card has exactly
/// one pencil; once expanded the AMOUNT chip carries one too, so guard on
/// the 'AMOUNT' label instead.
Future<void> expandLine(WidgetTester tester, int i) async {
  await scrollTo(tester, reviewCard(i));
  final expanded = find.descendant(
    of: reviewCard(i),
    matching: find.text('AMOUNT'),
  );
  if (expanded.evaluate().isNotEmpty) return;
  final pencil = find.descendant(
    of: reviewCard(i),
    matching: find.byIcon(FLucideIcons.pencil),
  );
  await tester.ensureVisible(pencil.first);
  await tester.pumpAndSettle();
  await tester.tap(pencil.first);
  await tester.pumpAndSettle();
}

/// Whether card [i] currently shows [text].
bool lineShows(int i, String text) => find
    .descendant(of: reviewCard(i), matching: find.text(text))
    .evaluate()
    .isNotEmpty;

/// Opens line [i]'s resolver sheet from whichever door the card is showing.
///
/// There are three, one per card state — an unmatched line with no candidates
/// offers "Find or create ingredient", one with candidates offers "Something
/// else" beside the chips, and a matched line's identity row says "tap to
/// change" — and they all open the same sheet.
Future<void> openResolverForLine(WidgetTester tester, int i) async {
  await expandLine(tester, i);
  final door = find.descendant(
    of: reviewCard(i),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Text &&
          const {
            'Find or create ingredient',
            'Something else',
            'tap to change',
          }.contains(w.data),
    ),
  );
  expect(door, findsWidgets, reason: 'line $i shows no way into the picker');
  await tester.ensureVisible(door.first);
  await tester.pumpAndSettle();
  await tester.tap(door.first);
  await pumpUntilFound(tester, find.byType(PickerShell));
}

/// Types [query] into the open picker sheet and returns its result rows.
Future<void> typeInPicker(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(PickerShell),
      matching: find.byType(EditableText),
    ),
    query,
  );
  await tester.pumpAndSettle();
}

/// Re-matches line [i] the way a cook does when the offered chips are wrong or
/// absent: open the resolver, type [query], and tap the row named [pick].
Future<void> searchAndPickForLine(
  WidgetTester tester,
  int i, {
  required String query,
  required String pick,
}) async {
  await openResolverForLine(tester, i);
  await typeInPicker(tester, query);
  final row = find.descendant(
    of: find.byType(IngredientResultList),
    matching: find.text(pick),
  );
  // The picker searches the LOCAL vocabulary, and that vocabulary arrives by
  // sync: on a freshly provisioned household the rows can still be coming
  // down when the first search runs. Waiting alone would not help — a search
  // that has already answered is not re-run by rows landing after it — so ask
  // again, which is what a cook staring at an empty result list would do.
  for (var attempt = 0; row.evaluate().isEmpty && attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 500));
    await typeInPicker(tester, '');
    await typeInPicker(tester, query);
  }
  // Unchanged: the row must exist, and exactly one must. A renamed vocab row
  // and a vocabulary that never arrived both look like "offered nothing", so
  // the query stays in the message.
  expect(
    row,
    findsOneWidget,
    reason: 'searching "$query" never offered "$pick" for line $i',
  );
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// Resolves an unmatched (`none`) line to a NEW ingredient the way the review
/// does: open the seeded search sheet, take its create-new footer, walk the
/// ingredient form it pushes over the review, and back out — the line then
/// resolves to that row as an ordinary match. A second line printing the SAME
/// thing finds the row the first one made in the search instead, so nothing is
/// created twice (the commit-time coalescing that used to do this is gone).
Future<void> createIngredientForLine(
  WidgetTester tester,
  int i, {
  required String name,
}) async {
  await openResolverForLine(tester, i);
  // Search first: a previous line may already have made this row.
  await typeInPicker(tester, name);
  // The form tidies the name it is seeded with (Title Case for an
  // ingredient), so the row it makes — and the row a later line finds —
  // carries the tidied name, not the typed one.
  final stored = cleanName(name, NameKind.ingredient);
  final existing = find.descendant(
    of: find.byType(IngredientResultList),
    matching: find.text(stored),
  );
  if (existing.evaluate().isNotEmpty) {
    await tester.tap(existing.first);
    await tester.pumpAndSettle();
    return;
  }
  // The footer is seeded with the typed name (else the raw line text).
  final create = find.textContaining('as a new ingredient');
  expect(create, findsOneWidget, reason: 'the create-new footer for line $i');
  await tester.tap(create);
  // ONE push: the form IS the create surface, and it lands OVER the review's
  // sheet. Its Save is the pop the sheet is awaiting — it writes the row and
  // the sheet resolves the line with it. Backing out would write nothing.
  await pumpUntilFound(tester, find.text('CANONICAL NAME'));
  await tester.tap(find.byKey(kFormSaveKey));
  await pumpUntilFound(
    tester,
    find.descendant(of: reviewCard(i), matching: find.text(stored)),
  );
  await tester.pumpAndSettle();
}
