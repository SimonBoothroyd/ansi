import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/cook_plan/data/cook_plan_providers.dart';
import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:ansi/features/cook_plan/presentation/leftovers_view_models.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_leftover_repository.dart';

/// Monday 9 November 2026, in a week from Monday.
final _monday = DateTime(2026, 11, 9, 9);

DateTime _nov(int day) => DateTime(2026, 11, day);

/// Beef Ragù keeps 3 days and freezes for 60.
Leftover _pot(
  String id, {
  required DateTime since,
  required DateTime plannedIn,
}) => Leftover(
  id: id,
  place: LeftoverPlace.fridge,
  recipeId: 'ragu',
  title: 'Beef Ragù',
  since: since,
  goodUntil: since.add(const Duration(days: 3)),
  box: 0,
  freezable: true,
  freezerUntil: since.add(const Duration(days: 60)),
  cooked: false,
  plannedIn: plannedIn,
);

Future<List<Leftover>> _offersOn(
  DateTime day, {
  List<Leftover> rows = const [],
  List<Leftover> pots = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => _monday),
      weekShapeProvider.overrideWithValue(WeekShape.monday),
      leftoverRepositoryProvider.overrideWithValue(
        FakeLeftoverRepository(rows, const {}, pots),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.listen(leftoverShelvesProvider, (_, _) {});
  await Future<void>.delayed(Duration.zero);
  return container.read(leftoversGoodOnProvider(day));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('leftoversGoodOn', () {
    // This week's Saturday ragù, planned and not cooked yet.
    final saturday = _pot('sat', since: _nov(14), plannedIn: _nov(9));

    test('offers a pot not born yet to a later week, under Freezer past its '
        'fridge date', () async {
      final offers = await _offersOn(_nov(19), pots: [saturday]);
      expect(offers.single.id, 'sat');
      expect(offers.single.place, LeftoverPlace.freezer);
      expect(offers.single.freezeBy, _nov(17));
    });

    test('never offers a pot not born yet to its own week: a meal there '
        'already shares it when it fits', () async {
      expect(await _offersOn(_nov(15), pots: [saturday]), isEmpty);
    });

    test('offers a cooking nobody ticked yet once, whatever shelf it reads '
        'on, even in its own week', () async {
      final fridge = Leftover(
        id: 'c',
        place: LeftoverPlace.fridge,
        recipeId: 'ragu',
        title: 'Beef Ragù',
        since: _nov(14),
        goodUntil: _nov(17),
        box: 2,
        planned: 2,
        freezable: true,
        cooked: false,
      );
      final freezer = Leftover(
        id: 'c',
        place: LeftoverPlace.freezer,
        recipeId: 'ragu',
        title: 'Beef Ragù',
        since: _nov(14),
        goodUntil: null,
        box: 1,
        freezable: true,
        cooked: false,
      );
      final offers = await _offersOn(_nov(15), rows: [fridge, freezer]);
      expect(offers.map((o) => (o.id, o.place)), [('c', LeftoverPlace.fridge)]);
    });

    test('a cooked row with nothing free is not offered', () async {
      final spoken = Leftover(
        id: 'k',
        place: LeftoverPlace.fridge,
        recipeId: 'ragu',
        title: 'Beef Ragù',
        since: _nov(8),
        goodUntil: _nov(11),
        box: 2,
        planned: 2,
      );
      expect(await _offersOn(_nov(10), rows: [spoken]), isEmpty);
    });
  });
}
