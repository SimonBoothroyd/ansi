/// The app's toasts. A toast reports an act that did not happen; a state that
/// stays wrong is the sync banner's.
///
/// Position and width are set once on the theme's toaster style. Every toast
/// swipes away sideways as well as down ([_showAnsiToast]). A toast needs
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

/// Shows an [FToast] that swipes away left, right or down.
///
/// Forui lets a bottom-centre toast swipe only down, and a toast gets one
/// horizontal direction at most — but a thumb flicks a toast sideways. Forui
/// keeps the downward swipe; a [Dismissible] adds both horizontal ones, then
/// hands the toast back to Forui to remove. No resize: the toast is already
/// off-screen, and a resizing [Dismissible] asserts if it is still in the tree.
void _showAnsiToast(
  BuildContext context, {
  required Widget icon,
  required Widget title,
  FToastVariant variant = FToastVariant.primary,
  Widget? description,
  Widget Function(BuildContext context, FToasterEntry entry)? suffixBuilder,
}) {
  showRawFToast(
    context: context,
    variant: variant,
    duration: _toastDuration,
    builder: (context, entry) => Dismissible(
      key: ObjectKey(entry),
      resizeDuration: null,
      onDismissed: (_) => entry.dismiss(),
      child: FToast(
        variant: variant,
        icon: icon,
        title: title,
        description: description,
        suffix: suffixBuilder?.call(context, entry),
      ),
    ),
  );
}

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
  _showAnsiToast(
    context,
    variant: FToastVariant.destructive,
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
  _showAnsiToast(
    context,
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

/// Says that a link was copied, where copying was the whole act.
///
/// An exception to "no success toasts", like the undo toast: a copy changes
/// nothing on screen, so without a word the tap would read as dead. [what]
/// names the thing copied, in the user's own nouns. Primary, not destructive.
void showAnsiCopiedToast(BuildContext context, {required String what}) {
  _showAnsiToast(
    context,
    icon: const Icon(FLucideIcons.link),
    title: Text('$what copied.'),
  );
}

/// Reports that something the user removed is recoverable, and carries the
/// undo. An exception to "no success toasts"
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
  _showAnsiToast(
    context,
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
