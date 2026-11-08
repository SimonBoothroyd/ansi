// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'leftovers_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The household's leftovers today, fridge first, live. Read from the week
/// holding today, whatever week is on screen: the fridge is now.

@ProviderFor(fridgeAndFreezer)
const fridgeAndFreezerProvider = FridgeAndFreezerProvider._();

/// The household's leftovers today, fridge first, live. Read from the week
/// holding today, whatever week is on screen: the fridge is now.

final class FridgeAndFreezerProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Leftover>>,
          List<Leftover>,
          Stream<List<Leftover>>
        >
    with $FutureModifier<List<Leftover>>, $StreamProvider<List<Leftover>> {
  /// The household's leftovers today, fridge first, live. Read from the week
  /// holding today, whatever week is on screen: the fridge is now.
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
  $StreamProviderElement<List<Leftover>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Leftover>> create(Ref ref) {
    return fridgeAndFreezer(ref);
  }
}

String _$fridgeAndFreezerHash() => r'e585e36fdaa345b404b5f1f06fba6dfa82d009e9';

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

/// Which shelf each stored row is on, by id: a meal planned from one wears
/// that shelf's tag on the Week.

@ProviderFor(leftoverPlaces)
const leftoverPlacesProvider = LeftoverPlacesProvider._();

/// Which shelf each stored row is on, by id: a meal planned from one wears
/// that shelf's tag on the Week.

final class LeftoverPlacesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, LeftoverPlace>>,
          Map<String, LeftoverPlace>,
          Stream<Map<String, LeftoverPlace>>
        >
    with
        $FutureModifier<Map<String, LeftoverPlace>>,
        $StreamProvider<Map<String, LeftoverPlace>> {
  /// Which shelf each stored row is on, by id: a meal planned from one wears
  /// that shelf's tag on the Week.
  const LeftoverPlacesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'leftoverPlacesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$leftoverPlacesHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, LeftoverPlace>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, LeftoverPlace>> create(Ref ref) {
    return leftoverPlaces(ref);
  }
}

String _$leftoverPlacesHash() => r'4adad43ee856053e7780ee71fdf243379e850ca9';

/// The rows a meal on [day] can be planned from, fridge then freezer: a fridge
/// row good on the day and not yet behind its date, any freezer row. Only a
/// recipe's row: a meal is planned from a recipe. Empty for a day behind us.

@ProviderFor(leftoversGoodOn)
const leftoversGoodOnProvider = LeftoversGoodOnFamily._();

/// The rows a meal on [day] can be planned from, fridge then freezer: a fridge
/// row good on the day and not yet behind its date, any freezer row. Only a
/// recipe's row: a meal is planned from a recipe. Empty for a day behind us.

final class LeftoversGoodOnProvider
    extends $FunctionalProvider<List<Leftover>, List<Leftover>, List<Leftover>>
    with $Provider<List<Leftover>> {
  /// The rows a meal on [day] can be planned from, fridge then freezer: a fridge
  /// row good on the day and not yet behind its date, any freezer row. Only a
  /// recipe's row: a meal is planned from a recipe. Empty for a day behind us.
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

String _$leftoversGoodOnHash() => r'f886bed45a381740726ea04dc5f5836e12432b61';

/// The rows a meal on [day] can be planned from, fridge then freezer: a fridge
/// row good on the day and not yet behind its date, any freezer row. Only a
/// recipe's row: a meal is planned from a recipe. Empty for a day behind us.

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

  /// The rows a meal on [day] can be planned from, fridge then freezer: a fridge
  /// row good on the day and not yet behind its date, any freezer row. Only a
  /// recipe's row: a meal is planned from a recipe. Empty for a day behind us.

  LeftoversGoodOnProvider call(DateTime day) =>
      LeftoversGoodOnProvider._(argument: day, from: this);

  @override
  String toString() => r'leftoversGoodOnProvider';
}
