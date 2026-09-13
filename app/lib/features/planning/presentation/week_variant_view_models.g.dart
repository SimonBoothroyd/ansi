// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'week_variant_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Week mode's draft for one `(recipe, week)`. [weekKey] is the week's first
/// day
/// as `YYYY-MM-DD` — the query param the door opens the editor with.

@ProviderFor(WeekVariantDraft)
const weekVariantDraftProvider = WeekVariantDraftFamily._();

/// Week mode's draft for one `(recipe, week)`. [weekKey] is the week's first
/// day
/// as `YYYY-MM-DD` — the query param the door opens the editor with.
final class WeekVariantDraftProvider
    extends $AsyncNotifierProvider<WeekVariantDraft, WeekVariant> {
  /// Week mode's draft for one `(recipe, week)`. [weekKey] is the week's first
  /// day
  /// as `YYYY-MM-DD` — the query param the door opens the editor with.
  const WeekVariantDraftProvider._({
    required WeekVariantDraftFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'weekVariantDraftProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$weekVariantDraftHash();

  @override
  String toString() {
    return r'weekVariantDraftProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  WeekVariantDraft create() => WeekVariantDraft();

  @override
  bool operator ==(Object other) {
    return other is WeekVariantDraftProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$weekVariantDraftHash() => r'88ed6e614bf3649b79aac6db863a0bab5669de42';

/// Week mode's draft for one `(recipe, week)`. [weekKey] is the week's first
/// day
/// as `YYYY-MM-DD` — the query param the door opens the editor with.

final class WeekVariantDraftFamily extends $Family
    with
        $ClassFamilyOverride<
          WeekVariantDraft,
          AsyncValue<WeekVariant>,
          WeekVariant,
          FutureOr<WeekVariant>,
          (String, String)
        > {
  const WeekVariantDraftFamily._()
    : super(
        retry: null,
        name: r'weekVariantDraftProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Week mode's draft for one `(recipe, week)`. [weekKey] is the week's first
  /// day
  /// as `YYYY-MM-DD` — the query param the door opens the editor with.

  WeekVariantDraftProvider call(String recipeId, String weekKey) =>
      WeekVariantDraftProvider._(argument: (recipeId, weekKey), from: this);

  @override
  String toString() => r'weekVariantDraftProvider';
}

/// Week mode's draft for one `(recipe, week)`. [weekKey] is the week's first
/// day
/// as `YYYY-MM-DD` — the query param the door opens the editor with.

abstract class _$WeekVariantDraft extends $AsyncNotifier<WeekVariant> {
  late final _$args = ref.$arg as (String, String);
  String get recipeId => _$args.$1;
  String get weekKey => _$args.$2;

  FutureOr<WeekVariant> build(String recipeId, String weekKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args.$1, _$args.$2);
    final ref = this.ref as $Ref<AsyncValue<WeekVariant>, WeekVariant>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<WeekVariant>, WeekVariant>,
              AsyncValue<WeekVariant>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
