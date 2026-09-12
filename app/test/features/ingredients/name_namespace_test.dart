/// The household's ingredient names and its aliases are ONE namespace, keyed
/// by `match_text` — the rule, the doors it has to cover, what the form says
/// when a name is already somebody's, and what it offers when the name was
/// very nearly one.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/name_namespace.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/source_scan.dart';
import '_form_harness.dart';
import 'ingredient_name_tidy_test.dart' show leaveTheField, nameField;

/// The shape every add-new door has: something pushes the create form and
/// **waits for the row it pops**. What the picker footer does, in a host small
/// enough to assert on.
Widget _pushHost(FakeIngredientRepo repo, {required List<Ingredient?> popped}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => FScaffold(
          child: Builder(
            builder: (context) => FButton(
              onPress: () async => popped.add(
                await context.push<Ingredient?>(newIngredientRoute()),
              ),
              child: const Text('add new'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/ingredients/new',
        builder: (_, state) =>
            IngredientDetailView(name: state.uri.queryParameters['name'] ?? ''),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [ingredientRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}

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

  group(
    'nearMatchesIn — the pickers’ band, over the names we already have',
    () {
      test('a typo of a canonical name is guessed at', () {
        expect(
          nearMatchesIn('Sauerkrout', _entries).single.ingredientId,
          'kraut',
        );
      });

      test('and a typo of an ALIAS finds its row — one namespace here too', () {
        final near = nearMatchesIn('Scallon', _entries).single;
        expect(near.ingredientName, 'Spring Onion');
        expect(near.isAlias, isTrue);
      });

      test('a name that WAS spelled right offers nothing — the band is the '
          'whole list or it is absent', () {
        // Tier 0: it is the name. (An exact hit is a collision, not a guess,
        // and the form shows the refusal instead.)
        expect(nearMatchesIn('Sauerkraut', _entries), isEmpty);
        // Tier 1: a word prefix is a spelling. "Spring" beside "Spring Onion"
        // is a person starting a different name, not a misspelling of that one.
        expect(nearMatchesIn('Spring', _entries), isEmpty);
      });

      test('under the typo tier’s own threshold it stays silent', () {
        // Three characters is where the phone stops guessing at a single-word
        // query (`kMinFuzzTokenLenSingle`), so this never reaches the band.
        expect(nearMatchesIn('Kra', _entries), isEmpty);
        expect(nearMatchesIn('Kimchi', _entries), isEmpty);
      });

      test('a row appears once however many of its names matched, and at most '
          'three rows are offered', () {
        const crowd = [
          NameEntry(
            ingredientId: 'kraut',
            ingredientName: 'Sauerkraut',
            text: 'Sauerkraut',
            matchText: 'sauerkraut',
          ),
          NameEntry(
            ingredientId: 'kraut',
            ingredientName: 'Sauerkraut',
            text: 'sauerkrautt',
            matchText: 'sauerkrautt',
            isAlias: true,
          ),
          NameEntry(
            ingredientId: 'b',
            ingredientName: 'Sauerkrauts',
            text: 'Sauerkrauts',
            matchText: 'sauerkrauts',
          ),
          NameEntry(
            ingredientId: 'c',
            ingredientName: 'Sauerkrant',
            text: 'Sauerkrant',
            matchText: 'sauerkrant',
          ),
          NameEntry(
            ingredientId: 'd',
            ingredientName: 'Sauerkrawt',
            text: 'Sauerkrawt',
            matchText: 'sauerkrawt',
          ),
        ];

        final near = nearMatchesIn('Sauerkrout', crowd);

        expect(near, hasLength(3));
        expect(near.map((n) => n.ingredientId).toSet(), hasLength(3));
      });

      test('the row being renamed is never offered its own name back', () {
        expect(nearMatchesIn('Sauerkrout', _entries, selfId: 'kraut'), isEmpty);
      });
    },
  );

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
        if (blankNonCode(file.readAsStringSync())
            .contains('newIngredientRoute('))
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

  group('did you mean — the band, under the name field', () {
    testWidgets('a near miss is offered under the pickers’ own header', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [_sauerkraut]), at: '/ingredients/new'),
      );
      await tester.pumpAndSettle();

      await tester.enterText(nameField, 'Sauerkrout');
      await tester.pump();
      await leaveTheField(tester);

      expect(find.text('DID YOU MEAN'), findsOneWidget);
      expect(find.text('Sauerkraut'), findsOneWidget);
      // A guess is never a refusal: the form is still saveable under the name
      // that was typed, which is the whole difference between the two notes.
      expect(find.text(kNameTakenPrefix), findsNothing);
    });

    testWidgets('a name nothing resembles says nothing at all', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [_sauerkraut]), at: '/ingredients/new'),
      );
      await tester.pumpAndSettle();

      await tester.enterText(nameField, 'Kimchi');
      await tester.pump();
      await leaveTheField(tester);

      expect(find.text('DID YOU MEAN'), findsNothing);
    });

    testWidgets('taking one asks first, and the form pops with the row that '
        'already exists', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final popped = <Ingredient?>[];
      await tester.pumpWidget(
        _pushHost(FakeIngredientRepo(const [_sauerkraut]), popped: popped),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('add new'));
      await tester.pumpAndSettle();

      await tester.enterText(nameField, 'Sauerkrout');
      await tester.pump();
      await leaveTheField(tester);
      await tester.tap(find.text('Sauerkraut'));
      await tester.pumpAndSettle();

      // It asks — the words in the field are a person's, and swapping them
      // for another row unasked is not the form's call.
      expect(find.text('Use Sauerkraut instead?'), findsOneWidget);
      await tester.tap(find.text('Use Sauerkraut'));
      await tester.pumpAndSettle();

      expect(popped.single!.id, 'kraut');
      expect(find.text('CANONICAL NAME'), findsNothing);
    });

    testWidgets('backing out of the question leaves the typed name alone', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final popped = <Ingredient?>[];
      await tester.pumpWidget(
        _pushHost(FakeIngredientRepo(const [_sauerkraut]), popped: popped),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('add new'));
      await tester.pumpAndSettle();
      await tester.enterText(nameField, 'Sauerkrout');
      await tester.pump();
      await leaveTheField(tester);
      await tester.tap(find.text('Sauerkraut'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep typing'));
      await tester.pumpAndSettle();

      expect(popped, isEmpty, reason: 'the form is still open');
      expect(fieldText(tester, nameField), 'Sauerkrout');
    });

    testWidgets('on a row that already EXISTS the near names are shown and '
        'nothing more — merging rows is not this form’s job', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango, _sauerkraut]),
          at: editRoute('mango'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(nameField, 'Sauerkrout');
      await tester.pump();
      await leaveTheField(tester);

      expect(find.text('DID YOU MEAN'), findsOneWidget);
      await tester.tap(find.text('Sauerkraut'));
      await tester.pumpAndSettle();

      expect(find.textContaining('instead?'), findsNothing);
      expect(fieldText(tester, nameField), 'Sauerkrout');
    });
  });
}
