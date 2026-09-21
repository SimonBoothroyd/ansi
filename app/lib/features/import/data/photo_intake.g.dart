// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_intake.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The real photo intake: `image_picker` (the camera, or the library's
/// multi-select, the only source on the iOS simulator) feeding [cropSeam] one
/// page at a time. A refused camera permission surfaces as a
/// `PlatformException` and is left to propagate.

@ProviderFor(photoIntake)
const photoIntakeProvider = PhotoIntakeProvider._();

/// The real photo intake: `image_picker` (the camera, or the library's
/// multi-select, the only source on the iOS simulator) feeding [cropSeam] one
/// page at a time. A refused camera permission surfaces as a
/// `PlatformException` and is left to propagate.

final class PhotoIntakeProvider
    extends
        $FunctionalProvider<
          PhotoIntakeService,
          PhotoIntakeService,
          PhotoIntakeService
        >
    with $Provider<PhotoIntakeService> {
  /// The real photo intake: `image_picker` (the camera, or the library's
  /// multi-select, the only source on the iOS simulator) feeding [cropSeam] one
  /// page at a time. A refused camera permission surfaces as a
  /// `PlatformException` and is left to propagate.
  const PhotoIntakeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'photoIntakeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$photoIntakeHash();

  @$internal
  @override
  $ProviderElement<PhotoIntakeService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PhotoIntakeService create(Ref ref) {
    return photoIntake(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PhotoIntakeService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PhotoIntakeService>(value),
    );
  }
}

String _$photoIntakeHash() => r'46a64682b507823e3e1fce9aab374d70f5177ae3';
