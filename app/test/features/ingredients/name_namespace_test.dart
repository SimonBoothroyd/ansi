/// The household's ingredient names and its aliases are ONE namespace, keyed
/// by `match_text` — the rule, the doors it has to cover, and what the form
/// says when a name is already somebody's.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:io';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/name_namespace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/source_scan.dart';
import '_form_harness.dart';
import 'ingredient_name_tidy_test.dart' show leaveTheField, nameField;

/// A row the household already has — the owner's own case, which is how two
/// live Sauerkrauts got there in the first place.
const _sauerkraut = Ingredient(
  id: 'kraut',
  canonicalName: 'Sauerkraut',
  defaultUnit: g,
  status: IngredientStatus.complete,
  category: 'pantry',
  macros: Macros(kcal: 19, protein: 1, carb: 4, fat: 0),
);

/// A household: two rows, one of which carries two aliases.
const _entries = [
  NameEntry(
    ingredientId: 'kraut',
    ingredientName: 'Sauerkraut',
    text: 'Sauerkraut',
    matchText: 'sauerkraut',
  ),
  NameEntry(
    ingredientId: 'spring',
    ingredientName: 'Spring Onion',
    text: 'Spring Onion',
    matchText: 'spring onion',
  ),
  NameEntry(
    ingredientId: 'spring',
    ingredientName: 'Spring Onion',
    text: 'scallion',
    matchText: 'scallion',
    isAlias: true,
  ),
];

void main() {
  group('collisionIn — an exact answer over match text', () {
    test('a canonical name is taken', () {
      expect(collisionIn('Sauerkraut', _entries)!.ingredientId, 'kraut');
    });

    test('so is an alias, and the ROW is what it names', () {
      final taken = collisionIn('Scallion', _entries)!;
      expect(taken.ingredientName, 'Spring Onion');
      expect(taken.isAlias, isTrue);
    });

    test('the key is match text, so case and spacing fold — and a hyphen is a '
        'word break, not a letter', () {
      for (final spelling in ['  sauerkraut ', 'SAUERKRAUT']) {
        expect(collisionIn(spelling, _entries), isNotNull, reason: spelling);
      }
      for (final spelling in ['  Spring-Onion', 'spring  onion ']) {
        expect(collisionIn(spelling, _entries), isNotNull, reason: spelling);
      }
      // "Sauer-Kraut" is two words to the normalizer, so it is a different
      // name — the rule follows what is STORED, not what looks alike.
      expect(collisionIn('Sauer-Kraut', _entries), isNull);
    });

    test('a row never collides with itself', () {
      expect(collisionIn('Sauerkraut', _entries, selfId: 'kraut'), isNull);
      // …nor with its own alias.
      expect(collisionIn('scallion', _entries, selfId: 'spring'), isNull);
    });

    test('a name carrying no identity word is nobody’s', () {
      // The phrase normalizer strips it to nothing, and a row's match text is
      // never empty, so there is nothing here to land on.
      expect(collisionIn('   ', _entries), isNull);
    });

    test('a free name is free', () {
      expect(collisionIn('Kimchi', _entries), isNull);
    });
  });

  // Every "add a new ingredient" door in the app is the same footer pushing
  // the same form, which is why the guard above covers the import review's
  // create-new and the recipe editor's without either knowing about it.
  test('every create-new door is the one row pushing the one form', () {
    const footers = [
      'lib/features/ingredients/presentation/ingredient_picker.dart',
      'lib/features/recipes/presentation/line_target_picker.dart',
      'lib/features/import/presentation/recon_resolver.dart',
      'lib/features/shopping/presentation/add_shopping_item_sheet.dart',
    ];
    for (final path in footers) {
      expect(
        File(path).readAsStringSync(),
        contains('AddNewIngredientRow('),
        reason: '$path should add ingredients through the shared footer',
      );
    }
    final pushers = [
      for (final file in dartFiles(Directory('lib')))
        if (blankNonCode(
          file.readAsStringSync(),
        ).contains('newIngredientRoute('))
          file.path,
    ]..sort();
    expect(pushers, [
      // Where the route is declared, and the two doors that push it: the
      // shared footer, and the manager's own `＋`.
      'lib/features/ingredients/presentation/ingredient_detail_view.dart',
      'lib/features/ingredients/presentation/ingredient_list_view.dart',
      'lib/features/ingredients/presentation/ingredient_picker.dart',
    ]);
  });

  group('the form says so under the field it is about', () {
    testWidgets('a taken name is refused inline, and Save goes quiet', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [_sauerkraut]), at: '/ingredients/new'),
      );
      await tester.pumpAndSettle();

      await tester.enterText(nameField, 'sauerkraut');
      await tester.pump();
      await leaveTheField(tester);

      expect(find.text(kNameTakenPrefix), findsOneWidget);
      expect(
        saveButton(tester).onPress,
        isNull,
        reason: 'the write would refuse it, so the button must not offer it',
      );
    });

    testWidgets('the existing name is a DOOR onto that row', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [_sauerkraut]), at: '/ingredients/new'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(nameField, 'Sauerkraut');
      await tester.pump();
      await leaveTheField(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(Wrap),
          matching: find.text('Sauerkraut'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CANONICAL NAME'), findsNothing);
      expect(
        find.text('Complete — counts in conversions and macro totals.'),
        findsOneWidget,
        reason: 'the door lands on the row that already has the name',
      );
    });

    testWidgets('renaming an EXISTING row onto another one is refused the '
        'same way', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango, _sauerkraut]),
          at: editRoute('mango'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(nameField, 'Sauerkraut');
      await tester.pump();
      await leaveTheField(tester);

      expect(find.text(kNameTakenPrefix), findsOneWidget);
      expect(saveButton(tester).onPress, isNull);
    });

    testWidgets('an alias already in the namespace is refused in the alias '
        'editor’s own voice', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango, _sauerkraut]);
      await tester.pumpWidget(host(repo, at: editRoute('mango')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alias'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('alias-entry')),
        'sauerkraut',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('alias-add')));
      await tester.pumpAndSettle();

      expect(find.text(kNameTakenPrefix), findsOneWidget);
      expect(find.text('Sauerkraut'), findsOneWidget);
      // Refused means not taken into the draft: no chip, and nothing for a
      // Save to write.
      expect(find.byKey(const ValueKey('alias-entry')), findsOneWidget);
    });
  });
}
