import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/presentation/shopping_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  ShoppingItem item(String name, {bool checked = false}) =>
      ShoppingItem(name: name, ingredientId: name, checked: checked);

  final week = DateTime(2026, 9, 14);
  final oneLeft = ShoppingList(
    groups: [
      ShoppingGroup(label: 'Produce', items: [item('Lime', checked: true)]),
      ShoppingGroup(label: 'Baking', items: [item('Flour')]),
    ],
  );

  group('LastTickCelebration.arm', () {
    late ProviderContainer container;
    late LastTickCelebration notifier;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
      notifier = container.read(lastTickCelebrationProvider.notifier);
    });

    test('plays for the tick that finishes the list, once', () {
      expect(notifier.arm(week, oneLeft, item('Flour')), isTrue);
      expect(notifier.arm(week, oneLeft, item('Flour')), isFalse);
    });

    test('a tick that does not finish the list never arms', () {
      final twoLeft = oneLeft.copyWith(
        groups: [
          ...oneLeft.groups,
          ShoppingGroup(label: 'Dairy', items: [item('Milk')]),
        ],
      );
      expect(notifier.arm(week, twoLeft, item('Flour')), isFalse);
      // …and refusing does not spend the list's one moment.
      expect(notifier.arm(week, oneLeft, item('Flour')), isTrue);
    });

    test('the same items next week are a new trip', () {
      expect(notifier.arm(week, oneLeft, item('Flour')), isTrue);
      final nextWeek = week.add(const Duration(days: 7));
      expect(notifier.arm(nextWeek, oneLeft, item('Flour')), isTrue);
    });

    test('a row added since is a new list', () {
      expect(notifier.arm(week, oneLeft, item('Flour')), isTrue);
      final grown = ShoppingList(
        groups: [
          ShoppingGroup(label: 'Produce', items: [item('Lime', checked: true)]),
          ShoppingGroup(label: 'Baking', items: [item('Flour', checked: true)]),
          ShoppingGroup(label: 'Dairy', items: [item('Milk')]),
        ],
      );
      expect(notifier.arm(week, grown, item('Milk')), isTrue);
    });
  });
}
