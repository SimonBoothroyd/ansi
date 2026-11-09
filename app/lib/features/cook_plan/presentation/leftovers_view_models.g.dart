// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'leftovers_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The household's leftovers today and every meal served from one, live,
/// whatever week is on screen: the fridge is now.

@ProviderFor(leftoverShelves)
const leftoverShelvesProvider = LeftoverShelvesProvider._();

/// The household's leftovers today and every meal served from one, live,
/// whatever week is on screen: the fridge is now.

final class LeftoverShelvesProvider
    extends
        $FunctionalProvider<
          AsyncValue<LeftoverShelves>,
          LeftoverShelves,
          Stream<LeftoverShelves>
        >
    with $FutureModifier<LeftoverShelves>, $StreamProvider<LeftoverShelves> {
  /// The household's leftovers today and every meal served from one, live,
  /// whatever week is on screen: the fridge is now.
  const LeftoverShelvesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'leftoverShelvesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$leftoverShelvesHash();

  @$internal
  @override
  $StreamProviderElement<LeftoverShelves> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<LeftoverShelves> create(Ref ref) {
    return leftoverShelves(ref);
  }
}

String _$leftoverShelvesHash() => r'2c9c1006b19d71e87b944b37aa37689333c2a134';

/// The rows of [leftoverShelves], fridge first.

@ProviderFor(fridgeAndFreezer)
const fridgeAndFreezerProvider = FridgeAndFreezerProvider._();

/// The rows of [leftoverShelves], fridge first.

final class FridgeAndFreezerProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Leftover>>,
          AsyncValue<List<Leftover>>,
          AsyncValue<List<Leftover>>
        >
    with $Provider<AsyncValue<List<Leftover>>> {
  /// The rows of [leftoverShelves], fridge first.
  const FridgeAndFreezerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'fridgeAndFreezerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fridgeAndFreezerHash();

  @$internal
  @override
  $ProviderElement<AsyncValue<List<Leftover>>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AsyncValue<List<Leftover>> create(Ref ref) {
    return fridgeAndFreezer(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<List<Leftover>> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<List<Leftover>>>(value),
    );
  }
}

String _$fridgeAndFreezerHash() => r'94cd70070cedfa594475719fe45131a73281e628';

/// Each meal linked to a cooking, judged on its own day, by `plan_entry` id:
/// its shelf and any warning.

@ProviderFor(leftoverMeals)
const leftoverMealsProvider = LeftoverMealsProvider._();

/// Each meal linked to a cooking, judged on its own day, by `plan_entry` id:
/// its shelf and any warning.

final class LeftoverMealsProvider
    extends
        $FunctionalProvider<
          Map<String, LeftoverMeal>,
          Map<String, LeftoverMeal>,
          Map<String, LeftoverMeal>
        >
    with $Provider<Map<String, LeftoverMeal>> {
  /// Each meal linked to a cooking, judged on its own day, by `plan_entry` id:
  /// its shelf and any warning.
  const LeftoverMealsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'leftoverMealsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$leftoverMealsHash();

  @$internal
  @override
  $ProviderElement<Map<String, LeftoverMeal>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, LeftoverMeal> create(Ref ref) {
    return leftoverMeals(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, LeftoverMeal> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, LeftoverMeal>>(value),
    );
  }
}

String _$leftoverMealsHash() => r'995a80a711befbfef742f7dc98017ef24322e954';

/// Whether any row is behind its date: the dot on the Week's door.

@ProviderFor(anyLeftoverPastItsDate)
const anyLeftoverPastItsDateProvider = AnyLeftoverPastItsDateProvider._();

/// Whether any row is behind its date: the dot on the Week's door.

final class AnyLeftoverPastItsDateProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether any row is behind its date: the dot on the Week's door.
  const AnyLeftoverPastItsDateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'anyLeftoverPastItsDateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$anyLeftoverPastItsDateHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return anyLeftoverPastItsDate(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$anyLeftoverPastItsDateHash() =>
    r'aacd63ba57c153b4bbc81c511b34452c7b6340fe';

/// The rows a meal on [day] can be planned from, fridge then freezer, each as
/// [leftoverOfferOn] offers it for that day: judged on [day], a fridge row
/// that will need freezing by then offered under Freezer. Soonest to go off
/// first within each. Only a recipe's row: a meal is planned from a recipe.
/// Empty for a day behind us.

@ProviderFor(leftoversGoodOn)
const leftoversGoodOnProvider = LeftoversGoodOnFamily._();

/// The rows a meal on [day] can be planned from, fridge then freezer, each as
/// [leftoverOfferOn] offers it for that day: judged on [day], a fridge row
/// that will need freezing by then offered under Freezer. Soonest to go off
/// first within each. Only a recipe's row: a meal is planned from a recipe.
/// Empty for a day behind us.

final class LeftoversGoodOnProvider
    extends $FunctionalProvider<List<Leftover>, List<Leftover>, List<Leftover>>
    with $Provider<List<Leftover>> {
  /// The rows a meal on [day] can be planned from, fridge then freezer, each as
  /// [leftoverOfferOn] offers it for that day: judged on [day], a fridge row
  /// that will need freezing by then offered under Freezer. Soonest to go off
  /// first within each. Only a recipe's row: a meal is planned from a recipe.
  /// Empty for a day behind us.
  const LeftoversGoodOnProvider._({
    required LeftoversGoodOnFamily super.from,
    required DateTime super.argument,
  }) : super(
         retry: null,
         name: r'leftoversGoodOnProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$leftoversGoodOnHash();

  @override
  String toString() {
    return r'leftoversGoodOnProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<List<Leftover>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Leftover> create(Ref ref) {
    final argument = this.argument as DateTime;
    return leftoversGoodOn(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Leftover> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Leftover>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LeftoversGoodOnProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$leftoversGoodOnHash() => r'b8d67597d183329ce1c2e6db04d2bf5c34540fc4';

/// The rows a meal on [day] can be planned from, fridge then freezer, each as
/// [leftoverOfferOn] offers it for that day: judged on [day], a fridge row
/// that will need freezing by then offered under Freezer. Soonest to go off
/// first within each. Only a recipe's row: a meal is planned from a recipe.
/// Empty for a day behind us.

final class LeftoversGoodOnFamily extends $Family
    with $FunctionalFamilyOverride<List<Leftover>, DateTime> {
  const LeftoversGoodOnFamily._()
    : super(
        retry: null,
        name: r'leftoversGoodOnProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The rows a meal on [day] can be planned from, fridge then freezer, each as
  /// [leftoverOfferOn] offers it for that day: judged on [day], a fridge row
  /// that will need freezing by then offered under Freezer. Soonest to go off
  /// first within each. Only a recipe's row: a meal is planned from a recipe.
  /// Empty for a day behind us.

  LeftoversGoodOnProvider call(DateTime day) =>
      LeftoversGoodOnProvider._(argument: day, from: this);

  @override
  String toString() => r'leftoversGoodOnProvider';
}
