/// Photo intake for import: pick or capture recipe photos, then crop and rotate
/// each page.
///
/// The confirmed files are handed back as paths for `startImport`; the
/// repository downscales and encodes them. In a browser pages are chosen as
/// files, with no camera and no crop step ([cropSeam]). The camera door asks
/// after each cropped shot whether there is another page; the multi-select
/// library door never asks.
///
/// [PhotoIntakeService] is the testable loop over two injected seams,
/// `pickImages` and `cropImage`, plugged in by [photoIntakeProvider].
/// [AskAnotherPage] is a parameter of [PhotoIntakeService.pickAndCrop] rather
/// than a constructor argument because asking needs a `BuildContext`, which the
/// provider lacks.
library;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'photo_intake.g.dart';

/// Where the pages come from: the camera (one shot per capture, repeated) or
/// the photo library (multi-select, asked once).
enum PhotoSource { camera, library }

/// Picks or captures recipe photos and returns their source paths, in order.
/// Empty when the user backed out of the picker or the camera.
typedef PickImages = Future<List<String>> Function(PhotoSource source);

/// Opens the crop/rotate editor for [sourcePath]; returns the cropped file's
/// path, or null when the user cancelled this page.
typedef CropImage = Future<String?> Function(String sourcePath);

/// Asks whether there is another page to photograph, given [pagesSoFar] (never
/// zero). True reopens the camera; false, including a dismissal, imports the
/// pages kept.
typedef AskAnotherPage = Future<bool> Function(int pagesSoFar);

class PhotoIntakeService {
  const PhotoIntakeService({
    required PickImages pickImages,
    required CropImage cropImage,
  }) : _pickImages = pickImages,
       _cropImage = cropImage;

  final PickImages _pickImages;
  final CropImage _cropImage;

  /// Captures or picks photos from [source], then crops each in turn, returning
  /// the cropped paths in order. A page cancelled in the cropper is dropped. An
  /// empty result means the caller must not start an import.
  ///
  /// From the camera the door reopens while [askAnotherPage] answers yes.
  /// Dismissing the camera keeps what is cropped. A cancelled first page skips
  /// the question; a cancelled later page still asks, which is how a bad shot
  /// is retaken. Without [askAnotherPage], and from the library, it is one
  /// pass.
  Future<List<String>> pickAndCrop(
    PhotoSource source, {
    AskAnotherPage? askAnotherPage,
  }) async {
    final cropped = <String>[];
    do {
      final picked = await _pickImages(source);
      if (picked.isEmpty) break;
      for (final path in picked) {
        final result = await _cropImage(path);
        if (result != null) cropped.add(result);
      }
    } while (source == PhotoSource.camera &&
        cropped.isNotEmpty &&
        askAnotherPage != null &&
        await askAnotherPage(cropped.length));
    return cropped;
  }
}

/// The real photo intake: `image_picker` (the camera, or the library's
/// multi-select, the only source on the iOS simulator) feeding [cropSeam] one
/// page at a time. A refused camera permission surfaces as a
/// `PlatformException` and is left to propagate.
@Riverpod(keepAlive: true)
PhotoIntakeService photoIntake(Ref ref) {
  final picker = ImagePicker();
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
    cropImage: cropSeam(),
  );
}

/// The crop and rotate step: `image_cropper`'s native editor on a phone. In a
/// browser the page passes through untouched, because the plugin throws without
/// `WebUiSettings`, which would need cropperjs in `web/index.html` and a
/// `BuildContext` this provider lacks. [web] is injectable so the skip is
/// testable.
@visibleForTesting
CropImage cropSeam({bool web = kIsWeb}) {
  if (web) return (sourcePath) async => sourcePath;
  final cropper = ImageCropper();
  return (sourcePath) async {
    final result = await cropper.cropImage(
      sourcePath: sourcePath,
      uiSettings: [
        IOSUiSettings(title: 'Crop'),
        // uCrop only enables freestyle crop when lockAspectRatio is explicitly
        // false; omitted, Android gets a fixed-ratio box.
        AndroidUiSettings(toolbarTitle: 'Crop', lockAspectRatio: false),
      ],
    );
    return result?.path;
  };
}
