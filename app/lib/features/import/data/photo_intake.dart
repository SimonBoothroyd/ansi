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
/// In a browser the flow is shorter and the screen says so: pages are chosen
/// as files, there is no camera door and no crop step ([cropSeam]).
///
/// The camera door photographs as many pages as the cook has: after each shot
/// is cropped it asks whether there is another, so a recipe that runs over a
/// page break is shot page by page in one sitting rather than photographed
/// first and picked back out of the library. Dismissing the camera ends the
/// shooting and imports what has been kept. The library door, already
/// multi-select, never asks.
///
/// [PhotoIntakeService] is the pure, testable loop over two injected seams —
/// `pickImages` (a [PhotoSource] → source paths) and `cropImage` (one page →
/// cropped path, or null if the user backed out of that page). The real seams
/// (`image_picker` + `image_cropper`) are plugged in by [photoIntakeProvider];
/// the native editors themselves aren't unit-tested, but the per-page loop is.
///
/// The third seam, [AskAnotherPage], is a **parameter of
/// [PhotoIntakeService.pickAndCrop]** and not a constructor argument, because
/// asking needs a `BuildContext` and the provider that builds the service has
/// none: a constructor seam would have to be nullable, supplied by nobody, and
/// the one caller that can ask would be passing it anyway. As a parameter the
/// view hands over a closure that is live exactly as long as the screen is.
library;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'photo_intake.g.dart';

/// Where the pages come from: the camera (one shot per capture, repeated for
/// as long as the cook keeps saying yes) or the photo library (any number,
/// multi-select, asked for once).
enum PhotoSource { camera, library }

/// Picks or captures recipe photos and returns their source paths, in order.
/// Empty when the user backed out of the picker or the camera.
typedef PickImages = Future<List<String>> Function(PhotoSource source);

/// Opens the crop/rotate editor for [sourcePath]; returns the cropped file's
/// path, or null when the user cancelled this page.
typedef CropImage = Future<String?> Function(String sourcePath);

/// Asks whether there is another page to photograph, given how many pages are
/// already kept ([pagesSoFar], never zero). True reopens the camera; false —
/// including a dismissal, and including a screen that is gone — reads the
/// pages already kept.
typedef AskAnotherPage = Future<bool> Function(int pagesSoFar);

class PhotoIntakeService {
  const PhotoIntakeService({
    required PickImages pickImages,
    required CropImage cropImage,
  }) : _pickImages = pickImages,
       _cropImage = cropImage;

  final PickImages _pickImages;
  final CropImage _cropImage;

  /// Captures or picks photos from [source], then crops/rotates each in turn,
  /// returning the cropped paths in the order they were taken. A page the user
  /// cancels in the cropper is dropped and the rest still import. An empty
  /// result (nothing picked, camera dismissed on the first page, or every page
  /// cancelled) means "start nothing" — the caller must not kick off an import.
  ///
  /// From the camera the door reopens for as long as [askAnotherPage] answers
  /// yes, so a recipe spread over pages is one sitting of shoot → crop → "and
  /// another". Three edges hold that loop honest: dismissing the camera ends
  /// the shooting and keeps what is already cropped; a first page cancelled in
  /// the cropper leaves nothing kept, so there is nothing to ask *about* and
  /// the question is skipped; but a page cancelled once something is kept still
  /// asks, which is how a bad shot is retaken. Without [askAnotherPage] — and
  /// from the library, whose multi-select already took every page at once — it
  /// is one pass and no question.
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

/// The crop/rotate step, where there is one.
///
/// On a phone it is `image_cropper`'s native editor. **In a browser there is
/// no crop step at all**: the plugin throws without `WebUiSettings`, and
/// supplying those means shipping the cropperjs stylesheet and script in
/// `web/index.html` *and* threading a `BuildContext` into a provider that
/// deliberately has none (see the seam note at the top of this file). That is
/// a third-party editor and a rewiring for a door a household reaches from a
/// browser rarely and can always reach from a phone — so the web build hands
/// the page through untouched and the import screen says so, rather than
/// pretending to crop or throwing at the tap.
///
/// [web] is the platform, injectable so the skip is a tested fact rather than
/// a branch nobody on the VM can reach.
@visibleForTesting
CropImage cropSeam({bool web = kIsWeb}) {
  if (web) return (sourcePath) async => sourcePath;
  final cropper = ImageCropper();
  return (sourcePath) async {
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
  };
}
