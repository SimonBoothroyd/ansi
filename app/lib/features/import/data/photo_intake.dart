/// Photo intake for import (step 8): pick/capture recipe photos, then crop +
/// rotate each page before it enters the pipeline.
///
/// The flow is: user photographs a page with the camera, or picks one or more
/// from the library → each page opens in the native crop/rotate editor → the
/// confirmed (cropped) files are handed back as paths, which the photos import
/// source carries into `startImport`. The repository then downscales each
/// cropped file (~1568px) and base64-encodes it for the edge function — so the
/// phone never ships a full-res photo.
///
/// The camera door is one page per tap: a book that spans pages is either
/// shot as one spread or photographed first and picked from the library, so
/// the common single-page case stays one shot, one crop, no "another page?"
/// question in between.
///
/// [PhotoIntakeService] is the pure, testable loop over two injected seams —
/// `pickImages` (a [PhotoSource] → source paths) and `cropImage` (one page →
/// cropped path, or null if the user backed out of that page). The real seams
/// (`image_picker` + `image_cropper`) are plugged in by [photoIntakeProvider];
/// the native editors themselves aren't unit-tested, but the per-page loop is.
library;

import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'photo_intake.g.dart';

/// Where the pages come from: the camera (one page per capture) or the photo
/// library (any number, multi-select).
enum PhotoSource { camera, library }

/// Picks or captures recipe photos and returns their source paths, in order.
/// Empty when the user backed out of the picker or the camera.
typedef PickImages = Future<List<String>> Function(PhotoSource source);

/// Opens the crop/rotate editor for [sourcePath]; returns the cropped file's
/// path, or null when the user cancelled this page.
typedef CropImage = Future<String?> Function(String sourcePath);

class PhotoIntakeService {
  const PhotoIntakeService({
    required PickImages pickImages,
    required CropImage cropImage,
  }) : _pickImages = pickImages,
       _cropImage = cropImage;

  final PickImages _pickImages;
  final CropImage _cropImage;

  /// Captures or picks photos from [source], then crops/rotates each in turn.
  /// A page the user cancels in the cropper is dropped (the rest still
  /// import); returns the cropped paths in pick order. An empty result
  /// (nothing picked, camera dismissed, or every page cancelled) means "start
  /// nothing" — the caller must not kick off an import.
  Future<List<String>> pickAndCrop(PhotoSource source) async {
    final picked = await _pickImages(source);
    final cropped = <String>[];
    for (final path in picked) {
      final result = await _cropImage(path);
      if (result != null) cropped.add(result);
    }
    return cropped;
  }
}

/// The real photo intake: `image_picker` — the camera for one page, or the
/// library's multi-select (the only source that works on the iOS simulator —
/// it has no camera) — feeding `image_cropper`'s native crop + rotate editor,
/// one page at a time. Confirming a page with no edits is a single tap; the
/// editor's rotate control handles deskew.
///
/// A refused camera permission surfaces from `image_picker` as a
/// `PlatformException`; it is left to propagate, because a door that silently
/// does nothing is worse than an error the user can act on.
@Riverpod(keepAlive: true)
PhotoIntakeService photoIntake(Ref ref) {
  final picker = ImagePicker();
  final cropper = ImageCropper();
  return PhotoIntakeService(
    pickImages: (source) async {
      switch (source) {
        case PhotoSource.camera:
          final file = await picker.pickImage(source: ImageSource.camera);
          return [if (file != null) file.path];
        case PhotoSource.library:
          final files = await picker.pickMultiImage();
          return [for (final f in files) f.path];
      }
    },
    cropImage: (sourcePath) async {
      final result = await cropper.cropImage(
        sourcePath: sourcePath,
        uiSettings: [
          IOSUiSettings(title: 'Crop'),
          // uCrop ships with freestyle (freely resizable) crop OFF, and the
          // plugin only turns it on when lockAspectRatio is explicitly false —
          // omit it and Android is stuck with a fixed-ratio box while iOS is
          // freeform.
          AndroidUiSettings(toolbarTitle: 'Crop', lockAspectRatio: false),
        ],
      );
      return result?.path;
    },
  );
}
