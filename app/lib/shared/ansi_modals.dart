/// Modal surfaces — the app's only way to open a Forui sheet or dialog.
///
/// Under the tab shell (`ansi_tab_shell.dart`) a tab screen sits inside its
/// **branch** Navigator, and Forui's `showFSheet`/`showFDialog` default to
/// `useRootNavigator: false`. A modal opened that way is pushed *inside* the
/// branch, so its barrier stops at the branch's bounds and the bottom nav bar
/// stays lit and tappable beside it — you can switch tabs behind an open sheet.
///
/// So every modal in the app goes on the app's **shell** Navigator
/// ([ansiShellNavigatorKey]) — the one navigator that holds the tab shell and
/// every page pushed over it, above all four branches. One wrapper each rather
/// than the same argument at every call site, and a structural test
/// (`test/shared/ansi_modals_test.dart`) fails the build if a view reaches for
/// the Forui function directly again.
///
/// **Not the root navigator above that**, which would put the modal above the
/// pushed pages too: a picker that pushes the flesh-out form over its own sheet
/// and then awaits the row it made (the add-new chain) needs the form to land
/// ON the sheet, and a page and a modal stack in a knowable order only when
/// they share a navigator. With no shell navigator mounted — a gate screen, a
/// test with a bare router — a modal falls back to the root, which in that tree
/// is the same navigator by another name.
///
/// **A sheet on a phone is a dialog on a desk.** From [AnsiLayout.medium] up
/// there is no bottom edge worth rising from and nothing to gain by spanning
/// the window, so the same builder is presented centred instead: sized to its
/// content up to 560 wide, or as a fixed pane for the search-driven sheets that
/// ask for a share of the height. One door, two presentations, every call site
/// and every return value unchanged.
///
/// The app's sheet geometry is baked in here too, because every sheet asks for
/// the same thing: bottom-up, no height cap, safe-area padded.
///
/// **Popping from inside.** The modal is the top route of the shell Navigator,
/// so `Navigator.of(context).pop(result)` from the builder's context still
/// dismisses the modal itself — it is the nearest route either way. What
/// changes is only which Navigator owns it.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/router/app_router.dart';
import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import 'ansi_layout.dart';

/// The widest a sheet-turned-dialog is drawn.
///
/// Narrower than the measure on purpose: a dialog is a question over a page,
/// and one as wide as the page it covers reads as a second page.
const double kAnsiDialogWidth = 560;

/// The tallest a sheet-turned-dialog is drawn — and the height the
/// search-driven ones take, so a long vocabulary scrolls inside the dialog
/// instead of pushing the search field off the top.
const double kAnsiDialogHeight = 640;

/// The navigator a modal opens on, as a context to hand Forui.
///
/// The shell navigator's overlay when the app is mounted (`Navigator.of` from
/// inside a navigator's overlay returns that navigator, which is how the
/// `HostContext` in `shared/write.dart` reaches the root), and otherwise the
/// caller's own context with the root asked for by name.
({BuildContext context, bool root}) _modalHost(BuildContext context) {
  final overlay = ansiShellNavigatorKey.currentState?.overlay;
  return overlay == null
      ? (context: context, root: true)
      : (context: overlay.context, root: false);
}

/// Shows a modal sheet above the whole shell — bottom-up on a phone, a centred
/// dialog from [AnsiLayout.medium] up.
///
/// [side] is the only geometry left open: `FLayout.btt` is what every sheet in
/// the app wants, and a future side sheet should still come through here. It is
/// about the sheet form only; a dialog has no side to come from.
Future<T?> showAnsiSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  FLayout side = FLayout.btt,
}) {
  // **A sheet takes the screen, so the field behind it stops asking for it.**
  //
  // A focused editable asks its enclosing scrollable to show its caret every
  // time the view metrics move — and opening a sheet moves them twice, once
  // each way. On the import review, which is one long ListView with the title
  // field at the very top, that is enough to throw the page back to the title
  // and take the card being corrected with it. Dropping focus here rather
  // than at each call site is the same argument this file already makes about
  // the shell navigator: one door, one rule.
  FocusManager.instance.primaryFocus?.unfocus();
  final host = _modalHost(context);
  if (AnsiLayout.of(context) == AnsiLayout.compact) {
    return showFSheet<T>(
      context: host.context,
      useRootNavigator: host.root,
      side: side,
      // Null lifts Forui's 9/16 cap: these sheets size to their content and the
      // tall ones (pickers, the barcode scanner) need the room.
      mainAxisMaxRatio: null,
      useSafeArea: true,
      builder: builder,
    );
  }
  return showFDialog<T>(
    context: host.context,
    useRootNavigator: host.root,
    builder: (context, style, animation) => FDialog.raw(
      animation: animation,
      // The sheet's own paper ground and the dialog's ring are the same
      // surface, so the content is clipped to it rather than painting over the
      // corners.
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(
        maxWidth: kAnsiDialogWidth,
        maxHeight: kAnsiDialogHeight,
      ),
      builder: (context, style) =>
          AnsiModalSurface(dialog: true, child: builder(context)),
    ),
  );
}

/// Which surface a sheet's content is being drawn on, for the one widget that
/// has to care: `shared/ansi_sheet_shell.dart`, whose bottom pad answers a
/// keyboard and a home indicator that a centred dialog has neither of.
///
/// Absent means the sheet form — including a sheet pumped straight into a test.
class AnsiModalSurface extends InheritedWidget {
  const AnsiModalSurface({
    required this.dialog,
    required super.child,
    super.key,
  });

  /// True when the content is inside a dialog rather than a bottom sheet.
  final bool dialog;

  static bool isDialog(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AnsiModalSurface>()?.dialog ??
      false;

  @override
  bool updateShouldNotify(AnsiModalSurface old) => dialog != old.dialog;
}

/// Shows a dialog above the whole shell.
Future<T?> showAnsiDialog<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    FDialogStyle style,
    Animation<double> animation,
  )
  builder,
}) {
  final host = _modalHost(context);
  return showFDialog<T>(
    context: host.context,
    useRootNavigator: host.root,
    builder: builder,
  );
}

/// Asks a yes/no question and waits for the answer: true when the reader took
/// [confirm], false when they took [cancel] **or dismissed** — silence is not
/// consent, so every caller reads a dismissal as the no.
///
/// The board draws one confirm dialog: serif 20 over sans 13 muted, the
/// affirmative on the **left** and the way out beside it. Passing the wording
/// rather than a widget tree is what keeps the nine questions the app asks
/// looking like one question asked nine times.
///
/// [destructive] paints the confirm red — for a delete, not for every write.
/// [caveat] is the mono aside some questions carry under the prose ("this
/// can't be undone here"), with [caveatLabel] naming it above.
Future<bool> askAnsi(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  String cancel = 'Cancel',
  bool destructive = false,
  String? caveat,
  String? caveatLabel,
}) async {
  final answered = await showAnsiDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      title: Text(title, style: ansiSerif(size: AnsiType.heading)),
      body: _dialogBody(body, caveat: caveat, caveatLabel: caveatLabel),
      actions: [
        FButton(
          variant: destructive
              ? FButtonVariant.destructive
              : FButtonVariant.primary,
          onPress: () => Navigator.of(context).pop(true),
          child: Text(confirm),
        ),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(false),
          child: Text(cancel),
        ),
      ],
    ),
  );
  return answered ?? false;
}

/// A refusal that names why, and returns true when the reader took the [door].
///
/// A refusal without a door is a wall in front of the one action that clears
/// it, so the door is the point: the dialog that says a book still holds 42
/// recipes is also the way to move them. With no door it is an OK-only note.
Future<bool> refuseAnsi(
  BuildContext context, {
  required String title,
  required String body,
  String? door,
}) async {
  final took = await showAnsiDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      title: Text(title, style: ansiSerif(size: AnsiType.heading)),
      body: _dialogBody(body),
      actions: [
        if (door != null)
          FButton(
            onPress: () => Navigator.of(context).pop(true),
            child: Text(door),
          ),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(false),
          child: Text(door == null ? 'OK' : 'Cancel'),
        ),
      ],
    ),
  );
  return took ?? false;
}

Widget _dialogBody(String body, {String? caveat, String? caveatLabel}) =>
    Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(body, style: ansiSans(size: 13, color: AnsiColors.muted)),
          if (caveatLabel != null) ...[
            const SizedBox(height: 12),
            Text(caveatLabel, style: ansiLabel()),
          ],
          if (caveat != null) ...[
            SizedBox(height: caveatLabel == null ? 10 : 4),
            Text(
              caveat,
              style: ansiMono(
                size: 11,
                color: AnsiColors.muted,
              ).copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
