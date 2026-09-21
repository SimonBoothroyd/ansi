/// The photo intake's two doors, shared by the recipe import and the receipt
/// scan.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../data/photo_intake.dart';

/// The photo doors. On a phone there are two: shoot pages now, or pick from the
/// library; each page is then cropped. An empty result starts nothing.
///
/// A browser has no camera and no cropper (`cropSeam`, photo_intake.dart), so
/// it draws one door, "choose image files", with a line saying pages go up as
/// they are. [web] is injectable so both wordings are testable.
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
