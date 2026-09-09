/// Leaving the canonical-name field is when the name is tidied, and a WORD
/// that changed says so — `was “chopped onions” · keep the old word`.
///
/// The two tiers are unit-tested next door (`name_clean_test`,
/// `suggest_name_test`); what these pin is the *moment* — that the field takes
/// the tidied text, that the revert line appears for a word and not for a
/// capital, that keeping puts the typed name back and stops the suggestion
/// coming again, and that Save is the backstop for a field never left.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// The canonical-name input.
final Finder nameField = find
    .descendant(
      of: find.byType(IngredientDetailView),
      matching: find.byType(TextField),
    )
    .first;

/// Leaves the field the way a person does — the keyboard goes away and focus
/// with it.
Future<void> leaveTheField(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> typeName(WidgetTester tester, String text) async {
  await tester.enterText(nameField, text);
  await tester.pump();
}

void main() {
  group('the canonical name is tidied when the field is left', () {
    testWidgets('a recipe line becomes the entry, and the line says what it '
        'was', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();

      await typeName(tester, 'chopped onions');
      expect(find.textContaining('was '), findsNothing);

      await leaveTheField(tester);
      expect(fieldText(tester, nameField), 'Onion');
      expect(find.text('was “chopped onions”'), findsOneWidget);
      expect(find.text('keep the old word'), findsOneWidget);
    });

    testWidgets('keep the old word puts the typed name back and takes the '
        'line away', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();

      await typeName(tester, 'chopped onions');
      await leaveTheField(tester);
      await tester.tap(find.text('keep the old word'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, nameField), 'chopped onions');
      expect(find.text('keep the old word'), findsNothing);
    });

    testWidgets('a kept name is not suggested again — the next leave recases '
        'it and offers nothing', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();

      await typeName(tester, 'chopped onions');
      await leaveTheField(tester);
      await tester.tap(find.text('keep the old word'));
      await tester.pumpAndSettle();

      // Back into the field and out again: the pin follows the recasing, so
      // the suggestion stays away.
      await tester.tap(nameField);
      await tester.pumpAndSettle();
      await leaveTheField(tester);

      expect(fieldText(tester, nameField), 'Chopped Onions');
      expect(find.text('keep the old word'), findsNothing);
    });

    testWidgets('Save writes a kept name with its words intact — only the '
        'case is the app’s', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(host(repo, at: '/ingredients/mango'));
      await tester.pumpAndSettle();

      await typeName(tester, 'chopped onions');
      await leaveTheField(tester);
      await tester.tap(find.text('keep the old word'));
      await tester.pumpAndSettle();

      await saveForm(tester);
      expect(repo.savedForms.single.row.canonicalName, 'Chopped Onions');
    });

    testWidgets('editing after a keep lets the suggestion come back', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();

      await typeName(tester, 'chopped onions');
      await leaveTheField(tester);
      await tester.tap(find.text('keep the old word'));
      await tester.pumpAndSettle();

      await typeName(tester, 'diced carrots');
      await leaveTheField(tester);
      expect(fieldText(tester, nameField), 'Carrot');
      expect(find.text('was “diced carrots”'), findsOneWidget);
    });

    testWidgets('case and spacing change silently — no line', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();

      await typeName(tester, '  cream  of   tartar ');
      await leaveTheField(tester);

      expect(fieldText(tester, nameField), 'Cream of Tartar');
      expect(find.text('keep the old word'), findsNothing);
    });
  });

  group('Save is the backstop for a field that was never left', () {
    testWidgets('a name typed and saved straight from the keyboard is tidied '
        'on the way out', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(host(repo, at: '/ingredients/mango'));
      await tester.pumpAndSettle();

      await typeName(tester, '  2 cups  plain flour ');
      await saveForm(tester);

      expect(repo.savedForms.single.row.canonicalName, 'Plain Flour');
    });
  });

  group('the alias entry', () {
    testWidgets('an alias is respaced, and never recased — the vocabulary '
        'stores it lowercase', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(host(repo, at: '/ingredients/mango'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alias'));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('alias-entry'));
      await tester.enterText(entry, '  spring   onion. ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('alias-add')));
      await tester.pumpAndSettle();

      expect(find.text('spring onion'), findsOneWidget);
      await saveForm(tester);
      expect(repo.savedForms.single.aliasesAdded.single.text, 'spring onion');
    });
  });
}
