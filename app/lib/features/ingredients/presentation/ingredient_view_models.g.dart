// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ingredient_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The form's ViewModel — one per ingredient id, and one for the create form
/// (a null id, which is what makes this the app's one add flow).

@ProviderFor(IngredientForm)
const ingredientFormProvider = IngredientFormFamily._();

/// The form's ViewModel — one per ingredient id, and one for the create form
/// (a null id, which is what makes this the app's one add flow).
final class IngredientFormProvider
    extends $NotifierProvider<IngredientForm, IngredientFormDraft> {
  /// The form's ViewModel — one per ingredient id, and one for the create form
  /// (a null id, which is what makes this the app's one add flow).
  const IngredientFormProvider._({
    required IngredientFormFamily super.from,
    required (String?, {String initialName}) super.argument,
  }) : super(
         retry: null,
         name: r'ingredientFormProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ingredientFormHash();

  @override
  String toString() {
    return r'ingredientFormProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  IngredientForm create() => IngredientForm();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IngredientFormDraft value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IngredientFormDraft>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IngredientFormProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ingredientFormHash() => r'2297c472b3b8d14231043a0a59de618878748ed2';

/// The form's ViewModel — one per ingredient id, and one for the create form
/// (a null id, which is what makes this the app's one add flow).

final class IngredientFormFamily extends $Family
    with
        $ClassFamilyOverride<
          IngredientForm,
          IngredientFormDraft,
          IngredientFormDraft,
          IngredientFormDraft,
          (String?, {String initialName})
        > {
  const IngredientFormFamily._()
    : super(
        retry: null,
        name: r'ingredientFormProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The form's ViewModel — one per ingredient id, and one for the create form
  /// (a null id, which is what makes this the app's one add flow).

  IngredientFormProvider call(
    String? ingredientId, {
    String initialName = '',
  }) => IngredientFormProvider._(
    argument: (ingredientId, initialName: initialName),
    from: this,
  );

  @override
  String toString() => r'ingredientFormProvider';
}

/// The form's ViewModel — one per ingredient id, and one for the create form
/// (a null id, which is what makes this the app's one add flow).

abstract class _$IngredientForm extends $Notifier<IngredientFormDraft> {
  late final _$args = ref.$arg as (String?, {String initialName});
  String? get ingredientId => _$args.$1;
  String get initialName => _$args.initialName;

  IngredientFormDraft build(String? ingredientId, {String initialName = ''});
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args.$1, initialName: _$args.initialName);
    final ref = this.ref as $Ref<IngredientFormDraft, IngredientFormDraft>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IngredientFormDraft, IngredientFormDraft>,
              IngredientFormDraft,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
