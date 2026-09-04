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

/// Shows a modal sheet above the whole shell, bottom-up by default.
///
/// [side] is the only geometry left open: `FLayout.btt` is what every sheet in
/// the app wants, and a future side sheet should still come through here.
Future<T?> showAnsiSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  FLayout side = FLayout.btt,
}) => showFSheet<T>(
  context: context,
  useRootNavigator: true,
  side: side,
  // Null lifts Forui's 9/16 cap: these sheets size to their content and the
  // tall ones (pickers, the barcode scanner) need the room.
  mainAxisMaxRatio: null,
  useSafeArea: true,
  builder: builder,
);

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
