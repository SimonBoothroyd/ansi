import 'dart:async';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/theme/ansi_tokens.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/cook_plan.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/cost_price.dart';
import 'package:ansi/features/ingredients/domain/default_amount.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/presentation/week_header.dart';
import 'package:ansi/features/recipes/domain/effective_lines.dart';
import 'package:ansi/features/shopping/data/shopping_providers.dart';
import 'package:ansi/features/shopping/domain/at_home.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_repository.dart';
import 'package:ansi/features/shopping/presentation/confetti_burst.dart';
import 'package:ansi/features/shopping/presentation/shop_add_field.dart';
import 'package:ansi/features/shopping/presentation/shopping_view.dart';
import 'package:ansi/features/shopping/presentation/shopping_view_models.dart';
import 'package:ansi/shared/dashed_border_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_cook_plan_repository.dart';
import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_week_variant_repository.dart';
import '../../helpers/forui_semantics.dart';

/// A canned shopping list; mutations are no-ops (the screen just renders)
/// unless [live], when an entry tick re-derives the list the way the real
/// repository's stream would, and [emit] plays the other phone.
class _FakeShoppingRepo implements ShoppingRepository {
  _FakeShoppingRepo(this.list, {this.tickThrows = false, this.live = false});

  ShoppingList list;

  /// Whether a check-off refuses — the aisle case the status line and the
  /// failure toast exist for.
  final bool tickThrows;

  /// Whether a tick shows up on the stream.
  final bool live;
  final _changes = StreamController<ShoppingList>.broadcast();
  int tickCalls = 0;

  /// The `checked` the last entry tick asked for — false is an untick.
  bool? lastChecked;

  /// A list arriving by sync: nothing on this phone tapped.
  void emit(ShoppingList next) {
    list = next;
    _changes.add(next);
  }

  @override
  Stream<ShoppingList> watchShoppingList(DateTime weekStart) {
    final out = StreamController<ShoppingList>()..add(list);
    unawaited(out.addStream(_changes.stream));
    return out.stream;
  }

  @override
  Future<void> setIngredientChecked({
    required String ingredientId,
    required bool checked,
    required DateTime weekStart,
  }) async {}

  @override
  Future<void> setEntryChecked({
    required String entryId,
    required bool checked,
  }) async {
    tickCalls++;
    lastChecked = checked;
    if (tickThrows) throw StateError('RLS denied');
    if (!live) return;
    emit(
      list.copyWith(
        groups: [
          for (final g in list.groups)
            g.copyWith(
              items: [
                for (final i in g.items)
                  if (i.entryId == entryId) i.copyWith(checked: checked) else i,
              ],
            ),
        ],
      ),
    );
  }

  @override
  Future<void> addTopUp({
    required String ingredientId,
    required double quantity,
    required Unit unit,
    required DateTime weekStart,
    String? measureId,
  }) async {}

  @override
  Future<void> editContribution({
    required String contributionId,
    required double quantity,
    required Unit unit,
    String? measureId,
  }) async {}

  @override
  Future<void> removeContribution({required String contributionId}) async {}

  @override
  Future<void> addFreeTextItem({
    required String text,
    required DateTime weekStart,
    String? category,
  }) async {}

  @override
  Future<void> removeEntry({required String entryId}) async {}

  @override
  Future<LastAmount?> lastTopUp(String ingredientId) async => null;

  /// Every amount said at home, in order.
  final atHomeSet =
      <
        ({String ingredientId, double quantity, Unit unit, String? measureId})
      >[];

  /// Every ingredient whose amount at home was cleared, in order.
  final atHomeCleared = <String>[];

  @override
  Future<void> setAtHome({
    required String ingredientId,
    required double quantity,
    required Unit unit,
    required DateTime weekStart,
    String? measureId,
  }) async {
    atHomeSet.add((
      ingredientId: ingredientId,
      quantity: quantity,
      unit: unit,
      measureId: measureId,
    ));
  }

  @override
  Future<void> clearAtHome({
    required String ingredientId,
    required DateTime weekStart,
  }) async {
    atHomeCleared.add(ingredientId);
  }
}

Widget _host(List<Override> overrides, {bool disableAnimations = false}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: FTheme(
              data: ansiThemeData(),
              child: const FToaster(child: ShoppingView()),
            ),
          ),
        ),
      ),
    );

/// The screen under a real router, for the header door — `pushOnce` needs one,
/// and the ledger it opens has to be somewhere to land.
Widget _routerHost(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp.router(
    theme: ansiHostTheme(),
    routerConfig: GoRouter(
      initialLocation: '/shop',
      routes: [
        GoRoute(path: '/shop', builder: (_, _) => const ShoppingView()),
        GoRoute(path: '/receipts', builder: (_, _) => const Text('the ledger')),
      ],
    ),
    builder: (context, child) => FTheme(
      data: ansiThemeData(),
      child: FToaster(child: child!),
    ),
  ),
);

/// A desk-width window — the band the provenance pane belongs to. The other
/// suites run at the default surface, which is a phone's column.
void deskWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The screen inside a tab the shell can hide: [visible] false is how the
/// shell keeps a tab mounted once another is chosen (its tickers off).
Widget _tabHost(List<Override> overrides, ValueNotifier<bool> visible) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: FToaster(
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, on, _) =>
                  TickerMode(enabled: on, child: const ShoppingView()),
            ),
          ),
        ),
      ),
    );

/// Taps a row's amount, which opens (or folds) its breakdown on a phone.
Future<void> _openRow(WidgetTester tester, String identity) async {
  await tester.tap(find.byKey(shopAmountTargetKey(identity)));
  await tester.pump();
}

/// Taps a folded line open (or shut), scrolling it into view first.
Future<void> _openFold(WidgetTester tester, ShopFold fold) async {
  final line = find.byKey(shopFoldKey(fold));
  await tester.ensureVisible(line);
  await tester.pump();
  await tester.tap(line);
  await tester.pump();
}

/// Records every haptic the phone is asked for, by type.
List<String> _recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return haptics;
}

void main() {
  testWidgets('an empty list is a quiet line INSIDE the list '
      'chrome', (tester) async {
    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(
          _FakeShoppingRepo(const ShoppingList()),
        ),
      ]),
    );
    await tester.pump();

    // The chrome stays — and the chrome is the week switcher, not a screen
    // name (0025 D7c): the lit tab in the bar is what says "Shop".
    expect(find.byType(WeekSwitcher), findsOneWidget);
    expect(find.textContaining('Shopping list'), findsNothing);
    expect(
      find.textContaining('nothing to buy for this week yet'),
      findsOneWidget,
    );
    expect(find.text('plan a meal'), findsOneWidget);
    // The add field works with no plan at all, so it is never swapped away.
    expect(find.byKey(kShopAddFieldKey), findsOneWidget);
  });

  testWidgets('an empty list but a live plan explains the missing '
      'ingredients', (tester) async {
    const planned = CookPlan(
      recipes: [
        RecipeCookPlan(
          recipeId: 'r1',
          title: 'Chicken Curry',
          servingsBase: 2,
          sessions: [
            CookSession(
              recipeId: 'r1',
              recipeTitle: 'Chicken Curry',
              servingsBase: 2,
              cookDay: 0,
              covers: [
                CoveredMeal(dayOfWeek: 0, mealSlot: 'Dinner', portions: 2),
              ],
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(
          _FakeShoppingRepo(const ShoppingList()),
        ),
        cookPlanRepositoryProvider.overrideWithValue(
          FakeCookPlanRepository(planned),
        ),
      ]),
    );
    await tester.pump(); // shopping list stream
    await tester.pump(); // cook plan stream

    // The two causes are still told apart — inside the list chrome, with the
    // add field still on screen.
    expect(find.textContaining('nothing to sum yet'), findsOneWidget);
    expect(find.textContaining('list no ingredients'), findsOneWidget);
    expect(find.text('add ingredients to a recipe'), findsOneWidget);
    expect(
      find.byKey(kShopAddFieldKey),
      findsOneWidget,
      reason: 'a staple works with no plan at all — never take that away',
    );
  });

  testWidgets('renders grouped items and totals, with the provenance behind '
      'the amount', (tester) async {
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Baking',
          items: [
            ShoppingItem(
              name: 'Flour',
              ingredientId: 'flour',
              totals: [Quantity(500, g)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Curry · cook Mon',
                  quantity: 300,
                  unit: g,
                  cookDay: 0,
                ),
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Oat Cookies',
                  quantity: 200,
                  unit: g,
                ),
              ],
            ),
          ],
        ),
        const ShoppingGroup(
          label: 'Non-food',
          items: [ShoppingItem(name: 'Paper towels', entryId: 'e1')],
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    expect(find.text('BAKING'), findsOneWidget);
    expect(find.text('Flour'), findsOneWidget);
    expect(find.text('500 g'), findsOneWidget);
    // Folded until its amount is tapped: one line a row, not five.
    expect(find.text('Curry · cook Mon'), findsNothing);
    expect(find.text('NON-FOOD'), findsOneWidget);
    expect(find.text('Paper towels'), findsOneWidget);
    // A numberless non-food staple shows an em dash.
    expect(find.text('—'), findsOneWidget);
    // Adding starts from the field at the top; the foot holds no add door.
    expect(find.byKey(kShopAddFieldKey), findsOneWidget);
    expect(find.textContaining('add item or top up'), findsNothing);
    // No caption: the list says what it is by being it.
    expect(find.textContaining('summed from the cook plan'), findsNothing);

    await _openRow(tester, 'flour');
    expect(find.text('Curry · cook Mon'), findsOneWidget);
    expect(find.text('Oat Cookies'), findsOneWidget);
  });

  testWidgets('a single-source row opens to say where it came from', (
    tester,
  ) async {
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Dairy',
          items: [
            ShoppingItem(
              name: 'Halloumi',
              ingredientId: 'halloumi',
              totals: [Quantity(250, g)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Charred Broccoli & Halloumi Salad · cook Wed',
                  quantity: 250,
                  unit: g,
                  cookDay: 2,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    await _openRow(tester, 'halloumi');
    expect(
      find.text('Charred Broccoli & Halloumi Salad · cook Wed'),
      findsOneWidget,
    );
  });

  testWidgets('a row asked for in one measure is shopped in it', (
    tester,
  ) async {
    const can = Measure(id: 'ml', label: 'can (400 g), drained', amount: 240);
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Canned Lentils',
              ingredientId: 'lentils',
              totals: [Quantity(240, g)],
              measureTotal: const (amount: 1, measure: can),
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Dal · cook Mon',
                  quantity: 1,
                  measure: can,
                  cookDay: 0,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    // The total is what goes in the basket, not the 8.47 oz it weighs…
    expect(find.text('1 can (400 g), drained'), findsOneWidget);
    // …with the honest mass beside the total, never instead of it.
    expect(find.text('240 g'), findsOneWidget);
    expect(find.textContaining('oz'), findsNothing);
    // Opened, twice over: the one line behind it says the same words.
    await _openRow(tester, 'lentils');
    expect(find.text('1 can (400 g), drained'), findsNWidgets(2));
    expect(find.text('Dal · cook Mon'), findsOneWidget);
  });

  testWidgets('a row counted in its whole measure leads with the whole count '
      'bought, as a piece row does', (tester) async {
    const whole = Measure(id: 'm-lime', label: 'lime, whole', amount: 67);
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Produce',
          items: [
            ShoppingItem(
              name: 'Lime',
              ingredientId: 'lime',
              totals: [Quantity(167.5, g)],
              measureTotal: const (amount: 2.5, measure: whole),
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Curry · cook Mon',
                  quantity: 1,
                  measure: whole,
                  cookDay: 0,
                ),
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Salad · cook Wed',
                  quantity: 1.5,
                  measure: whole,
                  cookDay: 2,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    // What you buy leads, and the need sits under it with what it weighs.
    expect(find.text('3 lime, whole'), findsOneWidget);
    expect(find.text('need 2½ · 167.5 g'), findsOneWidget);
    expect(find.text('2½ lime, whole'), findsNothing);
    await _openRow(tester, 'lime');
    expect(find.text('1 lime, whole'), findsOneWidget);
    expect(find.text('1½ lime, whole'), findsOneWidget);
  });

  testWidgets('a piece-weighted row reads its count of pieces, with the '
      'grams underneath', (tester) async {
    const whole = Measure(id: 'm-lime', label: 'lime, whole', amount: 67);
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Produce',
          items: [
            ShoppingItem(
              name: 'Lime',
              ingredientId: 'lime',
              totals: [Quantity(167.5, g)],
              pieceTotal: const (count: 2.5, approx: false),
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Curry · cook Mon',
                  quantity: 1,
                  measure: whole,
                  cookDay: 0,
                ),
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Salad · cook Wed',
                  quantity: 1.5,
                  unit: pieces,
                  cookDay: 2,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    // A count of limes — never "67 g + 1½ piece" — bought whole.
    expect(find.text('3 piece'), findsOneWidget);
    expect(find.text('need 2½ · 167.5 g'), findsOneWidget);
    expect(find.textContaining(' + '), findsNothing);
    // …and each line behind it keeps its own words.
    await _openRow(tester, 'lime');
    expect(find.text('1 lime, whole'), findsOneWidget);
    expect(find.text('1½ piece'), findsOneWidget);
  });

  group('the walk, folded', () {
    /// Flour from a recipe and a top-up, Lime rounded up, and paper towels:
    /// a row with a breakdown and a sub-line, one with a breakdown and none,
    /// and one with no breakdown at all.
    ShoppingList walk() => ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Baking',
          items: [
            ShoppingItem(
              name: 'Flour',
              ingredientId: 'flour',
              entryId: 'e-flour',
              totals: [Quantity(500, g)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Curry · cook Mon',
                  quantity: 450,
                  unit: g,
                  cookDay: 0,
                ),
                ShoppingContribution(
                  source: ContributionSource.manual,
                  label: 'manual top-up',
                  quantity: 50,
                  unit: g,
                  contributionId: 'c-flour',
                ),
              ],
            ),
          ],
        ),
        ShoppingGroup(
          label: 'Produce',
          items: [
            ShoppingItem(
              name: 'Lime',
              ingredientId: 'lime',
              entryId: 'e-lime',
              totals: [Quantity(167.5, g)],
              measureTotal: const (
                amount: 2.5,
                measure: Measure(
                  id: 'm-lime',
                  label: 'lime, whole',
                  amount: 67,
                ),
              ),
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Salad · cook Wed',
                  quantity: 2.5,
                  measure: Measure(
                    id: 'm-lime',
                    label: 'lime, whole',
                    amount: 67,
                  ),
                  cookDay: 2,
                ),
              ],
            ),
          ],
        ),
        const ShoppingGroup(
          label: 'Non-food',
          items: [ShoppingItem(name: 'Paper towels', entryId: 'e-towels')],
        ),
      ],
    );

    Future<_FakeShoppingRepo> pumpWalk(WidgetTester tester) async {
      final repo = _FakeShoppingRepo(walk(), live: true);
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(repo),
          ingredientRepositoryProvider.overrideWithValue(
            FakeIngredientRepo([]),
          ),
          measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        ]),
      );
      await tester.pump();
      return repo;
    }

    Finder chevronIn(String identity, IconData icon) => find.descendant(
      of: find.byKey(shopAmountTargetKey(identity)),
      matching: find.byIcon(icon),
    );

    testWidgets('the row tap ticks and does not open the breakdown', (
      tester,
    ) async {
      final repo = await pumpWalk(tester);
      await tester.tap(find.text('Flour'));
      await tester.pump();
      expect(repo.tickCalls, 1);
      expect(repo.lastChecked, isTrue);
      expect(find.text('Curry · cook Mon'), findsNothing);
    });

    testWidgets('the chevron points right while closed and down once open, '
        'and a row with nothing to trace has none', (tester) async {
      await pumpWalk(tester);
      expect(chevronIn('flour', FLucideIcons.chevronRight), findsOneWidget);
      expect(chevronIn('flour', FLucideIcons.chevronDown), findsNothing);
      // Paper towels has no breakdown: no target, and no arrow on its row.
      expect(find.byKey(shopAmountTargetKey('e-towels')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byIcon(FLucideIcons.chevronRight),
        ),
        findsNWidgets(2),
      );

      await _openRow(tester, 'flour');
      expect(chevronIn('flour', FLucideIcons.chevronDown), findsOneWidget);
      expect(chevronIn('flour', FLucideIcons.chevronRight), findsNothing);
      // An opened amount stays plain text: no chip round it in the walk.
      expect(
        find.descendant(
          of: find.byKey(shopAmountTargetKey('flour')),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration != null,
          ),
        ),
        findsNothing,
      );
      // A second tap folds it again.
      await _openRow(tester, 'flour');
      expect(find.text('Curry · cook Mon'), findsNothing);
    });

    testWidgets('the amount is a 44 px target, and the sub-line opens the '
        'same breakdown', (tester) async {
      await pumpWalk(tester);
      expect(
        tester.getSize(find.byKey(shopAmountTargetKey('flour'))).height,
        greaterThanOrEqualTo(44),
      );
      // Lime's sub-line is under its headline, and a tap there opens too.
      expect(find.text('3 lime, whole'), findsOneWidget);
      await tester.tap(find.text('need 2½ · 167.5 g'));
      await tester.pump();
      expect(find.text('Salad · cook Wed'), findsOneWidget);
    });

    testWidgets('an opened top-up is its own 44 px row, and it opens the '
        'edit sheet', (tester) async {
      filterForuiSemanticsAssertions();
      final repo = await pumpWalk(tester);
      await _openRow(tester, 'flour');
      final topUp = find.byKey(shopTopUpKey('c-flour'));
      expect(topUp, findsOneWidget);
      expect(tester.getSize(topUp).height, greaterThanOrEqualTo(44));
      expect(
        find.descendant(of: topUp, matching: find.byIcon(FLucideIcons.pencil)),
        findsOneWidget,
      );

      await tester.tap(topUp);
      await tester.pumpAndSettle();
      expect(find.text('Save changes'), findsOneWidget);
      expect(repo.tickCalls, 0, reason: 'editing a top-up is not a tick');
    });

    testWidgets('a ticked row folds its breakdown, and comes back closed', (
      tester,
    ) async {
      await pumpWalk(tester);
      await _openRow(tester, 'flour');
      expect(find.text('Curry · cook Mon'), findsOneWidget);

      await tester.tap(find.text('Flour'));
      await tester.pump();
      await tester.pump();
      await _openFold(tester, ShopFold.basket);
      // In the basket: no breakdown and no arrow.
      expect(find.text('Curry · cook Mon'), findsNothing);
      expect(find.byKey(shopAmountTargetKey('flour')), findsNothing);

      await tester.tap(find.text('Flour'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Curry · cook Mon'), findsNothing);
      expect(chevronIn('flour', FLucideIcons.chevronRight), findsOneWidget);
    });

    testWidgets('the folded lines read right while closed and down once '
        'open', (tester) async {
      final list = ShoppingList(
        groups: [
          ShoppingGroup(
            label: 'Produce',
            items: [
              ShoppingItem(
                name: 'Lime',
                ingredientId: 'lime',
                entryId: 'e-lime',
                checked: true,
                totals: [Quantity(100, g)],
              ),
              ShoppingItem(
                name: 'Onion',
                ingredientId: 'onion',
                entryId: 'e-onion',
                totals: [Quantity(100, g)],
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
        ]),
      );
      await tester.pump();

      Finder arrow(IconData icon) => find.descendant(
        of: find.byKey(shopFoldKey(ShopFold.basket)),
        matching: find.byIcon(icon),
      );
      final line = find.byKey(shopFoldKey(ShopFold.basket));
      expect(tester.getSize(line).height, greaterThanOrEqualTo(44));
      expect(arrow(FLucideIcons.chevronRight), findsOneWidget);
      await _openFold(tester, ShopFold.basket);
      expect(arrow(FLucideIcons.chevronDown), findsOneWidget);
      expect(find.text('Lime'), findsOneWidget);
      await _openFold(tester, ShopFold.basket);
      expect(arrow(FLucideIcons.chevronRight), findsOneWidget);
      expect(find.text('Lime'), findsNothing);
    });

    testWidgets('at a desk a row draws no arrow: the pane holds the '
        'breakdown', (tester) async {
      deskWidth(tester);
      await pumpWalk(tester);
      expect(find.byKey(shopAmountTargetKey('flour')), findsNothing);
      expect(find.text('Curry · cook Mon'), findsOneWidget);
    });
  });

  group('the basket', () {
    ShoppingItem item(String name, {bool checked = false}) => ShoppingItem(
      name: name,
      ingredientId: name.toLowerCase(),
      entryId: 'e-${name.toLowerCase()}',
      checked: checked,
      totals: [Quantity(100, g)],
    );

    testWidgets('a ticked row leaves its aisle for the basket at the bottom', (
      tester,
    ) async {
      final repo = _FakeShoppingRepo(
        ShoppingList(
          groups: [
            ShoppingGroup(
              label: 'Produce',
              items: [item('Lime', checked: true), item('Onion')],
            ),
            ShoppingGroup(label: 'Baking', items: [item('Flour')]),
          ],
        ),
      );
      await tester.pumpWidget(
        _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pump();

      // The aisles still stand, holding only what is left to grab…
      expect(find.text('BAKING'), findsOneWidget);
      // …and the ticked row is behind one counted line below every aisle,
      // folded until it is tapped.
      expect(find.text('IN THE BASKET · 1'), findsOneWidget);
      expect(find.text('Lime'), findsNothing);
      expect(find.text('PRODUCE'), findsOneWidget);
      // Opened, the row sits under its own aisle's label, kept inside the
      // basket so the row is re-found where it was found.
      await _openFold(tester, ShopFold.basket);
      final basketTop = tester.getTopLeft(find.text('IN THE BASKET · 1')).dy;
      expect(find.text('PRODUCE'), findsNWidgets(2));
      final produceInBasket = find
          .text('PRODUCE')
          .evaluate()
          .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dy)
          .where((dy) => dy > basketTop);
      expect(produceInBasket, hasLength(1));
      expect(tester.getTopLeft(find.text('Lime')).dy, greaterThan(basketTop));
      expect(tester.getTopLeft(find.text('Onion')).dy, lessThan(basketTop));
      expect(tester.getTopLeft(find.text('Flour')).dy, lessThan(basketTop));
      // The row keeps its tap: from the basket, a tap unticks it.
      await tester.tap(find.text('Lime'));
      await tester.pump();
      expect(repo.tickCalls, 1);
      expect(repo.lastChecked, isFalse);
    });

    testWidgets('an aisle whose rows are all ticked leaves the top', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(
            _FakeShoppingRepo(
              ShoppingList(
                groups: [
                  ShoppingGroup(
                    label: 'Produce',
                    items: [item('Lime', checked: true)],
                  ),
                  ShoppingGroup(label: 'Baking', items: [item('Flour')]),
                ],
              ),
            ),
          ),
        ]),
      );
      await tester.pump();

      // Produce is gone from the top and stands only inside the basket.
      expect(find.text('BAKING'), findsOneWidget);
      expect(find.text('IN THE BASKET · 1'), findsOneWidget);
      expect(find.text('PRODUCE'), findsNothing);
      await _openFold(tester, ShopFold.basket);
      final basketTop = tester.getTopLeft(find.text('IN THE BASKET · 1')).dy;
      expect(find.text('PRODUCE'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('PRODUCE')).dy,
        greaterThan(basketTop),
      );
      expect(find.textContaining('in the basket'), findsNothing);
    });

    testWidgets('every row ticked: a quiet line where the aisles were', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(
            _FakeShoppingRepo(
              ShoppingList(
                groups: [
                  ShoppingGroup(
                    label: 'Produce',
                    items: [item('Lime', checked: true)],
                  ),
                  ShoppingGroup(
                    label: 'Baking',
                    items: [item('Flour', checked: true)],
                  ),
                ],
              ),
            ),
          ),
        ]),
      );
      await tester.pump();

      expect(find.text('everything’s in the basket'), findsOneWidget);
      expect(find.text('IN THE BASKET · 2'), findsOneWidget);
      // Arriving finished is not finishing: nothing was ticked here.
      expect(find.byType(ConfettiBurst), findsNothing);
      // Both aisles stand inside the basket, and nowhere above it.
      await _openFold(tester, ShopFold.basket);
      final basketTop = tester.getTopLeft(find.text('IN THE BASKET · 2')).dy;
      expect(find.text('PRODUCE'), findsOneWidget);
      expect(find.text('BAKING'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('PRODUCE')).dy,
        greaterThan(basketTop),
      );
      expect(tester.getTopLeft(find.text('BAKING')).dy, greaterThan(basketTop));
      // Still a list with things in it — not the empty-list line.
      expect(find.textContaining('nothing to buy'), findsNothing);
      expect(find.byKey(kShopAddFieldKey), findsOneWidget);
    });
  });

  group('the last tick', () {
    ShoppingItem item(String name, {bool checked = false}) => ShoppingItem(
      name: name,
      ingredientId: name.toLowerCase(),
      entryId: 'e-${name.toLowerCase()}',
      checked: checked,
      totals: [Quantity(100, g)],
    );

    /// Lime in the basket, Onion still to grab: one tick from done.
    ShoppingList oneLeft() => ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Produce',
          items: [item('Lime', checked: true), item('Onion')],
        ),
      ],
    );

    /// Lets a burst play out and come down.
    Future<void> settleBurst(WidgetTester tester) async {
      await tester.pump(kConfettiDuration + const Duration(milliseconds: 80));
      await tester.pump();
    }

    testWidgets('this phone’s last tick bursts the confetti, with a haptic, '
        'and the write goes through as it always did', (tester) async {
      final haptics = _recordHaptics(tester);
      final repo = _FakeShoppingRepo(oneLeft(), live: true);
      await tester.pumpWidget(
        _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pump();

      await tester.tap(find.text('Onion'));
      await tester.pump();

      expect(find.byType(ConfettiBurst), findsOneWidget);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      expect(repo.tickCalls, 1);
      expect(repo.lastChecked, isTrue);
      // The tail is the shipped state arriving: the row is in the basket and
      // the quiet line stands where the aisle was, under the confetti.
      expect(find.text('everything’s in the basket'), findsOneWidget);
      expect(find.text('IN THE BASKET · 2'), findsOneWidget);

      await settleBurst(tester);
      expect(find.byType(ConfettiBurst), findsNothing);
    });

    testWidgets('a list of one item plays nothing', (tester) async {
      final haptics = _recordHaptics(tester);
      final repo = _FakeShoppingRepo(
        ShoppingList(
          groups: [
            ShoppingGroup(label: 'Produce', items: [item('Onion')]),
          ],
        ),
        live: true,
      );
      await tester.pumpWidget(
        _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pump();

      await tester.tap(find.text('Onion'));
      await tester.pump();

      expect(find.byType(ConfettiBurst), findsNothing);
      expect(haptics, isEmpty);
      expect(repo.tickCalls, 1);
    });

    testWidgets('the partner’s last tick, arriving by sync, plays nothing', (
      tester,
    ) async {
      final haptics = _recordHaptics(tester);
      final repo = _FakeShoppingRepo(oneLeft(), live: true);
      await tester.pumpWidget(
        _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pump();

      repo.emit(
        ShoppingList(
          groups: [
            ShoppingGroup(
              label: 'Produce',
              items: [
                item('Lime', checked: true),
                item('Onion', checked: true),
              ],
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('everything’s in the basket'), findsOneWidget);
      expect(find.byType(ConfettiBurst), findsNothing);
      expect(haptics, isEmpty);
    });

    testWidgets('every finish plays: re-ticking the last row bursts again, '
        'and so does a row added since', (tester) async {
      final haptics = _recordHaptics(tester);
      final repo = _FakeShoppingRepo(oneLeft(), live: true);
      await tester.pumpWidget(
        _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pump();

      await tester.tap(find.text('Onion'));
      await tester.pump();
      expect(find.byType(ConfettiBurst), findsOneWidget);
      await settleBurst(tester);

      // Untick from the basket, then tick again: the same list, finished a
      // second time, and it celebrates a second time.
      await _openFold(tester, ShopFold.basket);
      await tester.tap(find.text('Onion'));
      await tester.pump();
      expect(find.text('everything’s in the basket'), findsNothing);
      await tester.tap(find.text('Onion'));
      await tester.pump();
      expect(find.text('everything’s in the basket'), findsOneWidget);
      expect(find.byType(ConfettiBurst), findsOneWidget);
      expect(haptics, hasLength(2));
      await settleBurst(tester);

      // Flour joins (a top-up, say) and is ticked: another finish.
      repo.emit(
        repo.list.copyWith(
          groups: [
            ...repo.list.groups,
            ShoppingGroup(label: 'Baking', items: [item('Flour')]),
          ],
        ),
      );
      // Two frames: the stream's event lands in one, the rows rebuild in the
      // next.
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Flour'));
      await tester.pump();
      expect(find.byType(ConfettiBurst), findsOneWidget);
      expect(haptics, hasLength(3));
      await settleBurst(tester);
    });

    testWidgets('with animations off the haptic still fires and nothing is '
        'drawn', (tester) async {
      final haptics = _recordHaptics(tester);
      final repo = _FakeShoppingRepo(oneLeft(), live: true);
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(repo),
        ], disableAnimations: true),
      );
      await tester.pump();

      await tester.tap(find.text('Onion'));
      await tester.pump();

      expect(find.byType(ConfettiBurst), findsNothing);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      expect(repo.tickCalls, 1);
      expect(find.text('everything’s in the basket'), findsOneWidget);
    });
  });

  testWidgets('a nested contribution names both levels', (tester) async {
    // The provenance segment the domain builds for a component session: the
    // sub-recipe's own line, then the plan it is cooked for.
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Olive oil',
              ingredientId: 'oil',
              totals: [Quantity(60, ml)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Sausage Sliders · cook Sat',
                  quantity: 30,
                  unit: ml,
                  cookDay: 5,
                ),
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Romesco Aioli · for Sliders · cook Sat',
                  quantity: 30,
                  unit: ml,
                  cookDay: 5,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    await _openRow(tester, 'oil');
    expect(find.text('Sausage Sliders · cook Sat'), findsOneWidget);
    expect(find.text('Romesco Aioli · for Sliders · cook Sat'), findsOneWidget);
    // Summed once, bought once.
    expect(find.text('60 ml'), findsOneWidget);
  });

  testWidgets('a tick that does not land says so, in the item’s own name', (
    tester,
  ) async {
    const list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Non-food',
          items: [ShoppingItem(name: 'Paper towels', entryId: 'e1')],
        ),
      ],
    );
    final repo = _FakeShoppingRepo(list, tickThrows: true);

    await tester.pumpWidget(
      _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
    );
    await tester.pump();

    await tester.tap(find.text('Paper towels'));
    await tester.pumpAndSettle();

    expect(repo.tickCalls, 1);
    expect(find.text('Couldn’t tick Paper towels.'), findsOneWidget);
  });

  testWidgets('an unresolved component makes the list’s silence '
      'legible', (tester) async {
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Olive oil',
              ingredientId: 'oil',
              totals: [Quantity(30, ml)],
            ),
          ],
        ),
      ],
      unresolvedComponents: const [
        (recipeId: 'sliders', recipeTitle: 'Sausage Sliders', count: 1),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    // Folded behind one amber line with its flag: a defect somebody can fix.
    expect(find.text('1 note from the plan'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(shopFoldKey(ShopFold.notes)),
        matching: find.byIcon(FLucideIcons.flag),
      ),
      findsOneWidget,
    );
    expect(find.text('SAUSAGE SLIDERS'), findsNothing);
    await _openFold(tester, ShopFold.notes);
    expect(find.text('SAUSAGE SLIDERS'), findsOneWidget);
    expect(find.text('1 component unresolved — see Cook'), findsOneWidget);
  });

  testWidgets('a line at a RETIRED ingredient is named at the bottom, with '
      'the pick it needs — never bought from the dead row', (tester) async {
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Olive oil',
              ingredientId: 'oil',
              totals: [Quantity(30, ml)],
            ),
          ],
        ),
      ],
      retiredIngredients: const [
        (
          heading: 'Curry',
          ingredientName: 'Sauerkraut',
          site: RetiredIngredientSite.recipeLine,
        ),
        (
          heading: 'Snack · Tue',
          ingredientName: 'Protein bar',
          site: RetiredIngredientSite.planEntry,
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    // Neither is an aisle row; both are named behind the notes line, and
    // each says where the pick is — the recipe for a recipe line, the plan
    // for a bare-ingredient meal.
    expect(find.text('2 notes from the plan'), findsOneWidget);
    await _openFold(tester, ShopFold.notes);
    expect(find.text('CURRY'), findsOneWidget);
    expect(
      find.text('Sauerkraut · ingredient removed · pick again in the recipe'),
      findsOneWidget,
    );
    expect(find.text('SNACK · TUE'), findsOneWidget);
    expect(
      find.text('Protein bar · ingredient removed · pick again in the plan'),
      findsOneWidget,
    );
    // Amber, like the unresolved echo: a broken line is a defect somebody can
    // fix, not a rule somebody chose.
    expect(
      find.descendant(
        of: find.byType(RetiredIngredientEcho),
        matching: find.byIcon(FLucideIcons.flag),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('an optional line that left the list is named by its recipe, '
      'muted — a rule, not a defect', (tester) async {
    final list = ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Olive oil',
              ingredientId: 'oil',
              totals: [Quantity(30, ml)],
            ),
          ],
        ),
      ],
      optionalLines: const [
        (
          recipeId: 'curry',
          recipeTitle: 'Weeknight Chicken Curry',
          names: ['lime', 'coriander'],
          lineIds: ['li-lime', 'li-coriander'],
          reason: LineDropReason.optional,
        ),
      ],
    );

    await tester.pumpWidget(
      _host([
        shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      ]),
    );
    await tester.pump();

    // Every note a choice, so the line reads muted, with no flag.
    expect(find.text('1 note from the plan'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(shopFoldKey(ShopFold.notes)),
        matching: find.byIcon(FLucideIcons.flag),
      ),
      findsNothing,
    );
    final line = tester.widget<Text>(find.text('1 note from the plan'));
    expect(line.style?.color, AnsiColors.muted);
    await _openFold(tester, ShopFold.notes);
    expect(find.text('WEEKNIGHT CHICKEN CURRY'), findsOneWidget);
    expect(
      find.textContaining('2 optional lines not listed — lime, coriander'),
      findsOneWidget,
    );
    // Muted, not amber: the unresolved echo's flag icon is not on this row.
    expect(
      find.descendant(
        of: find.byType(OptionalLinesEcho),
        matching: find.byIcon(FLucideIcons.flag),
      ),
      findsNothing,
    );
  });

  group('the echo row is a door', () {
    /// The names are kept short on purpose: the test font is fixed-width, and
    /// a longer sentence ellipsizes before the name a tap is aimed at.
    ShoppingList listWith(
      LineDropReason reason, {
      List<String> names = const ['lime'],
      List<String> lineIds = const ['li-lime'],
    }) => ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Olive oil',
              ingredientId: 'oil',
              totals: [Quantity(30, ml)],
            ),
          ],
        ),
      ],
      optionalLines: [
        (
          recipeId: 'curry',
          recipeTitle: 'Weeknight Chicken Curry',
          names: names,
          lineIds: lineIds,
          reason: reason,
        ),
      ],
    );

    testWidgets('tapping an optional name ticks that line in for the '
        "shop's week", (tester) async {
      final variants = FakeWeekVariantRepository();
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(
            _FakeShoppingRepo(listWith(LineDropReason.optional)),
          ),
          weekVariantRepositoryProvider.overrideWithValue(variants),
        ]),
      );
      await tester.pump();
      await _openFold(tester, ShopFold.notes);

      await tester.tapOnText(find.textRange.ofSubstring('lime'));
      await tester.pump();

      expect(variants.ticked, hasLength(1));
      final write = variants.ticked.single;
      expect(write.recipeId, 'curry');
      expect(write.lineId, 'li-lime');
      expect(write.included, isTrue);
      expect(write.weekStart, WeekShape.monday.weekStartOf(DateTime.now()));
    });

    testWidgets('a line the WEEK left out is not a door — that change is '
        'undone where it was made', (tester) async {
      final variants = FakeWeekVariantRepository();
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(
            _FakeShoppingRepo(
              listWith(
                LineDropReason.thisWeek,
                names: const ['wine'],
                lineIds: const ['li-wine'],
              ),
            ),
          ),
          weekVariantRepositoryProvider.overrideWithValue(variants),
        ]),
      );
      await tester.pump();
      await _openFold(tester, ShopFold.notes);

      await tester.tapOnText(find.textRange.ofSubstring('wine'));
      await tester.pump();

      expect(variants.ticked, isEmpty);
    });
  });

  group('at a desk', () {
    /// Flour (two sources and a top-up), Halloumi, and one row already in the
    /// basket — enough to ask where each row's breakdown is drawn.
    ShoppingList listWithBasket() => ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Baking',
          items: [
            ShoppingItem(
              name: 'Flour',
              ingredientId: 'flour',
              totals: [Quantity(500, g)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Curry · cook Mon',
                  quantity: 300,
                  unit: g,
                  cookDay: 0,
                ),
                ShoppingContribution(
                  source: ContributionSource.manual,
                  label: 'manual top-up',
                  quantity: 50,
                  unit: g,
                  contributionId: 'c1',
                ),
              ],
            ),
          ],
        ),
        ShoppingGroup(
          label: 'Dairy',
          items: [
            ShoppingItem(
              name: 'Halloumi',
              entryId: 'e-halloumi',
              ingredientId: 'halloumi',
              totals: [Quantity(250, g)],
              contributions: const [
                ShoppingContribution(
                  source: ContributionSource.cookSession,
                  label: 'Halloumi Salad · cook Wed',
                  quantity: 250,
                  unit: g,
                  cookDay: 2,
                ),
              ],
            ),
          ],
        ),
        const ShoppingGroup(
          label: 'Pantry',
          items: [
            ShoppingItem(
              name: 'Coconut milk, canned',
              entryId: 'e-coconut',
              ingredientId: 'coconut',
              checked: true,
            ),
          ],
        ),
      ],
    );

    testWidgets('the breakdown moves into a pane beside the walk, which still '
        'holds its aisles and its one basket section', (tester) async {
      deskWidth(tester);
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(
            _FakeShoppingRepo(listWithBasket()),
          ),
        ]),
      );
      await tester.pump();

      // The pane reads the first row of the walk until a name says otherwise.
      expect(find.text('WHERE IT CAME FROM'), findsOneWidget);
      expect(find.byKey(kShopReadingRowKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(kShopReadingRowKey),
          matching: find.text('Flour'),
        ),
        findsOneWidget,
      );
      // Its whole breakdown is in the pane — every source, and the top-up that
      // is still editable there — and drawn exactly once, because no row under
      // 1024's rule is drawing one of its own.
      expect(find.text('Curry · cook Mon'), findsOneWidget);
      expect(find.text('manual top-up'), findsOneWidget);
      // A row the pane is NOT reading says nothing about where it came from.
      expect(find.text('Halloumi Salad · cook Wed'), findsNothing);
      // The pane names where the row is walked to; the walk keeps its aisles
      // and its one basket section, exactly as a phone draws them.
      expect(find.text('BAKING'), findsWidgets);
      expect(find.text('DAIRY'), findsOneWidget);
      expect(find.text('In the basket · 1'.toUpperCase()), findsOneWidget);
      // …and a ticked row is still in that section, not back in its aisle —
      // and reading one says where it is in the words the list uses.
      await _openFold(tester, ShopFold.basket);
      expect(find.text('Coconut milk, canned'), findsOneWidget);
      await tester.tap(find.text('Coconut milk, canned'));
      await tester.pump();
      expect(find.text('PANTRY · IN THE BASKET'), findsOneWidget);
      expect(
        find.text('nothing to trace — an item you added by hand'),
        findsOneWidget,
      );
    });

    testWidgets('the check box ticks, and ticking says nothing about which '
        'row the pane is reading', (tester) async {
      deskWidth(tester);
      final repo = _FakeShoppingRepo(listWithBasket());
      await tester.pumpWidget(
        _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pump();

      // The pane is on Flour, the first row of the walk; Halloumi's box is a
      // target of its own, 31 x 44, big enough for the thumb of a shopper.
      final box = find.byKey(shopTickTargetKey('halloumi'));
      expect(tester.getSize(box), const Size(31, 44));
      await tester.tap(box);
      await tester.pump();

      expect(repo.tickCalls, 1);
      expect(repo.lastChecked, isTrue);
      expect(
        find.descendant(
          of: find.byKey(kShopReadingRowKey),
          matching: find.text('Flour'),
        ),
        findsOneWidget,
        reason: 'grabbing a row is not reading it — the pane has not moved',
      );
    });

    testWidgets('a tap on the name, or on the amount, points the pane at that '
        'row and does NOT tick it', (tester) async {
      deskWidth(tester);
      final repo = _FakeShoppingRepo(listWithBasket());
      await tester.pumpWidget(
        _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pump();

      await tester.tap(find.text('Halloumi'));
      await tester.pump();

      expect(find.text('Halloumi Salad · cook Wed'), findsOneWidget);
      expect(find.text('Curry · cook Mon'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(kShopReadingRowKey),
          matching: find.text('Halloumi'),
        ),
        findsOneWidget,
      );

      // The amount is the rest of the row, and the rest of the row selects
      // too: only the box ticks. Flour's total, to move the pane back.
      await tester.tap(find.text('500 g'));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(kShopReadingRowKey),
          matching: find.text('Flour'),
        ),
        findsOneWidget,
      );
      expect(
        repo.tickCalls,
        0,
        reason: 'reading a row is not grabbing it — only the box ticks',
      );
    });

    testWidgets('the row the pane is on keeps it when it is ticked — it walks '
        'to the basket section, it does not leave the list', (tester) async {
      deskWidth(tester);
      final repo = _FakeShoppingRepo(listWithBasket(), live: true);
      await tester.pumpWidget(
        _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pump();

      // Read Halloumi, then tick it: the derivation moves it under IN THE
      // BASKET, and the pane stays on the row the shopper was reading.
      await tester.tap(find.text('Halloumi'));
      await tester.pump();
      await tester.tap(find.byKey(shopTickTargetKey('halloumi')));
      await tester.pump();

      expect(find.text('In the basket · 2'.toUpperCase()), findsOneWidget);
      expect(find.text('DAIRY · IN THE BASKET'), findsOneWidget);
      await _openFold(tester, ShopFold.basket);
      expect(
        find.descendant(
          of: find.byKey(kShopReadingRowKey),
          matching: find.text('Halloumi'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('below 1024 the phone rule is untouched: the whole row ticks, '
        'and there is no pane to point at', (tester) async {
      final repo = _FakeShoppingRepo(listWithBasket());
      await tester.pumpWidget(
        _host([shoppingRepositoryProvider.overrideWithValue(repo)]),
      );
      await tester.pump();

      expect(find.byKey(kShopReadingRowKey), findsNothing);
      expect(find.byKey(shopTickTargetKey('halloumi')), findsNothing);

      await tester.tap(find.text('Halloumi'));
      await tester.pump();

      expect(repo.tickCalls, 1);
      expect(repo.lastChecked, isTrue);
    });
  });

  group('the ledger door', () {
    ShoppingList aisle() => ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Produce',
          items: [
            ShoppingItem(
              name: 'Onion',
              ingredientId: 'onion',
              entryId: 'e-onion',
              totals: [Quantity(100, g)],
            ),
          ],
        ),
      ],
    );

    // No receipt is kept in any of these: the door does not wait for one.
    List<Override> doorOverrides() => [
      shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(aisle())),
    ];

    /// Where the switcher sits, and where the header it sits in sits.
    (double switcher, double header) centres(WidgetTester tester) => (
      tester.getCenter(find.byType(WeekSwitcher)).dx,
      tester.getCenter(find.byWidgetPredicate((w) => w is FHeader).first).dx,
    );

    testWidgets('with no receipt kept, the header still opens the ledger', (
      tester,
    ) async {
      await tester.pumpWidget(_routerHost(doorOverrides()));
      await tester.pump();

      expect(find.byIcon(FLucideIcons.receipt), findsOneWidget);
      expect(find.bySemanticsLabel('Receipts'), findsOneWidget);

      await tester.tap(find.byIcon(FLucideIcons.receipt));
      await tester.pumpAndSettle();
      expect(find.text('the ledger'), findsOneWidget);
    });

    testWidgets('the switcher stays centred with the action beside it', (
      tester,
    ) async {
      await tester.pumpWidget(_routerHost(doorOverrides()));
      await tester.pump();
      final (switcher, header) = centres(tester);

      // A nested header centres its title in the WHOLE width and moves it
      // only when the two would collide…
      expect(switcher, closeTo(header, 0.5));
      // …and the action is to the right of it, where a suffix belongs.
      expect(
        tester.getCenter(find.byIcon(FLucideIcons.receipt)).dx,
        greaterThan(switcher),
      );
    });

    testWidgets('at a desk the door is in the same place, still centred', (
      tester,
    ) async {
      deskWidth(tester);
      await tester.pumpWidget(_routerHost(doorOverrides()));
      await tester.pump();

      expect(find.byIcon(FLucideIcons.receipt), findsOneWidget);
      final (switcher, header) = centres(tester);
      expect(switcher, closeTo(header, 0.5));
    });

    testWidgets('the foot holds no scan door and no add door', (tester) async {
      await tester.pumpWidget(_routerHost(doorOverrides()));
      await tester.pump();

      expect(
        find.text('scan a receipt'),
        findsNothing,
        reason: 'the scan lives on the ledger, with what it makes',
      );
      expect(find.byIcon(FLucideIcons.camera), findsNothing);
      expect(find.textContaining('add item or top up'), findsNothing);
      expect(
        find.byType(DashedBorderBox),
        findsNothing,
        reason: 'the walk ends on its last line, with no door under it',
      );
    });
  });

  group('what the trip costs', () {
    /// Two rows, one of them unpriced — the ordinary walk. `everythingPriced`
    /// drops the unpriced one, which is the only state in which the trip
    /// figure is an estimate of the whole walk rather than a floor.
    ShoppingList costList({
      bool checked = false,
      bool everythingPriced = false,
    }) => ShoppingList(
      groups: [
        ShoppingGroup(
          label: 'Produce',
          items: [
            ShoppingItem(
              name: 'Yellow onion',
              ingredientId: 'i1',
              entryId: 'e1',
              checked: checked,
              totals: [Quantity(550, g)],
              pieceTotal: const (count: 5, approx: true),
            ),
            if (!everythingPriced)
              ShoppingItem(
                name: 'Charred broccoli',
                ingredientId: 'i2',
                entryId: 'e2',
                totals: [Quantity(350, g)],
                pieceTotal: const (count: 1, approx: true),
              ),
          ],
        ),
      ],
    );

    List<Override> costOverrides(ShoppingList list) => [
      shoppingRepositoryProvider.overrideWithValue(_FakeShoppingRepo(list)),
      shopPricingProvider.overrideWithValue({
        'i1': (
          row: (
            basis: MacrosBasis.perG,
            densityGPerMl: null,
            pieceBasisAmount: null,
          ),
          price: ShopPrice(
            PriceObservation(
              lineId: 'rl-1',
              receiptId: 'r-1',
              cents: 440,
              packBasisAmount: 1000,
              basis: MacrosBasis.perG,
              store: "TJ's",
              purchasedAt: DateTime.utc(2026, 9, 3),
            ),
            ShopPriceChoice.cheapestSeen,
          ),
        ),
      }),
    ];

    testWidgets('the estimate rides the sync line and each row its own', (
      tester,
    ) async {
      await tester.pumpWidget(_host(costOverrides(costList())));
      await tester.pump();

      // The broccoli has no price, so it adds nothing to the figure — and
      // the figure says as much rather than reading as the whole walk
      // (owner).
      expect(
        find.text(r'at least $2 at the cheapest · 1 row unpriced'),
        findsOneWidget,
      );
      expect(find.text(r"550 g · $2.42 at TJ's"), findsOneWidget);
      // A row with no price says so rather than leaving a gap.
      expect(find.text('350 g · no price yet'), findsOneWidget);
    });

    testWidgets('a walk where everything is priced is an estimate, as it '
        'always was', (tester) async {
      await tester.pumpWidget(
        _host(costOverrides(costList(everythingPriced: true))),
      );
      await tester.pump();

      expect(find.text(r'≈ $2 at the cheapest'), findsOneWidget);
    });

    testWidgets('a ticked row carries no estimate — it is in the basket', (
      tester,
    ) async {
      await tester.pumpWidget(_host(costOverrides(costList(checked: true))));
      await tester.pump();

      expect(find.text(r"550 g · $2.42 at TJ's"), findsNothing);
      // And it is out of the trip figure, which answers what is LEFT.
      expect(find.textContaining('at the cheapest'), findsNothing);
    });
  });

  group('what is already at home', () {
    const onionMedium = Measure(
      id: 'm-onion',
      label: 'onion, medium',
      amount: 110,
    );

    IngredientMetaInput meta(
      String name,
      String category, {
      Unit unit = g,
      List<Measure> measures = const [],
    }) => (
      name: name,
      category: category,
      densityGPerMl: null,
      defaultUnit: unit,
      measures: measures,
      pieceBasisAmount: null,
      basis: MacrosBasis.perG,
    );

    CookContributionInput cook(
      String id,
      double qty,
      Unit unit, {
      Measure? measure,
      String recipe = 'Curry',
    }) => (
      ingredientId: id,
      quantity: qty,
      unit: unit,
      rawUnit: unit.id,
      measure: measure,
      recipeTitle: recipe,
      cookDay: 0,
      batched: false,
      forParents: const [],
      weekNote: null,
    );

    ShoppingEntryInput entry(String id, String ingredientId) => (
      id: id,
      ingredientId: ingredientId,
      freeText: null,
      category: null,
      checked: false,
      unit: null,
      createdAt: null,
    );

    AtHomeInput home(String entryId, double qty, Unit unit, {Measure? m}) => (
      entryId: entryId,
      quantity: qty,
      unit: unit,
      rawUnit: unit.id,
      measureId: m?.id,
      measure: m,
      updatedAt: null,
    );

    /// Flour 500 g, onions 5 medium, butter in two units (no density), and
    /// paper towels; [atHome] says what is already in the cupboard.
    ShoppingList walk({Map<String, AtHomeInput> atHome = const {}}) =>
        buildShoppingList(
          cook: [
            cook('flour', 300, g),
            cook('flour', 200, g, recipe: 'Cookies'),
            cook('onion', 5, pieces, measure: onionMedium),
            cook('butter', 100, g),
            cook('butter', 2, tbsp),
          ],
          entries: [
            entry('e-flour', 'flour'),
            entry('e-onion', 'onion'),
            (
              id: 'e-towels',
              ingredientId: null,
              freeText: 'Paper towels',
              category: null,
              checked: false,
              unit: null,
              createdAt: null,
            ),
          ],
          manual: const {},
          meta: {
            'flour': meta('Flour', 'baking'),
            'onion': meta(
              'Yellow onion',
              'produce',
              unit: pieces,
              measures: const [onionMedium],
            ),
            'butter': meta('Butter', 'dairy'),
          },
          weekdayShort: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
          atHome: atHome,
        );

    Future<_FakeShoppingRepo> pumpWalk(
      WidgetTester tester, {
      Map<String, AtHomeInput> atHome = const {},
    }) async {
      final repo = _FakeShoppingRepo(walk(atHome: atHome));
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(repo),
          // The amount editor reads the row and its measures.
          ingredientRepositoryProvider.overrideWithValue(
            FakeIngredientRepo([]),
          ),
          measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        ]),
      );
      await tester.pump();
      return repo;
    }

    /// The toggle's segments animate their indicator; let it land.
    Future<void> tapSegment(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> enterThePass(WidgetTester tester) =>
        tapSegment(tester, 'At home?');

    bool checking(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(ShoppingView)),
    ).read(shopCheckingProvider);

    testWidgets('the toggle opens the pass: houses and amounts, no provenance, '
        'no free text, and To buy leaves it', (tester) async {
      await pumpWalk(tester);
      expect(find.byType(ShopToggle), findsOneWidget);
      // The foot holds no door into it any more, and no band says it is on.
      expect(find.text('check what’s at home'), findsNothing);
      expect(find.text('What’s already at home?'), findsNothing);
      await _openRow(tester, 'flour');
      expect(find.text('Curry'), findsWidgets);

      await enterThePass(tester);
      expect(checking(tester), isTrue);
      expect(find.text('500 g'), findsOneWidget);
      expect(find.text('5 onion, medium'), findsOneWidget);
      // The question is only "do we have it": no breakdown, no non-food.
      expect(find.text('Curry'), findsNothing);
      expect(find.text('Paper towels'), findsNothing);
      // The toggle is the only control for the mode: no band, no Done.
      expect(find.text('Done'), findsNothing);

      await tapSegment(tester, 'To buy');
      expect(checking(tester), isFalse);
      expect(find.text('Paper towels'), findsOneWidget);
    });

    testWidgets('a list of free text alone draws no toggle', (tester) async {
      await tester.pumpWidget(
        _host([
          shoppingRepositoryProvider.overrideWithValue(
            _FakeShoppingRepo(
              const ShoppingList(
                groups: [
                  ShoppingGroup(
                    label: 'Non-food',
                    items: [ShoppingItem(name: 'Paper towels', entryId: 'e1')],
                  ),
                ],
              ),
            ),
          ),
        ]),
      );
      await tester.pump();
      expect(find.text('At home?'), findsNothing);
    });

    testWidgets('leaving the tab sets the toggle back to To buy and folds '
        'what was opened', (tester) async {
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        _tabHost([
          shoppingRepositoryProvider.overrideWithValue(
            _FakeShoppingRepo(walk()),
          ),
          ingredientRepositoryProvider.overrideWithValue(
            FakeIngredientRepo([]),
          ),
          measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        ], visible),
      );
      await tester.pump();
      await _openRow(tester, 'flour');
      expect(find.text('Cookies'), findsOneWidget);
      await enterThePass(tester);
      expect(checking(tester), isTrue);

      visible.value = false;
      await tester.pump();
      await tester.pump();
      visible.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(checking(tester), isFalse);
      expect(find.text('Paper towels'), findsOneWidget);
      // The breakdown opened on the last visit is folded again.
      expect(find.text('Cookies'), findsNothing);
    });

    testWidgets('a tap on the row says all of it — the need as it stands, '
        'in the measure it is counted in', (tester) async {
      final repo = await pumpWalk(tester);
      await enterThePass(tester);

      await tester.tap(find.byKey(shopHomeRowKey('onion')));
      await tester.pump();
      expect(repo.atHomeSet.single, (
        ingredientId: 'onion',
        quantity: 5.0,
        unit: pieces,
        measureId: 'm-onion',
      ));

      await tester.tap(find.byKey(shopHomeRowKey('flour')));
      await tester.pump();
      expect(repo.atHomeSet.last.quantity, 500);
      expect(repo.atHomeSet.last.unit, g);
    });

    testWidgets(
      'a row already answered reads its amount, and a tap clears it',
      (tester) async {
        final repo = await pumpWalk(
          tester,
          atHome: {
            'e-flour': home('e-flour', 200, g),
            'e-onion': home('e-onion', 5, pieces, m: onionMedium),
          },
        );
        await enterThePass(tester);
        expect(find.text('200 of 500 g'), findsOneWidget);
        expect(find.text('all 5'), findsOneWidget);

        await tester.tap(find.byKey(shopHomeRowKey('flour')));
        await tester.pump();
        expect(repo.atHomeCleared, ['flour']);
        expect(repo.atHomeSet, isEmpty);
      },
    );

    testWidgets('a row in two units says why it cannot take an amount, and a '
        'tap does nothing', (tester) async {
      final repo = await pumpWalk(tester);
      await enterThePass(tester);
      expect(find.text('two units — no density'), findsOneWidget);
      await tester.tap(find.byKey(shopHomeRowKey('butter')));
      await tester.pump();
      expect(repo.atHomeSet, isEmpty);
    });

    testWidgets('after: a part-have says so first on its sub-line, and a '
        'whole-have sits in At home, under the basket', (tester) async {
      final repo = await pumpWalk(
        tester,
        atHome: {
          'e-flour': home('e-flour', 200, g),
          'e-onion': home('e-onion', 5, pieces, m: onionMedium),
        },
      );
      expect(find.text('300 g'), findsWidgets);
      expect(find.textContaining('200 g at home'), findsOneWidget);
      // The provenance, opened, still says what the week asked for.
      await _openRow(tester, 'flour');
      expect(find.text('Cookies'), findsOneWidget);
      // The whole-have is behind one counted line until it is opened.
      expect(find.text('AT HOME · 1'), findsOneWidget);
      expect(find.byKey(shopAtHomeRowKey('onion')), findsNothing);
      await _openFold(tester, ShopFold.atHome);
      expect(find.byKey(shopAtHomeRowKey('onion')), findsOneWidget);
      // Never struck through: it was not bought.
      final name = tester.widget<Text>(
        find.descendant(
          of: find.byKey(shopAtHomeRowKey('onion')),
          matching: find.text('Yellow onion'),
        ),
      );
      expect(name.style?.decoration, isNot(TextDecoration.lineThrough));

      // A tap puts it back in its aisle.
      await tester.tap(find.byKey(shopAtHomeRowKey('onion')));
      await tester.pump();
      expect(repo.atHomeCleared, ['onion']);
    });

    testWidgets(
      'everything at home and nothing ticked closes on its own line',
      (tester) async {
        final list = buildShoppingList(
          cook: [cook('flour', 500, g)],
          entries: [entry('e-flour', 'flour')],
          manual: const {},
          meta: {'flour': meta('Flour', 'baking')},
          weekdayShort: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
          atHome: {'e-flour': home('e-flour', 500, g)},
        );
        await tester.pumpWidget(
          _host([
            shoppingRepositoryProvider.overrideWithValue(
              _FakeShoppingRepo(list),
            ),
          ]),
        );
        await tester.pump();
        expect(find.text('everything’s at home'), findsOneWidget);
        expect(find.text('everything’s in the basket'), findsNothing);
      },
    );

    testWidgets('wide: the house says all of it, and the pane holds the '
        'amount for the row the list points at', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      final repo = await pumpWalk(tester);
      await enterThePass(tester);

      // The pane asks how much, in place of where it came from.
      expect(find.text('WHERE IT CAME FROM'), findsNothing);
      expect(find.text('this week needs'), findsOneWidget);

      await tester.tap(find.byKey(shopHomeTargetKey('flour')));
      await tester.pump();
      expect(repo.atHomeSet.single.ingredientId, 'flour');
    });

    testWidgets('wide: the pane’s × ends the pass, and the toggle reads To '
        'buy again', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await pumpWalk(tester);
      await enterThePass(tester);
      expect(checking(tester), isTrue);
      // The toggle sits over the walk's own column, not the pane.
      expect(
        tester.getCenter(find.byType(ShopToggle)).dx,
        lessThan(tester.getTopLeft(find.text('this week needs')).dx),
      );

      await tester.tap(find.byIcon(FLucideIcons.x));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(checking(tester), isFalse);
      expect(find.text('WHERE IT CAME FROM'), findsOneWidget);
    });
  });
}
