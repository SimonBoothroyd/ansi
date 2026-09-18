/// The photo intake's two doors, in the words each platform can honour.
///
/// They are shared by the recipe import and the receipt scan, because both
/// ask the same thing of the same service: pick or shoot pages, crop each,
/// hand back the paths.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../data/photo_intake.dart';

/// The photo doors, in the words each platform can honour.
///
/// On a phone there are two, split by where the page comes from: shoot them
/// now, page after page until the cook says to read it, or pick one or more
/// from the library. Either way it is pick → crop/rotate each → import the
/// cropped set. An empty result (nothing picked, camera dismissed with nothing
/// kept, every page cancelled) starts nothing; the repository downscales each
/// page before upload.
///
/// A browser has no camera door to open and no cropper behind it
/// (`cropSeam`, photo_intake.dart), so it draws **one** door, named for what
/// it actually does — choose image files — with a line saying the pages go up
/// as they are. "Take a photo" there would promise a camera the tab has not
/// got, and a crop that never happens.
///
/// [web] is the platform, injectable so both sets of words are testable on a
/// VM that is never `kIsWeb`.
class ImportPhotoDoors extends StatelessWidget {
  const ImportPhotoDoors({required this.onPick, this.web = kIsWeb, super.key});

  final void Function(PhotoSource source) onPick;

  final bool web;

  @override
  Widget build(BuildContext context) {
    if (web) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FButton(
            variant: FButtonVariant.outline,
            prefix: const Icon(FLucideIcons.image),
            onPress: () => onPick(PhotoSource.library),
            child: const Text('Choose image files'),
          ),
          const SizedBox(height: 8),
          Text(
            'In a browser the pages go up as they are — cropping and rotating '
            'is a phone job. Photograph the page there, or choose a file here.',
            style: ansiSans(size: 12.5, color: AnsiColors.muted, height: 1.4),
          ),
        ],
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
