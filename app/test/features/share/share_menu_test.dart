/// The recipe page's share link: the ⋯ menu's *Share link* and *Stop sharing*,
/// against a fake server and a fake platform hand-off.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_view.dart';
import 'package:ansi/features/share/data/share_providers.dart';
import 'package:ansi/features/share/domain/recipe_share_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_recipe_repository.dart';
import '../../helpers/pump_app.dart';

const _recipe = Recipe(
  id: 'r1',
  title: 'Miso Noodles',
  servingsBase: 2,
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        LineItem(
          id: 'i1',
          ingredientId: 'udon',
          ingredientName: 'Udon',
          unit: g,
          quantity: 400,
        ),
      ],
    ),
  ],
);

class _FakeRecipeRepo extends FakeRecipeRepository {
  _FakeRecipeRepo() : super(recipe: _recipe);

  @override
  Stream<List<RecipeSummary>> watchRecipes() => Stream.value([
    RecipeSummary(
      id: _recipe.id,
      title: _recipe.title,
      servingsBase: _recipe.servingsBase,
    ),
  ]);
}

/// The server, as far as the menu can tell: one live link or none.
class _FakeShares implements RecipeShareRepository {
  _FakeShares({this.live, this.offline = false, this.cannotAsk = false});

  String? live;
  final bool offline;
  final bool cannotAsk;
  final calls = <String>[];

  @override
  Future<String> share(String recipeId) async {
    calls.add('share $recipeId');
    if (offline) throw Exception('no connection');
    return live ??= 'Tok3n_Tok3n-Tok3n_Tok3';
  }

  @override
  Future<bool> unshare(String recipeId) async {
    calls.add('unshare $recipeId');
    if (offline) throw Exception('no connection');
    final had = live != null;
    live = null;
    return had;
  }

  @override
  Future<bool> isShared(String recipeId) async {
    if (cannotAsk) throw Exception('no connection');
    return live != null;
  }
}

typedef _HandOff = ({String url, String subject});

Future<List<_HandOff>> _pump(
  WidgetTester tester, {
  required _FakeShares shares,
  String base = 'https://getansi.app',
  LinkHandOff outcome = LinkHandOff.offered,
}) async {
  final handed = <_HandOff>[];
  await tester.pumpWidget(
    routedHost(
      initial: '/recipes/r1',
      routes: {
        '/recipes/:id': (_, state) =>
            RecipeView(recipeId: state.pathParameters['id']!),
      },
      overrides: [
        recipeRepositoryProvider.overrideWithValue(_FakeRecipeRepo()),
        recipeShareRepositoryProvider.overrideWithValue(shares),
        shareBaseUrlProvider.overrideWithValue(base),
        handOffLinkProvider.overrideWithValue(({
          required url,
          required subject,
          origin,
        }) async {
          handed.add((url: url, subject: subject));
          return outcome;
        }),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return handed;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(FLucideIcons.ellipsis));
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String label) async {
  await _openMenu(tester);
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a build with no share host offers no link', (tester) async {
    final shares = _FakeShares();
    await _pump(tester, shares: shares, base: '');
    await _openMenu(tester);

    expect(find.text('Share link'), findsNothing);
    expect(find.text('Stop sharing'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('Share link asks the server and hands the URL to the sheet', (
    tester,
  ) async {
    final shares = _FakeShares();
    final handed = await _pump(tester, shares: shares);

    await _openMenu(tester);
    expect(find.text('Stop sharing'), findsNothing);
    await tester.tap(find.text('Share link'));
    await tester.pumpAndSettle();

    expect(shares.calls, ['share r1']);
    expect(handed, [
      (
        url: 'https://getansi.app/r/Tok3n_Tok3n-Tok3n_Tok3',
        subject: 'Miso Noodles',
      ),
    ]);
    // Offered through the sheet: nothing to say on screen.
    expect(find.text('Link copied.'), findsNothing);
  });

  testWidgets('sharing twice sends the same link', (tester) async {
    final shares = _FakeShares(live: 'SameSameSameSameSame_1');
    final handed = await _pump(tester, shares: shares);

    await _menu(tester, 'Share link');
    await _menu(tester, 'Share link');

    expect(handed.map((h) => h.url).toSet(), {
      'https://getansi.app/r/SameSameSameSameSame_1',
    });
  });

  testWidgets('where the link is copied rather than offered, a toast says so', (
    tester,
  ) async {
    await _pump(tester, shares: _FakeShares(), outcome: LinkHandOff.copied);

    await _menu(tester, 'Share link');

    expect(find.text('Link copied.'), findsOneWidget);
  });

  testWidgets('offline, sharing says it could not, and hands nothing over', (
    tester,
  ) async {
    final handed = await _pump(tester, shares: _FakeShares(offline: true));

    await _menu(tester, 'Share link');

    expect(find.text('Couldn’t share this recipe.'), findsOneWidget);
    expect(handed, isEmpty);
  });

  testWidgets('a standing link offers Stop sharing, which asks first', (
    tester,
  ) async {
    final shares = _FakeShares(live: 'LiveLiveLiveLiveLive_1');
    await _pump(tester, shares: shares);

    await _openMenu(tester);
    expect(find.text('Share link'), findsOneWidget);
    await tester.tap(find.text('Stop sharing'));
    await tester.pumpAndSettle();

    expect(find.text('Stop sharing this recipe?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(shares.calls, isEmpty);
    expect(shares.live, isNotNull);

    await _menu(tester, 'Stop sharing');
    await tester.tap(find.widgetWithText(FButton, 'Stop sharing'));
    await tester.pumpAndSettle();

    expect(shares.calls, ['unshare r1']);
    expect(shares.live, isNull);
    // The menu asks again, and there is nothing left to stop.
    await _openMenu(tester);
    expect(find.text('Stop sharing'), findsNothing);
    expect(find.text('Share link'), findsOneWidget);
  });

  testWidgets('a page that could not ask offers sharing alone', (tester) async {
    await _pump(
      tester,
      shares: _FakeShares(live: 'LiveLiveLiveLiveLive_1', cannotAsk: true),
    );

    await _openMenu(tester);
    expect(find.text('Share link'), findsOneWidget);
    expect(find.text('Stop sharing'), findsNothing);
  });
}
