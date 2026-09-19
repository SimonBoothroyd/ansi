/// *Say what the pack is* — the one question a recipe line never asks.
///
/// Three things are pinned: the dock **states the derivation itself** rather
/// than a preview of one, so the refusal a row that cannot weigh the pack
/// produces is the same refusal that keeps Done off; *keep as a measure* is
/// offered only where there is a word to gain; and what the toggle SAYS is
/// true — minting buys a word, not a pack that carries over, because the pack
/// carries over either way.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/receipts/presentation/receipt_pack_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';
import '_harness.dart';

/// A per-100 ml row with no density: a pack said in grams crosses the
/// mass↔volume boundary, which crosses only through a density.
const oliveOil = Ingredient(
  id: 'vocab-oil',
  canonicalName: 'Olive oil',
  defaultUnit: ml,
  macrosBasis: MacrosBasis.perMl,
  status: IngredientStatus.complete,
  source: 'seed',
);

const bag = Measure(id: 'm-bag', label: 'bag', amount: 454);

/// A row's own word, in the household's style: the container carries its
/// shelf size, so two sizes of one container are two measures.
const bottle = Measure(id: 'm-bottle', label: 'bottle (17 oz)', amount: 482);

Future<void> pumpSheet(
  WidgetTester tester, {
  Ingredient row = sriracha,
  int paidCents = 399,
  List<Measure> measures = const [],
  UnitChoice? choice,
  void Function(ReceiptPackAnswer)? onDone,
}) {
  // Forui's own sheet chrome trips a framework semantics assertion the moment
  // a field takes focus (tracker row `app/ui`); it is not this sheet failing.
  filterForuiSemanticsAssertions();
  return tester.pumpAnsiApp(
    // Inside a scaffold, the way the sheet is really hosted: the shell alone
    // has no route under it, and the semantics tree a focused field builds
    // needs one.
    FScaffold(
      child: ReceiptPackEditor(
        ingredient: row,
        paidCents: paidCents,
        initialChoice: choice,
        onDone: onDone ?? (_) {},
      ),
    ),
    overrides: [
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo(measures)),
    ],
  );
}

FButton doneButton(WidgetTester tester) => tester.widget<FButton>(
  find.ancestor(of: find.text('Done'), matching: find.byType(FButton)),
);

void main() {
  testWidgets('it names the row and what the paper said it cost', (
    tester,
  ) async {
    await pumpSheet(tester);
    expect(find.text('Sriracha'), findsOneWidget);
    expect(find.text(r'the receipt says $3.99'), findsOneWidget);
  });

  testWidgets('Done is shut until the pack is stated', (tester) async {
    await pumpSheet(tester);
    expect(doneButton(tester).onPress, isNull);
  });

  testWidgets('the dock states what the two come to, and Done opens', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.enterText(find.byType(EditableText).first, '482');
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(kReceiptPackDerivedKey)).data,
      '= 83¢ / 100 g',
    );
    expect(doneButton(tester).onPress, isNotNull);
  });

  testWidgets('the chip row offers only units the row can actually weigh', (
    tester,
  ) async {
    // The honesty gate is upstream of this sheet: a per-100 ml row with no
    // density never offers a gram chip, so the mass↔volume crossing cannot be
    // asked for here at all.
    await pumpSheet(tester, row: oliveOil);
    await tester.pumpAndSettle();
    expect(find.text('g'), findsNothing);
    expect(find.text('ml'), findsWidgets);
  });

  testWidgets('a line that rang up as nothing is refused, not priced', (
    tester,
  ) async {
    // A zero is not a discovery that the food is free — it is a figure
    // nobody could read — so the dock says so and Done stays shut.
    await pumpSheet(tester, paidCents: 0);
    await tester.enterText(find.byType(EditableText).first, '482');
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(kReceiptPackDerivedKey)).data,
      contains('say what you paid'),
    );
    expect(doneButton(tester).onPress, isNull);
  });

  testWidgets('keep as a measure asks for the word, and hands it back', (
    tester,
  ) async {
    ReceiptPackAnswer? answer;
    await pumpSheet(tester, onDone: (a) => answer = a);
    await tester.enterText(find.byType(EditableText).first, '482');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(kKeepAsMeasureKey));
    await tester.pumpAndSettle();
    expect(
      doneButton(tester).onPress,
      isNull,
      reason: 'a word to keep, with no word typed, is not an answer',
    );

    await tester.enterText(find.byType(EditableText).last, 'bottle');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(answer!.amount, 482);
    expect(answer!.basisAmount, 482);
    expect(answer!.keepAsMeasure, 'bottle');
  });

  testWidgets('a pack already named as a measure has no word to gain', (
    tester,
  ) async {
    await pumpSheet(tester, measures: const [bag]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('bag').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(kKeepAsMeasureKey),
      findsNothing,
      reason: 'the household already has the word',
    );
  });

  group('what keeping the word actually buys', () {
    testWidgets('the note says it is a word, not a pack that carries over', (
      tester,
    ) async {
      // The pack carries over from this row's latest price whether or not a
      // word was minted (`landPack`). The old copy claimed the opposite, and
      // a batch of bare `pack` and `jar` measures was minted on it.
      await pumpSheet(tester);
      await tester.enterText(find.byType(EditableText).first, '482');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kKeepAsMeasureKey));
      await tester.pumpAndSettle();

      final note = tester.widget<Text>(find.byKey(kKeepAsMeasureNoteKey)).data!;
      expect(note, contains('lands on this pack either way'));
      expect(note, contains('say on a recipe line'));
      expect(note, contains('buy 3'));
      // The household's own style, shown rather than described.
      expect(note, contains('can (14.5 oz)'));
      expect(find.text('e.g. can (14.5 oz)'), findsOneWidget);
    });

    testWidgets('the word is taken as written, spacing tidied', (tester) async {
      ReceiptPackAnswer? answer;
      await pumpSheet(tester, onDone: (a) => answer = a);
      await tester.enterText(find.byType(EditableText).first, '411');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kKeepAsMeasureKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(EditableText).last,
        '  can   (14.5 oz) ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(answer!.keepAsMeasure, 'can (14.5 oz)');
    });

    testWidgets('a word the row already says at this weight is not minted '
        'twice', (tester) async {
      ReceiptPackAnswer? answer;
      await pumpSheet(
        tester,
        measures: const [bottle],
        onDone: (a) => answer = a,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, '482');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kKeepAsMeasureKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'Bottle (17 oz)');
      await tester.pumpAndSettle();

      expect(find.textContaining('the line will point at it'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(answer!.keepAsMeasure, isNull, reason: 'the word exists');
      expect(answer!.choice, isA<MeasureOption>());
      expect((answer!.choice as MeasureOption).measure.id, 'm-bottle');
      expect(answer!.amount, 1, reason: 'a COUNT of the word it points at');
      expect(
        answer!.basisAmount,
        482,
        reason: 'the figure read off the paper, not what the row says today',
      );
    });

    testWidgets('the same word at another size is refused, with the way out', (
      tester,
    ) async {
      await pumpSheet(tester, measures: const [bottle]);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, '794');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kKeepAsMeasureKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'bottle (17 oz)');
      await tester.pumpAndSettle();

      final note = tester.widget<Text>(find.byKey(kKeepAsMeasureNoteKey)).data!;
      expect(note, contains('already 482 g on this row'));
      expect(note, contains('this pack is 794 g'));
      expect(note, contains('bottle (17 oz) (794 g)'));
      expect(
        doneButton(tester).onPress,
        isNull,
        reason: 'a second row of one word is not an answer',
      );
    });
  });

  testWidgets('a fresh line opens on the chip the row leads with, not on its '
      'default unit (owner)', (tester) async {
    ReceiptPackAnswer? answer;
    await pumpSheet(tester, measures: const [bag], onDone: (a) => answer = a);
    await tester.pumpAndSettle();

    // No chip tapped: the `1` below is one bag, because that is the chip the
    // sheet opened on.
    await tester.enterText(find.byType(EditableText).first, '1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(answer!.choice, const MeasureOption(bag));
    expect(answer!.basisAmount, 454);
  });

  testWidgets('a line already priced reopens on the pack it was bought in, '
      'whatever the row leads with', (tester) async {
    ReceiptPackAnswer? answer;
    await pumpSheet(
      tester,
      measures: const [bag],
      choice: const UnitOption(g),
      onDone: (a) => answer = a,
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, '482');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(answer!.choice, const UnitOption(g));
    expect(answer!.basisAmount, 482);
  });

  testWidgets('a measure chip hands back a COUNT of that measure', (
    tester,
  ) async {
    ReceiptPackAnswer? answer;
    await pumpSheet(tester, measures: const [bag], onDone: (a) => answer = a);
    await tester.pumpAndSettle();
    await tester.tap(find.text('bag').first);
    await tester.enterText(find.byType(EditableText).first, '1');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(answer!.amount, 1);
    expect(answer!.basisAmount, 454, reason: 'what one bag weighs');
    expect(answer!.keepAsMeasure, isNull);
  });
}
