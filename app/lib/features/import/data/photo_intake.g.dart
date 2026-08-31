// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_intake.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The real photo intake: `image_picker` multi-select (the only source that
/// works on the iOS simulator — it has no camera) feeding `image_cropper`'s
/// native crop + rotate editor, one page at a time. Confirming a page with no
/// edits is a single tap; the editor's rotate control handles deskew.

@ProviderFor(photoIntake)
const photoIntakeProvider = PhotoIntakeProvider._();

/// The real photo intake: `image_picker` multi-select (the only source that
/// works on the iOS simulator — it has no camera) feeding `image_cropper`'s
/// native crop + rotate editor, one page at a time. Confirming a page with no
/// edits is a single tap; the editor's rotate control handles deskew.

final class PhotoIntakeProvider
    extends
        $FunctionalProvider<
          PhotoIntakeService,
          PhotoIntakeService,
          PhotoIntakeService
        >
    with $Provider<PhotoIntakeService> {
  /// The real photo intake: `image_picker` multi-select (the only source that
  /// works on the iOS simulator — it has no camera) feeding `image_cropper`'s
  /// native crop + rotate editor, one page at a time. Confirming a page with no
  /// edits is a single tap; the editor's rotate control handles deskew.
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

String _$photoIntakeHash() => r'034f54c2fd49b92f76897a691b9b836cdcdd27b8';
