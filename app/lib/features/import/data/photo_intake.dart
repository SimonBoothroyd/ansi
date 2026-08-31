/// Photo intake for import (step 8): pick/capture recipe photos, then crop +
/// rotate each page before it enters the pipeline.
///
/// The flow is: user picks one or more photos → each page opens in the native
/// crop/rotate editor → the confirmed (cropped) files are handed back as paths,
/// which the photos import source carries into `startImport`. The repository
/// then downscales each cropped file (~1568px) and base64-encodes it for the
/// edge function — so the phone never ships a full-res photo.
///
/// [PhotoIntakeService] is the pure, testable loop over two injected seams —
/// `pickImages` (pick/capture → source paths) and `cropImage` (one page →
/// cropped path, or null if the user backed out of that page). The real seams
/// (`image_picker` + `image_cropper`) are plugged in by [photoIntakeProvider];
/// the native editors themselves aren't unit-tested, but the per-page loop is.
library;

import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'photo_intake.g.dart';

/// Picks recipe photos and returns cropped page paths ready for upload.
typedef PickImages = Future<List<String>> Function();

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

  /// Picks photos, then crops/rotates each in turn. A page the user cancels in
  /// the cropper is dropped (the rest still import); returns the cropped paths
  /// in pick order. An empty result (nothing picked, or every page cancelled)
  /// means "start nothing" — the caller must not kick off an import.
  Future<List<String>> pickAndCrop() async {
    final picked = await _pickImages();
    final cropped = <String>[];
    for (final path in picked) {
      final result = await _cropImage(path);
      if (result != null) cropped.add(result);
    }
    return cropped;
  }
}

/// The real photo intake: `image_picker` multi-select (the only source that
/// works on the iOS simulator — it has no camera) feeding `image_cropper`'s
/// native crop + rotate editor, one page at a time. Confirming a page with no
/// edits is a single tap; the editor's rotate control handles deskew.
@Riverpod(keepAlive: true)
PhotoIntakeService photoIntake(Ref ref) {
  final picker = ImagePicker();
  final cropper = ImageCropper();
  return PhotoIntakeService(
    pickImages: () async {
      final files = await picker.pickMultiImage();
      return [for (final f in files) f.path];
    },
    cropImage: (sourcePath) async {
      final result = await cropper.cropImage(
        sourcePath: sourcePath,
        uiSettings: [
          IOSUiSettings(title: 'Crop'),
          AndroidUiSettings(toolbarTitle: 'Crop'),
        ],
      );
      return result?.path;
    },
  );
}
