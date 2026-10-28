// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dropped_write_subject.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// [write]'s subject, read once from the local database.

@ProviderFor(droppedWriteSubject)
const droppedWriteSubjectProvider = DroppedWriteSubjectFamily._();

/// [write]'s subject, read once from the local database.

final class DroppedWriteSubjectProvider
    extends
        $FunctionalProvider<
          AsyncValue<DroppedWriteSubject>,
          DroppedWriteSubject,
          FutureOr<DroppedWriteSubject>
        >
    with
        $FutureModifier<DroppedWriteSubject>,
        $FutureProvider<DroppedWriteSubject> {
  /// [write]'s subject, read once from the local database.
  const DroppedWriteSubjectProvider._({
    required DroppedWriteSubjectFamily super.from,
    required DroppedWrite super.argument,
  }) : super(
         retry: null,
         name: r'droppedWriteSubjectProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$droppedWriteSubjectHash();

  @override
  String toString() {
    return r'droppedWriteSubjectProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<DroppedWriteSubject> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DroppedWriteSubject> create(Ref ref) {
    final argument = this.argument as DroppedWrite;
    return droppedWriteSubject(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DroppedWriteSubjectProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$droppedWriteSubjectHash() =>
    r'66c431fb05f11f3d185fe2fef5ac39906ebff93a';

/// [write]'s subject, read once from the local database.

final class DroppedWriteSubjectFamily extends $Family
    with
        $FunctionalFamilyOverride<FutureOr<DroppedWriteSubject>, DroppedWrite> {
  const DroppedWriteSubjectFamily._()
    : super(
        retry: null,
        name: r'droppedWriteSubjectProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// [write]'s subject, read once from the local database.

  DroppedWriteSubjectProvider call(DroppedWrite write) =>
      DroppedWriteSubjectProvider._(argument: write, from: this);

  @override
  String toString() => r'droppedWriteSubjectProvider';
}
