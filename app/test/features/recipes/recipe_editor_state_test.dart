/// Pins the editor draft lifecycle: saving a draft must reset the notifier so
/// the next "New recipe" open starts blank, even when the provider instance
/// outlives the editor screen (auto-dispose only fires once the last listener
/// is gone, which navigation timing can defer).
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/recipe_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';

class _FakeRecipeRepo implements RecipeRepository {
  final saved = <Recipe>[];

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value(const []);

  @override
  Stream<Recipe?> watchRecipe(String id) => Stream.value(null);

  @override
  Future<void> saveRecipe(Recipe recipe) async => saved.add(recipe);

  @override
  Future<void> deleteRecipe(String id) async {}

  @override
  Future<void> setFavorite(String id, bool favorite) async {}
  @override
  Future<void> setFiling(String id, String bookId, String? sectionId) async {}

  @override
  Future<List<RecipeUse>> usedIn(String recipeId) async => const [];

  @override
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  }) async => false;
}

class _FakeBookRepo extends FakeBookRepository {
  const _FakeBookRepo() : super(const [Book(id: 'b1', name: 'Our Cookbook')]);
}

void main() {
  test('a "New recipe" open after a save starts from a clean draft', () async {
    final repo = _FakeRecipeRepo();
    final container = ProviderContainer(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repo),
        bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
      ],
    );
    addTearDown(container.dispose);

    // Hold a listener for the whole scenario, simulating a provider instance
    // that survives the save (the live leak this test pins).
    final sub = container.listen(recipeEditorProvider(null), (_, _) {});
    addTearDown(sub.close);

    final first = await container.read(recipeEditorProvider(null).future);
    container.read(recipeEditorProvider(null).notifier)
      ..setTitle('Weeknight Chicken Curry')
      ..addGroup();
    final id = await container.read(recipeEditorProvider(null).notifier).save();

    expect(repo.saved, hasLength(1));
    expect(id, first.id);

    // A fresh open of the same provider must be a blank draft again — new id,
    // empty title, a single empty group.
    final next = await container.read(recipeEditorProvider(null).future);
    expect(next.id, isNot(first.id));
    expect(next.title, isEmpty);
    expect(next.groups, hasLength(1));
    expect(next.groups.single.items, isEmpty);
  });

  test(
    'a draft opened with a title starts from it (Library v2 / D7)',
    () async {
      final container = ProviderContainer(
        overrides: [
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
          bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
        ],
      );
      addTearDown(container.dispose);

      // What `/recipes/new?title=romes` carries over from the Library's
      // "nothing matches" state: you searched for a recipe you were about to
      // write, so the editor opens on it rather than on an empty form.
      final seeded = await container.read(
        recipeEditorProvider(null, initialTitle: '  Romesco Aioli  ').future,
      );
      expect(seeded.title, 'Romesco Aioli');

      // A plain "New recipe" is still blank, and is a different draft.
      final blank = await container.read(recipeEditorProvider(null).future);
      expect(blank.title, isEmpty);
      expect(blank.id, isNot(seeded.id));
    },
  );

  test('a draft opened from a section door is filed there, not in the default '
      'book (0028 E3)', () async {
    final container = ProviderContainer(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
        bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
      ],
    );
    addTearDown(container.dispose);

    // What `/recipes/new?book=b9&section=s9` carries: the shelf the ＋ was
    // standing on. `ensureDefaultBook` is not consulted at all.
    final filed = await container.read(
      recipeEditorProvider(
        null,
        initialBookId: 'b9',
        initialSectionId: 's9',
      ).future,
    );
    expect(filed.bookId, 'b9');
    expect(filed.sectionId, 's9');

    // The Unsectioned door files into the book and leaves the section null.
    final unsectioned = await container.read(
      recipeEditorProvider(null, initialBookId: 'b9').future,
    );
    expect(unsectioned.bookId, 'b9');
    expect(unsectioned.sectionId, isNull);
    expect(unsectioned.id, isNot(filed.id));

    // And with no door to inherit from, the default book as always.
    final plain = await container.read(recipeEditorProvider(null).future);
    expect(plain.bookId, 'b1');
    expect(plain.sectionId, isNull);
  });

  group('the MAKES row (step 8.6 / D2 · D9, board frame h)', () {
    Future<RecipeEditor> editor(ProviderContainer container) async {
      await container.read(recipeEditorProvider(null).future);
      return container.read(recipeEditorProvider(null).notifier);
    }

    ProviderContainer host() {
      final container = ProviderContainer(
        overrides: [
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
          bookRepositoryProvider.overrideWithValue(const _FakeBookRepo()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('states what one batch makes, in up to two denominations', () async {
      final container = host();
      final notifier = await editor(container);
      notifier
        ..setYield(250, g)
        ..setSecondYield(16, tbsp);

      final recipe = container.read(recipeEditorProvider(null)).requireValue;
      expect(recipe.yields, [(qty: 250.0, unit: g), (qty: 16.0, unit: tbsp)]);
      // Serves is untouched: two independent facts (D2).
      expect(recipe.servingsBase, 2);
    });

    test('the second slot refuses the first slot’s own family', () async {
      final container = host();
      final notifier = await editor(container);
      notifier
        ..setYield(250, g)
        ..setSecondYield(1, kg);

      final recipe = container.read(recipeEditorProvider(null)).requireValue;
      expect(recipe.yieldQty2, isNull, reason: 'two numbers in one family');
      expect(recipe.yields, hasLength(1));
    });

    test('a second denomination cannot exist without a first', () async {
      final container = host();
      final notifier = await editor(container)
        ..setSecondYield(16, tbsp);
      expect(
        container.read(recipeEditorProvider(null)).requireValue.yieldQty2,
        isNull,
      );
      // …and clearing the first drops the second with it, so a save can never
      // bounce off the migration's CHECK.
      notifier
        ..setYield(250, g)
        ..setSecondYield(16, tbsp)
        ..setYield(null, null);
      final recipe = container.read(recipeEditorProvider(null)).requireValue;
      expect(recipe.yieldQty, isNull);
      expect(recipe.yieldUnit2, isNull);
      expect(recipe.yields, isEmpty);
    });

    test('a component line is added with the other identity (D1)', () async {
      final container = host();
      final notifier = await editor(container);
      final groupId = container
          .read(recipeEditorProvider(null))
          .requireValue
          .groups
          .single
          .id;
      notifier.addComponentLineItem(
        groupId,
        const SubRecipeTarget(id: 'aioli', title: 'Romesco Aioli'),
        quantity: 0.25,
        unit: cup,
      );

      final line = container
          .read(recipeEditorProvider(null))
          .requireValue
          .groups
          .single
          .items
          .single;
      expect(line.subRecipeId, 'aioli');
      expect(line.ingredientId, isNull);
      expect(line.measureId, isNull, reason: 'measures are an ingredient idea');
      expect(line.quantity, 0.25);
      expect(line.unit, cup);
    });

    test('a component added with no amount still counts in batches', () async {
      final container = host();
      final notifier = await editor(container);
      final groupId = container
          .read(recipeEditorProvider(null))
          .requireValue
          .groups
          .single
          .id;
      notifier.addComponentLineItem(
        groupId,
        const SubRecipeTarget(id: 'aioli', title: 'Romesco Aioli'),
      );
      final line = container
          .read(recipeEditorProvider(null))
          .requireValue
          .groups
          .single
          .items
          .single;
      expect(line.unit, batches);
    });
  });
}
