/// Sim smoke — LIBRARY: the Library v2 surfaces the editor and ingredients
/// files walk past but never drive — the fold, the pinned title search (and
/// its `DID YOU MEAN` band), the book `⋯` (rename, the delete refused with a
/// count and "Move them to…") and the reorder sheet — on the real stack, so
/// a sheet on the wrong navigator or a write that never uploads shows here
/// before it shows on a phone.
///
/// The second book and the recipe filed in it are SEEDED through the app's
/// own repositories over the throwaway database and round-tripped through
/// sync before the first tap; the recipe editor is the editor file's
/// business. Every write the taps make is asserted in the local db after
/// the upload queue drains, so the rename and the reorder are proven to have
/// reached the server and come back down.
///
/// Local gate only (`make test-sim FILE=library`), never CI. Needs the local
/// backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'package:ansi/features/books/data/book_repository_impl.dart';
import 'package:ansi/features/books/presentation/library_view.dart'
    show LibraryView;
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/drive.dart';
import 'support/library.dart';
import 'support/stack.dart';

const _uuid = Uuid();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  testWidgets('library: fold, search, rename, the refused delete, reorder', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);

    // A second shelf with one recipe on it, through the real repositories:
    // "Baking" holds "Sourdough". The default book the session controller
    // ensured stays empty, so the two cards read differently.
    final books = SqliteBookRepository(db, householdId: stack.householdId);
    final bakingId = await books.createBook('Baking');
    await SqliteRecipeRepository(db, householdId: stack.householdId).saveRecipe(
      Recipe(
        id: _uuid.v4(),
        title: 'Sourdough',
        servingsBase: 1,
        bookId: bakingId,
      ),
    );
    await pumpUntilFound(tester, find.text('Sourdough'));
    await stack.waitForSyncRoundTrip(tester);
    expect(find.text('Our Cookbook'), findsOneWidget);
    expect(find.text('no recipes yet'), findsOneWidget);
    expect(find.text('Baking'), findsOneWidget);
    expect(find.text('1 recipe'), findsOneWidget);

    // ------------------------------------------------------------------------
    // Fold (D3): the chevron hides the contents and keeps the count; unfold
    // brings them back. Per device, never synced — nothing to assert in the
    // db, and the folded set is keyed by this run's fresh book id.
    // ------------------------------------------------------------------------
    await tester.tap(
      find.descendant(
        of: bookCard('Baking'),
        matching: find.byIcon(FLucideIcons.chevronDown),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sourdough'), findsNothing);
    expect(find.text('1 recipe'), findsOneWidget, reason: 'the count stays');
    await tester.tap(
      find.descendant(
        of: bookCard('Baking'),
        matching: find.byIcon(FLucideIcons.chevronRight),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sourdough'), findsOneWidget);

    // ------------------------------------------------------------------------
    // The pinned title search (D2): a live query replaces the tree with filed
    // rows, a typo lands under `DID YOU MEAN`, and clearing restores the tree.
    // ------------------------------------------------------------------------
    final search = fieldIn(find.byType(LibraryView));
    await tester.enterText(search, 'sour');
    await tester.pumpAndSettle();
    expect(find.text('Sourdough'), findsOneWidget);
    expect(find.text('Baking · Unsectioned'), findsOneWidget);
    expect(find.text('Our Cookbook'), findsNothing, reason: 'no tree');
    expect(find.text('DID YOU MEAN'), findsNothing);
    await tester.enterText(search, 'sordough');
    await tester.pumpAndSettle();
    expect(find.text('DID YOU MEAN'), findsOneWidget);
    expect(find.text('Sourdough'), findsOneWidget);
    await tester.enterText(search, '');
    await tester.pumpAndSettle();
    expect(find.text('Our Cookbook'), findsOneWidget);
    expect(find.text('Baking'), findsOneWidget);
    expect(find.text('Sourdough'), findsOneWidget);

    // ------------------------------------------------------------------------
    // The book ⋯ (D4) — rename, through the prompt, and the write survives
    // the round trip.
    // ------------------------------------------------------------------------
    await openBookMenu(tester, 'Baking');
    await tester.tap(find.text('Rename'));
    await pumpUntilFound(tester, find.text('Rename book'));
    // The dialog's field, in the overlay above the pinned search.
    await tester.enterText(find.byType(EditableText).last, 'Bread');
    await tester.pump();
    await tester.tap(find.text('Rename'));
    await pumpUntilFound(tester, find.text('Bread'));
    expect(find.text('Baking'), findsNothing);
    await stack.waitForSyncRoundTrip(tester);
    final renamed = await db.get('SELECT name FROM book WHERE id = ?', [
      bakingId,
    ]);
    expect(renamed['name'], 'Bread');

    // The delete of a book that holds a recipe is refused with the count and
    // the door — and nothing is deleted, whichever way the dialog is left.
    await openBookMenu(tester, 'Bread');
    await tester.tap(find.text('Delete book'));
    await pumpUntilFound(tester, find.text('Can’t delete “Bread” yet'));
    expect(find.textContaining('It holds 1 recipe.'), findsOneWidget);
    expect(find.text('Move them to…'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);
    final kept = await db.get(
      'SELECT COUNT(*) AS c FROM book WHERE deleted_at IS NULL',
    );
    expect(kept['c'], 2);

    // ------------------------------------------------------------------------
    // Reorder, off the BOOK's own ⋯ (0028 E4): the sheet that used to do this
    // from the header was a second user interface for `_BookMenu._move` —
    // the same splice and `reorderBooks` — so it was deleted rather than
    // moved. "Bread" goes above the default book, and the order round-trips.
    // ------------------------------------------------------------------------
    await openBookMenu(tester, 'Bread');
    await tester.tap(find.text('Move up'));
    await tester.pumpAndSettle();
    await stack.waitForSyncRoundTrip(tester);
    final order = await db.getAll(
      'SELECT name FROM book WHERE deleted_at IS NULL ORDER BY sort_order',
    );
    expect(order.map((r) => r['name']).toList(), ['Bread', 'Our Cookbook']);
    expect(
      tester.getTopLeft(find.text('Bread')).dy,
      lessThan(tester.getTopLeft(find.text('Our Cookbook')).dy),
      reason: 'the Library redraws in the new order',
    );

    // ------------------------------------------------------------------------
    // Move to… off the RECIPE row's own ⋯ (0028 E8): re-shelving is a library
    // act, so it happens where the shelves are visible — and on a narrow
    // `setFiling` write, never a whole-recipe save. "Sourdough" leaves Bread
    // for the default book, and the new filing round-trips.
    // ------------------------------------------------------------------------
    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.text('Sourdough'),
              matching: find.byType(Row),
            ),
            matching: find.byIcon(FLucideIcons.ellipsis),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await pumpUntilFound(tester, find.text('here now'));
    // The shelf it is on now is marked and refuses to be picked; the target
    // says what will happen before the tap that does it.
    await tester.tap(find.text('Our Cookbook').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('moves to Our Cookbook · Unsectioned'),
      findsOneWidget,
    );
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    await stack.waitForSyncRoundTrip(tester);

    final filed = await db.get(
      'SELECT b.name AS book, r.section_id AS section FROM recipe r '
      'JOIN book b ON b.id = r.book_id WHERE r.title = ?',
      ['Sourdough'],
    );
    expect(filed['book'], 'Our Cookbook');
    expect(filed['section'], isNull);
    final onServer = await Supabase.instance.client
        .from('recipe')
        .select('book_id')
        .eq('title', 'Sourdough')
        .single();
    expect(onServer['book_id'], isNotNull);
    expect(
      find.text('no recipes yet'),
      findsOneWidget,
      reason: 'Bread is bare',
    );
  });
}
