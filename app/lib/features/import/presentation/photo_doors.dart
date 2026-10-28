/// The photo intake's two doors, shared by the recipe import and the receipt
/// scan.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/photo_intake.dart';

/// The photo doors. On a phone there are two: shoot pages now, or pick from the
/// library; each page is then cropped. An empty result starts nothing.
///
/// A browser has no camera and no cropper (`cropSeam`, photo_intake.dart), so
/// it draws one door, "choose image files", and its pages go up as they are.
/// [web] is injectable so both forms are testable.
class ImportPhotoDoors extends StatelessWidget {
  const ImportPhotoDoors({required this.onPick, this.web = kIsWeb, super.key});

  final void Function(PhotoSource source) onPick;

  final bool web;

  @override
  Widget build(BuildContext context) {
    if (web) {
      return FButton(
        variant: FButtonVariant.outline,
        prefix: const Icon(FLucideIcons.image),
        onPress: () => onPick(PhotoSource.library),
        child: const Text('Choose image files'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: FButton(
            variant: FButtonVariant.outline,
            prefix: const Icon(FLucideIcons.camera),
            onPress: () => onPick(PhotoSource.camera),
            child: const Text('Take a photo'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FButton(
            variant: FButtonVariant.outline,
            prefix: const Icon(FLucideIcons.image),
            onPress: () => onPick(PhotoSource.library),
            child: const Text('Choose photos'),
          ),
        ),
      ],
    );
  }
}
