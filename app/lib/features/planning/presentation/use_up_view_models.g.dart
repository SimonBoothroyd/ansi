// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'use_up_view_models.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(useUp)
const useUpProvider = UseUpFamily._();

final class UseUpProvider
    extends
        $FunctionalProvider<
          AsyncValue<UseUpView>,
          UseUpView,
          FutureOr<UseUpView>
        >
    with $FutureModifier<UseUpView>, $FutureProvider<UseUpView> {
  const UseUpProvider._({
    required UseUpFamily super.from,
    required DateTime super.argument,
  }) : super(
         retry: null,
         name: r'useUpProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$useUpHash();

  @override
  String toString() {
    return r'useUpProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<UseUpView> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<UseUpView> create(Ref ref) {
    final argument = this.argument as DateTime;
    return useUp(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is UseUpProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$useUpHash() => r'13cf2542a82e3d251b59c8320ea17219f9561067';

final class UseUpFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<UseUpView>, DateTime> {
  const UseUpFamily._()
    : super(
        retry: null,
        name: r'useUpProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  UseUpProvider call(DateTime weekStart) =>
      UseUpProvider._(argument: weekStart, from: this);

  @override
  String toString() => r'useUpProvider';
}
