/// The `Read a label` door's one public call: [pickLabelPhoto].
///
/// It opens the app's own photo intake behind a sheet — camera or gallery, so
/// a screenshot of another tab works as well as a photograph of the pack — and
/// resolves with ONE image's path, or null when the person backed out. It
/// reads nothing and writes nothing; the caller hands the path to the form.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../import/data/photo_intake.dart';
import '../../import/presentation/photo_doors.dart';

/// Opens the photo doors and resolves with the label photo's path, or null.
///
/// One image: a nutrition panel is one panel, and the form has one set of
/// fields. The camera door takes one shot (no "another page?" loop) and a
/// multi-pick from the library keeps the first.
Future<String?> pickLabelPhoto(BuildContext context, WidgetRef ref) {
  final intake = ref.read(photoIntakeProvider);
  return showAnsiSheet<String>(
    context: context,
    builder: (sheetContext) => AnsiSheetShell(
      title: 'Read a label',
      subtitle: 'one photo of the nutrition panel — a screenshot counts',
      children: [
        ImportPhotoDoors(
          onPick: (source) async {
            final paths = await intake.pickAndCrop(source);
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop(paths.isEmpty ? null : paths.first);
          },
        ),
      ],
    ),
  );
}
