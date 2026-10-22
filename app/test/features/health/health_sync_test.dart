/// One pass of keeping Health Connect in step, against a fake phone.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/health/domain/health_meal.dart';
import 'package:ansi/features/health/presentation/health_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_health.dart';

HealthMeal _meal(String id, {double kcal = 400}) => HealthMeal(
  id: id,
  name: 'Curry',
  day: DateTime(2026, 10, 21),
  at: DateTime(2026, 10, 21, 19),
  mealType: HealthMealType.dinner,
  macros: Macros(kcal: kcal, protein: 30, carb: 40, fat: 10),
);

void main() {
  final window = DateTime.utc(2026, 10, 12);

  test('writes, takes back, and remembers what is now there', () async {
    final gateway = FakeHealthGateway();
    final log = FakeHealthSendLog()..log = {'gone': _meal('gone').contentKey};
    await reconcileHealth(
      [_meal('a')],
      windowStart: window,
      gateway: gateway,
      log: log,
    );
    expect(gateway.deleted, ['gone']);
    expect(gateway.written.map((m) => m.id), ['a']);
    expect(log.log.keys, ['a']);
  });

  test('a second pass with nothing changed writes nothing', () async {
    final gateway = FakeHealthGateway();
    final log = FakeHealthSendLog();
    await reconcileHealth(
      [_meal('a')],
      windowStart: window,
      gateway: gateway,
      log: log,
    );
    gateway.written.clear();
    await reconcileHealth(
      [_meal('a')],
      windowStart: window,
      gateway: gateway,
      log: log,
    );
    expect(gateway.written, isEmpty);
  });

  test('without permission it touches nothing, and forgets nothing', () async {
    final gateway = FakeHealthGateway()..granted = false;
    final log = FakeHealthSendLog()..log = {'x': _meal('x').contentKey};
    await reconcileHealth(
      const [],
      windowStart: window,
      gateway: gateway,
      log: log,
    );
    expect(gateway.deleted, isEmpty);
    expect(log.log.keys, ['x']);
  });
}
