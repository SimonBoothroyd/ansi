// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_intake.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The real photo intake: `image_picker` — the camera, reopened per page by
/// [PhotoIntakeService.pickAndCrop], or the library's multi-select (the only
/// source that works on the iOS simulator — it has no camera) — feeding
/// [cropSeam], one page at a time: `image_cropper`'s native crop + rotate
/// editor on a phone, and nothing at all in a browser. Confirming a page with
/// no edits is a single tap; the editor's rotate control handles deskew.
///
/// The provider supplies the two platform seams only. The question between
/// pages needs a `BuildContext` and so is passed in by the view.
///
/// A refused camera permission surfaces from `image_picker` as a
/// `PlatformException`; it is left to propagate, because a door that silently
/// does nothing is worse than an error the user can act on.

@ProviderFor(photoIntake)
const photoIntakeProvider = PhotoIntakeProvider._();

/// The real photo intake: `image_picker` — the camera, reopened per page by
/// [PhotoIntakeService.pickAndCrop], or the library's multi-select (the only
/// source that works on the iOS simulator — it has no camera) — feeding
/// [cropSeam], one page at a time: `image_cropper`'s native crop + rotate
/// editor on a phone, and nothing at all in a browser. Confirming a page with
/// no edits is a single tap; the editor's rotate control handles deskew.
///
/// The provider supplies the two platform seams only. The question between
/// pages needs a `BuildContext` and so is passed in by the view.
///
/// A refused camera permission surfaces from `image_picker` as a
/// `PlatformException`; it is left to propagate, because a door that silently
/// does nothing is worse than an error the user can act on.

final class PhotoIntakeProvider
    extends
        $FunctionalProvider<
          PhotoIntakeService,
          PhotoIntakeService,
          PhotoIntakeService
        >
    with $Provider<PhotoIntakeService> {
  /// The real photo intake: `image_picker` — the camera, reopened per page by
  /// [PhotoIntakeService.pickAndCrop], or the library's multi-select (the only
  /// source that works on the iOS simulator — it has no camera) — feeding
  /// [cropSeam], one page at a time: `image_cropper`'s native crop + rotate
  /// editor on a phone, and nothing at all in a browser. Confirming a page with
  /// no edits is a single tap; the editor's rotate control handles deskew.
  ///
  /// The provider supplies the two platform seams only. The question between
  /// pages needs a `BuildContext` and so is passed in by the view.
  ///
  /// A refused camera permission surfaces from `image_picker` as a
  /// `PlatformException`; it is left to propagate, because a door that silently
  /// does nothing is worse than an error the user can act on.
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
