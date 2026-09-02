/// Pins the editor draft lifecycle: saving a draft must reset the notifier so
/// the next "New recipe" open starts blank, even when the provider instance
/// outlives the editor screen (auto-dispose only fires once the last listener
/// is gone, which navigation timing can defer).
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/book_repository.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_repository.dart';
import 'package:ansi/features/recipes/presentation/recipe_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
  Future<List<RecipeUse>> usedIn(String recipeId) async => const [];

  @override
  Future<bool> componentLinkWouldCycle({
    required String recipeId,
    required String subRecipeId,
  }) async => false;
}

class _FakeBookRepo implements BookRepository {
  static const _book = Book(id: 'b1', name: 'Our Cookbook');

  @override
  Stream<List<Book>> watchLibrary() => Stream.value(const [_book]);

  @override
  Future<Book> ensureDefaultBook() async => _book;

  @override
  Future<String> createBook(String name) async => 'b';

  @override
  Future<String> createSection(String bookId, String name) async => 's';

  @override
  Future<void> renameSection(String sectionId, String name) async {}

  @override
  Future<void> reorderSections(String b, List<String> ids) async {}

  @override
  Future<void> deleteSection(String sectionId) async {}

  @override
  Future<void> assignRecipe(
    String recipeId, {
    required String bookId,
    String? sectionId,
  }) async {}
}

void main() {
  test('a "New recipe" open after a save starts from a clean draft', () async {
    final repo = _FakeRecipeRepo();
    final container = ProviderContainer(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repo),
        bookRepositoryProvider.overrideWithValue(_FakeBookRepo()),
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

  group('the MAKES row (step 8.6 / D2 · D9, board frame h)', () {
    Future<RecipeEditor> editor(ProviderContainer container) async {
      await container.read(recipeEditorProvider(null).future);
      return container.read(recipeEditorProvider(null).notifier);
    }

    ProviderContainer host() {
      final container = ProviderContainer(
        overrides: [
          recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
          bookRepositoryProvider.overrideWithValue(_FakeBookRepo()),
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
