/// The **On receipts** fold on the ingredient page — the receipt door's memory,
/// read back where somebody can check it.
///
/// Three things are pinned here. The section is **absent** on a row no receipt
/// has carried, so a reader who came for the macros is never shown furniture
/// about paper. It arrives **shut**, saying only how much is in it, because its
/// job is a spot-check and not a fact the page owes anybody. And a name is a
/// **tap onto its own newest receipt**, because that saved receipt is the
/// editable review and correcting the match there is the only way to correct
/// what the door remembers.
///
/// The fourth is the wording: the muted line has to say that this is not the
/// alias list, since a page that shows both a row's `also known as` words and
/// its printed names is exactly where the two would be confused.
library;

import 'package:ansi/features/ingredients/domain/price_repository.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_facts.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_list_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_price_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// The owner's own case: one shop's strip read `SHELLER`, every other read
/// `SHELLED`, and both go on being recalled until somebody sees them together.
ReceiptName name(
  String printed, {
  int lines = 1,
  List<String> stores = const ["TJ's"],
  String receiptId = 'r-sep',
  DateTime? on,
}) => (
  namePrinted: printed,
  lineCount: lines,
  stores: stores,
  lastSeen: on ?? DateTime.utc(2026, 9, 19),
  receiptId: receiptId,
);

/// The muted line under the list, spelled out — a change to it is a change a
/// reader has to agree to.
const theLine =
    'what the receipt door remembers — not words this row is also '
    'known as; fix one on its own receipt, where the latest answer wins';

void main() {
  group('the On receipts fold', () {
    testWidgets('a row no receipt has carried draws no section at all', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: ingredientDetailRoute('mango'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Identity'), findsOneWidget);
      expect(
        find.text('On receipts'),
        findsNothing,
        reason: 'the Price group already says this row has never been bought',
      );
      expect(find.byKey(kOnReceiptsFoldKey), findsNothing);
    });

    testWidgets('it arrives shut, saying only how much is in it', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: ingredientDetailRoute('mango'),
          prices: FakePriceRepo(
            names: [
              name('SHELLER EDAMAME'),
              name('SHELLED EDAMAME', lines: 4, receiptId: 'r-aug'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('On receipts'), findsOneWidget);
      expect(find.text('2 names · 5 lines'), findsOneWidget);
      expect(
        find.text('SHELLER EDAMAME'),
        findsNothing,
        reason: 'shut means shut — the names are behind the chevron',
      );
      expect(find.text(theLine), findsNothing);
    });

    testWidgets('unfolding shows every name, newest first, with its own line', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: ingredientDetailRoute('mango'),
          prices: FakePriceRepo(
            names: [
              name('SHELLER EDAMAME'),
              name(
                'SHELLED EDAMAME',
                lines: 2,
                stores: ["TJ's", 'Whole Foods'],
                receiptId: 'r-aug',
                on: DateTime.utc(2026, 8, 2),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kOnReceiptsFoldKey));
      await tester.pumpAndSettle();

      expect(find.text('SHELLER EDAMAME'), findsOneWidget);
      expect(find.text("1 line · TJ's · 19 Sep"), findsOneWidget);
      expect(find.text('SHELLED EDAMAME'), findsOneWidget);
      expect(find.text("2 lines · TJ's +1 · 2 Aug"), findsOneWidget);

      // And the line that says what this list is not.
      expect(find.text(theLine), findsOneWidget);
    });

    testWidgets('folding it again puts the names away', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: ingredientDetailRoute('mango'),
          prices: FakePriceRepo(names: [name('SHELLER EDAMAME')]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kOnReceiptsFoldKey));
      await tester.pumpAndSettle();
      expect(find.text('SHELLER EDAMAME'), findsOneWidget);

      await tester.tap(find.byKey(kOnReceiptsFoldKey));
      await tester.pumpAndSettle();
      expect(find.text('SHELLER EDAMAME'), findsNothing);
    });

    testWidgets('a name opens the newest receipt that carries it — where the '
        'match is corrected', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      GoRouter? router;
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: ingredientDetailRoute('mango'),
          prices: FakePriceRepo(
            names: [
              name('SHELLER EDAMAME'),
              name('SHELLED EDAMAME', lines: 2, receiptId: 'r-aug'),
            ],
          ),
          onRouter: (r) => router = r,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kOnReceiptsFoldKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(onReceiptsNameKey('SHELLED EDAMAME')));
      await tester.pumpAndSettle();

      expect(
        router!.state.uri.toString(),
        '/receipts/r-aug',
        reason: 'the row it names, not the first one drawn',
      );
      expect(find.text('receipt r-aug'), findsOneWidget);
    });

    testWidgets('the EDITING posture draws no fold — nothing here is edited '
        'on this page', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: editRoute('mango'),
          prices: FakePriceRepo(names: [name('SHELLER EDAMAME')]),
        ),
      );
      await tester.pumpAndSettle();

      // The Price group IS on the form — changing what a thing costs is
      // editing it — and this section is not: it reads receipts, and the way to
      // answer one leaves the page, which a form holding a draft must not
      // offer.
      expect(find.byKey(kAddPriceKey), findsOneWidget);
      expect(find.text('On receipts'), findsNothing);
      expect(find.byKey(kOnReceiptsFoldKey), findsNothing);
    });
  });

  /// The fact sheet is ONE column at every width — centred at the page measure
  /// on a phone and a tablet, and drawn beside the vocabulary at a desk, capped
  /// at [kFactSheetPaneWidth]. So the fold needs no second arrangement: it is
  /// the last block of that column wherever the column is. What the width has
  /// to buy is that the section stays *inside* the sheet's pane rather than
  /// spanning the window, and that the fold still works where the vocabulary is
  /// beside it.
  group('at a desk', () {
    testWidgets('the fold is the last block of the fact sheet’s own column, '
        'and it still opens there', (tester) async {
      filterForuiSemanticsAssertions();
      tester.view.physicalSize = const Size(1440, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      GoRouter? router;
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango, curryLeaves]),
          at: ingredientDetailRoute('mango'),
          prices: FakePriceRepo(
            names: [name('SHELLER EDAMAME'), name('SHELLED EDAMAME')],
          ),
          onRouter: (r) => router = r,
        ),
      );
      await tester.pumpAndSettle();

      // Beside the vocabulary, not over it — and the fold is in that pane.
      final sheet = tester.getRect(find.byType(IngredientDetailView));
      expect(sheet.width, lessThanOrEqualTo(kFactSheetPaneWidth));
      final fold = tester.getRect(find.byKey(kOnReceiptsFoldKey));
      expect(fold.left, greaterThanOrEqualTo(sheet.left));
      expect(fold.right, lessThanOrEqualTo(sheet.right));

      // Under Price, which is the group it is about: what the row cost, then
      // what the paper called it.
      expect(
        fold.top,
        greaterThan(tester.getRect(find.byKey(kAddPriceKey)).bottom),
      );

      await tester.tap(find.byKey(kOnReceiptsFoldKey));
      await tester.pumpAndSettle();
      expect(find.text('SHELLER EDAMAME'), findsOneWidget);

      await tester.tap(find.byKey(onReceiptsNameKey('SHELLER EDAMAME')));
      await tester.pumpAndSettle();
      expect(router!.state.uri.toString(), '/receipts/r-sep');
    });
  });

  group('the words', () {
    test('the shut fold counts names and lines, each spelled for its own '
        'count', () {
      expect(onReceiptsFact([name('A')]), '1 name · 1 line');
      expect(
        onReceiptsFact([name('A', lines: 3), name('B')]),
        '2 names · 4 lines',
      );
    });

    test('a row names the newest store and counts the rest', () {
      expect(
        receiptNameFact(name('A', lines: 2, stores: ["TJ's", 'Whole Foods'])),
        "2 lines · TJ's +1 · 19 Sep",
      );
      expect(
        receiptNameFact(
          name(
            'A',
            stores: ["TJ's", 'Whole Foods', 'Safeway', 'Berkeley Bowl'],
          ),
        ),
        "1 line · TJ's +3 · 19 Sep",
      );
    });

    test('a name no receipt named a shop for drops the clause rather than '
        'standing it empty', () {
      expect(receiptNameFact(name('A', stores: const [])), '1 line · 19 Sep');
      expect(storeWordsFact(const []), isNull);
    });
  });
}
