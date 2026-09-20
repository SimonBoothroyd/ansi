/// Authoring a word end to end, over the real PowerSync views: the recipe
/// editor's own host states it, the editor's Save writes it, and another
/// recipe's component line saying it resolves on reload.
///
/// It runs the EDITOR'S HOST — `RecipeEditor`, the notifier the MEASURES
/// section drives — against a real database rather than a fake, because the
/// deferred door's whole claim is that a word typed in a form lands with the
/// recipe through `saveRecipe`'s child diff. The widget's own half (which
/// refusal is shown, what the form clears) is pinned by
/// `recipe_measures_editor_test.dart`; the call this file makes into
/// `authorRecipeMeasure` is the one that widget makes, in the same order, so
/// what is proved here is the chain below it: draft → diff → row → resolution.
library;

import 'dart:io';

import 'package:ansi/core/result/result.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/book_repository.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/data/recipe_measure_repository_impl.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_header_edits.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_authoring.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_repository.dart';
import 'package:ansi/features/recipes/presentation/recipe_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

class _OneBook implements BookRepository {
  static const _book = Book(id: 'bk', name: 'Our Cookbook');

  @override
  Stream<List<Book>> watchLibrary() => Stream.value(const [_book]);

  @override
  Future<Book> ensureDefaultBook() async => _book;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteRecipeRepository repo;
  late SqliteRecipeMeasureRepository words;
  late ProviderContainer container;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteRecipeRepository(db, householdId: 'h');
    words = SqliteRecipeMeasureRepository(db, householdId: 'h');
    container = ProviderContainer(
      overrides: [
        recipeRepositoryProvider.overrideWithValue(repo),
        recipeMeasureRepositoryProvider.overrideWithValue(words),
        bookRepositoryProvider.overrideWithValue(_OneBook()),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() => closeTestDb(db, dir));

  /// The editor over [recipeId] (or a new recipe), held for the test's life —
  /// it is autoDispose, and a host that vanished between two setters would be
  /// this file's bug rather than the seam's.
  Future<RecipeEditor> editor([String? recipeId]) async {
    final provider = recipeEditorProvider(recipeId);
    container.listen(provider, (_, _) {});
    await container.read(provider.future);
    return container.read(provider.notifier);
  }

  /// One word, authored exactly as the MEASURES editor authors it: the rule
  /// first, against what the draft says it makes, then into the draft.
  RecipeMeasure author(
    RecipeEditor host,
    String label,
    double amount,
    Unit unit,
  ) {
    final authored = authorRecipeMeasure(
      id: 'm-$label',
      recipeId: host.header.id,
      label: label,
      amount: amount,
      unit: unit,
      yields: host.header.yields,
      measures: host.header.measures,
      sortOrder: host.header.measures.length,
    );
    expect(authored, isA<Ok<RecipeMeasure>>(), reason: 'authored $label');
    final word = (authored as Ok<RecipeMeasure>).value;
    host.setMeasures([...host.header.measures, word]);
    return word;
  }

  test('a word typed in the editor lands with the recipe, and a component '
      'line saying it resolves', () async {
    final aioli = await editor();
    aioli
      ..setTitle('Romesco Aioli')
      ..setYield(300, g);
    author(aioli, 'blob', 15, g);
    // Nothing is in the database yet: the list rides the draft (ADR-0011).
    expect(await db.getAll('SELECT id FROM recipe_measure'), isEmpty);

    final saved = await aioli.save();
    final stored = await repo.watchRecipe(saved.id).first;
    expect(stored!.measures.single.label, 'blob');
    expect(stored.measures.single.amount, 15);
    expect(stored.measures.single.unit, g);
    expect(stored.measures.single.recipeId, saved.id);

    // A parent that says `3 blob` of it — the line the word exists for.
    await repo.saveRecipe(
      Recipe(
        id: 'sliders',
        title: 'Sausage Sliders',
        servingsBase: 8,
        groups: [
          IngredientGroup(
            id: 'sg',
            items: [
              LineItem(
                id: 'si1',
                subRecipeId: saved.id,
                ingredientName: 'Romesco Aioli',
                quantity: 3,
                recipeMeasureId: stored.measures.single.id,
              ),
            ],
          ),
        ],
      ),
    );

    final parent = await repo.watchRecipe('sliders').first;
    final line = parent!.groups.single.items.single;
    final target = line.subRecipe!;
    // `3 blob` is 45 g, and the aioli's own `makes 300 g` makes that 0.15 of a
    // batch — through the one resolution every reader uses.
    expect(
      resolveComponentAmount(
        quantity: line.quantity,
        unit: line.unit,
        yields: target.yields,
        recipeMeasureId: line.recipeMeasureId,
        measures: target.measures,
      ),
      isA<ResolvedComponentAmount>().having(
        (r) => r.batches,
        'batches',
        closeTo(0.15, 1e-9),
      ),
    );
  });

  test('a re-statement keeps the row, so the line follows the number', () async {
    final aioli = await editor();
    aioli
      ..setTitle('Romesco Aioli')
      ..setYield(300, g);
    author(aioli, 'blob', 15, g);
    final made = await aioli.save();

    // Re-opened, re-stated in place — the row keeps its id, which is the whole
    // reason this is not a delete and a re-add.
    final again = await editor(made.id);
    final row = again.header.measures.single;
    again.setMeasures([row.copyWith(amount: 18)]);
    await again.save();

    final stored = await repo.watchRecipe(made.id).first;
    expect(stored!.measures.single.id, row.id);
    expect(stored.measures.single.amount, 18);
    expect(
      await db.getAll('SELECT id FROM recipe_measure WHERE deleted_at IS NULL'),
      hasLength(1),
    );
  });

  test('a word the draft drops is retired by the Save — and refused while a '
      'line still says it', () async {
    final aioli = await editor();
    aioli
      ..setTitle('Romesco Aioli')
      ..setYield(300, g);
    author(aioli, 'blob', 15, g);
    final made = await aioli.save();

    // Nothing says it yet: the Save retires it.
    final dropping = await editor(made.id);
    dropping.setMeasures(const []);
    await dropping.save();
    expect(await words.watchRecipeMeasures(made.id).first, isEmpty);

    // Coined again, and this time a line says it.
    final again = await editor(made.id);
    final back = author(again, 'blob', 15, g);
    await again.save();
    await repo.saveRecipe(
      Recipe(
        id: 'sliders',
        title: 'Sausage Sliders',
        servingsBase: 8,
        groups: [
          IngredientGroup(
            id: 'sg',
            items: [
              LineItem(
                id: 'si1',
                subRecipeId: made.id,
                ingredientName: 'Romesco Aioli',
                quantity: 3,
                recipeMeasureId: back.id,
              ),
            ],
          ),
        ],
      ),
    );
    expect((await words.countLinesUsing(back.id)).lines, 1);

    final refused = await editor(made.id);
    refused.setMeasures(const []);
    await expectLater(refused.save(), throwsA(isA<RecipeMeasureInUse>()));
    // Refused, and nothing moved: the word is still the recipe's.
    expect(await words.watchRecipeMeasures(made.id).first, hasLength(1));
  });

  test('a Save that both re-states a word and takes its family away is '
      'refused by the repository, with the rule’s own sentence', () async {
    final aioli = await editor();
    aioli
      ..setTitle('Romesco Aioli')
      ..setYield(300, g);
    author(aioli, 'blob', 15, g);
    final made = await aioli.save();

    final both = await editor(made.id);
    // One Save, two edits: the batch is now a volume, and the word is re-stated
    // in grams. The gate judges the word against the `makes` this Save leaves
    // behind, which is the one it cannot be held to.
    both
      ..setYield(1, cup)
      ..setMeasures([both.header.measures.single.copyWith(amount: 18)]);
    await expectLater(
      both.save(),
      throwsA(
        isA<RecipeMeasureRefused>()
            .having((e) => e.code, 'code', 'recipe_measure/unit_family')
            .having(
              (e) => e.message,
              'message',
              contains('a recipe has no density'),
            ),
      ),
    );
    // Nothing landed — neither half of the Save.
    final stored = await repo.watchRecipe(made.id).first;
    expect(stored!.measures.single.amount, 15);
    expect(stored.yields, [(qty: 300.0, unit: g)]);
  });

  test('a word carried through a `makes` edit unchanged is never re-authored — '
      'the editor warns instead', () async {
    final aioli = await editor();
    aioli
      ..setTitle('Romesco Aioli')
      ..setYield(300, g);
    author(aioli, 'blob', 15, g);
    final made = await aioli.save();

    final orphaning = await editor(made.id);
    orphaning.setYield(1, cup);
    // The warning the editor's Save shows, computed off what the recipe said
    // when it opened.
    expect(orphaning.measuresOrphanedBySave().single.label, 'blob');

    // …and the Save goes through: a `makes` edit is the recipe's own fact, and
    // the word survives it (ADR-0018 rule 4).
    await orphaning.save();
    final stored = await repo.watchRecipe(made.id).first;
    expect(stored!.measures.single.amount, 15);
    expect(stored.yields, [(qty: 1.0, unit: cup)]);
    // Alive and unresolvable at once, which is the state every surface names.
    expect(
      recipeMeasureResolvesAgainst(stored.measures.single, stored.yields),
      isFalse,
    );
  });

  test('a recipe with no MAKES cannot coin a word at all — the refusal the '
      'disabled list carries', () async {
    final host = await editor();
    host.setTitle('Romesco Aioli');
    expect(
      authorRecipeMeasure(
        id: 'm-blob',
        recipeId: host.header.id,
        label: 'blob',
        amount: 15,
        unit: g,
        yields: host.header.yields,
      ),
      isA<Err<RecipeMeasure>>().having(
        (e) => e.failure.message,
        'message',
        kRecipeMeasureNoYieldRefusal,
      ),
    );
  });
}
