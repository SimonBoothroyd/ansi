/// *Say what the pack is* — the one question a recipe line never asks.
///
/// Two things are pinned: the dock **states the derivation itself** rather
/// than a preview of one, so the refusal a row that cannot weigh the pack
/// produces is the same refusal that keeps Done off; and *keep as a measure*
/// is offered only where there is a word to gain.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
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

Future<void> pumpSheet(
  WidgetTester tester, {
  Ingredient row = sriracha,
  int paidCents = 399,
  List<Measure> measures = const [],
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
