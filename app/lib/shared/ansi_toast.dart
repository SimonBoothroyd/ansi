/// The app's toasts. A toast reports an act that did not happen; a state that
/// stays wrong is the sync banner's.
///
/// Position and width are set once on the theme's toaster style. A toast needs
/// the `FToaster` ancestor `app.dart` installs, so a widget test must use
/// `pumpAnsiApp`. See `docs/design-docs/errors-and-sync-health.md`.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';

/// Long enough to read a sentence and reach for Retry.
const _toastDuration = Duration(seconds: 6);

/// A context below the app's one `FToaster`, for a caller outside the widget
/// tree (the zone handler). Null until the first frame.
final ansiToastAnchor = GlobalKey(debugLabel: 'ansi toast anchor');

/// Reports that one thing the user asked for did not happen.
///
/// [what] is a lowercase verb phrase completing "Couldn't ___." in the user's
/// own nouns. [onRetry] runs the same write again; pass null only where
/// re-running would be wrong.
void showAnsiFailureToast(
  BuildContext context, {
  required String what,
  VoidCallback? onRetry,
}) {
  showFToast(
    context: context,
    variant: FToastVariant.destructive,
    duration: _toastDuration,
    icon: const Icon(FLucideIcons.circleAlert),
    title: Text('Couldn’t $what.'),
    suffixBuilder: onRetry == null
        ? null
        : (context, entry) => FButton(
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            onPress: () {
              entry.dismiss();
              onRetry();
            },
            child: const Text('Retry'),
          ),
  );
}

/// Reports that something threw where nobody was expecting it. Primary, not
/// destructive. The caller rate-limits
/// (`core/observability/crash_sink.dart`).
void showAnsiProblemToast(
  BuildContext context, {
  required VoidCallback onCopyDetails,
}) {
  showFToast(
    context: context,
    duration: _toastDuration,
    icon: const Icon(FLucideIcons.info),
    title: const Text('Something went wrong.'),
    description: Text('Ansi kept going.', style: ansiMonoInherit(size: 11)),
    suffixBuilder: (context, entry) => FButton(
      variant: FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      onPress: () {
        entry.dismiss();
        onCopyDetails();
      },
      child: const Text('Copy details'),
    ),
  );
}

/// Reports that something the user removed is recoverable, and carries the
/// undo. The one exception to "no success toasts"
/// (`docs/design-docs/errors-and-sync-health.md`, D1).
///
/// [what] is what went, in the user's own nouns; [detail] names what would
/// come back. Primary, not destructive.
void showAnsiUndoToast(
  BuildContext context, {
  required String what,
  required VoidCallback onUndo,
  String? detail,
}) {
  showFToast(
    context: context,
    duration: _toastDuration,
    icon: const Icon(FLucideIcons.minus),
    title: Text(what),
    description: detail == null
        ? null
        : Text(detail, style: ansiMonoInherit(size: 11)),
    suffixBuilder: (context, entry) => FButton(
      variant: FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      onPress: () {
        entry.dismiss();
        onUndo();
      },
      child: const Text('Undo'),
    ),
  );
}
