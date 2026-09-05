/// Modal surfaces — the app's only way to open a Forui sheet or dialog.
///
/// Under the tab shell (`ansi_tab_shell.dart`) a tab screen sits inside its
/// **branch** Navigator, and Forui's `showFSheet`/`showFDialog` default to
/// `useRootNavigator: false`. A modal opened that way is pushed *inside* the
/// branch, so its barrier stops at the branch's bounds and the bottom nav bar
/// stays lit and tappable beside it — you can switch tabs behind an open sheet.
///
/// So every modal in the app goes on the **root** Navigator, above the shell.
/// One wrapper each rather than the same two arguments at every call site, and
/// a structural test (`test/shared/ansi_modals_test.dart`) fails the build if a
/// view reaches for the Forui function directly again.
///
/// The app's sheet geometry is baked in here too, because every sheet asks for
/// the same thing: bottom-up, no height cap, safe-area padded.
///
/// **Popping from inside.** The modal is the top route of the root Navigator,
/// so `Navigator.of(context).pop(result)` from the builder's context still
/// dismisses the modal itself — it is the nearest route either way. What
/// changes is only which Navigator owns it.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';

/// Shows a modal sheet above the whole shell, bottom-up by default.
///
/// [side] is the only geometry left open: `FLayout.btt` is what every sheet in
/// the app wants, and a future side sheet should still come through here.
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
  // the root navigator: one door, one rule.
  FocusManager.instance.primaryFocus?.unfocus();
  return showFSheet<T>(
    context: context,
    useRootNavigator: true,
    side: side,
    // Null lifts Forui's 9/16 cap: these sheets size to their content and the
    // tall ones (pickers, the barcode scanner) need the room.
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: builder,
  );
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
}) =>
    showFDialog<T>(context: context, useRootNavigator: true, builder: builder);

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
      title: Text(title, style: ansiSerif(size: 20)),
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
      title: Text(title, style: ansiSerif(size: 20)),
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
