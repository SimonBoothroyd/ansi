/// The app's toasts — the transient half of the error posture.
///
/// **A toast reports an act. A banner reports a state.** If the user did
/// something and it didn't happen, it is a toast, with a way to try again. If
/// something is *currently* wrong and stays wrong until acted on, it is the
/// sync banner, not this.
///
/// A toast sits **bottom-centre**, above the tab bar, so it never covers a
/// header action; it needs an `FToaster` ancestor, which `app.dart` installs
/// once beside `FTheme`. A widget test that pumps a bare screen must use
/// `pumpAnsiApp` (`test/helpers/pump_app.dart`) or `showFToast` throws.
///
/// The words are the design's, not a developer's: never "Error", never
/// "Failed", never an exception's `toString()`. See
/// `docs/design-docs/errors-and-sync-health.md`.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';

/// Long enough to read a sentence and reach for Retry; short enough that a
/// failure the user has already moved past does not follow them around.
const _toastDuration = Duration(seconds: 6);

/// A context below the app's one `FToaster`, for a caller that has none of its
/// own — the zone handler, which runs outside the widget tree entirely.
///
/// `app.dart` mounts it inside the toaster; it is null until the first frame.
final ansiToastAnchor = GlobalKey(debugLabel: 'ansi toast anchor');

/// Reports that one thing the user asked for did not happen.
///
/// [what] is a lowercase verb phrase in the user's own noun completing
/// "Couldn't ___." — "save the recipe", "add Tuesday's dinner", "delete that
/// section". Never a table name, never a method name.
///
/// [onRetry] runs the same write again. It is offered by default because a
/// local write that threw once usually succeeds on a second attempt; pass null
/// only where re-running would be wrong.
void showAnsiFailureToast(
  BuildContext context, {
  required String what,
  String? reassurance,
  VoidCallback? onRetry,
}) {
  showFToast(
    context: context,
    variant: FToastVariant.destructive,
    alignment: FToastAlignment.bottomCenter,
    duration: _toastDuration,
    icon: const Icon(FLucideIcons.circleAlert),
    title: Text('Couldn’t $what.'),
    description: reassurance == null
        ? null
        : Text(reassurance, style: ansiMonoInherit(size: 11)),
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

/// Reports that something threw where nobody was expecting it.
///
/// Primary, not destructive: this is information, not alarm — the app kept
/// going, and a user action that failed already had its own honest surface via
/// [showAnsiFailureToast]. The rate limiting lives in the caller
/// (`core/observability/crash_sink.dart`), because an exception thrown inside
/// `build` repeats every frame.
void showAnsiProblemToast(
  BuildContext context, {
  required VoidCallback onCopyDetails,
}) {
  showFToast(
    context: context,
    alignment: FToastAlignment.bottomCenter,
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

/// Reports that something the user removed is **recoverable**, and offers the
/// way back.
///
/// This is the one deliberate exception to "no success toasts"
/// (`docs/design-docs/errors-and-sync-health.md`, D1): it is not reporting
/// that a write succeeded — it is **carrying the undo**, which is the only
/// reason it exists. Week v3 E3 spends it to buy the confirm dialog it
/// refuses: a `−` on every dish row of a resting screen is defensible only
/// because the act is trivially reversible, and this is what makes it so.
///
/// [what] is what went, in the user's own nouns — "Removed Chicken Curry from
/// Monday." [detail] names what would come back ("dinner · Ada & Jun · 1¾
/// portions"), because an undo you cannot audit is a promise, not a control.
///
/// Primary, not destructive: nothing is wrong. The red is reserved for
/// [showAnsiFailureToast], where something actually failed.
void showAnsiUndoToast(
  BuildContext context, {
  required String what,
  required VoidCallback onUndo,
  String? detail,
}) {
  showFToast(
    context: context,
    alignment: FToastAlignment.bottomCenter,
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
