/// The app's only way to open a Forui sheet or dialog
/// (`test/shared/ansi_modals_test.dart` holds that).
///
/// Modals open on the shell navigator ([ansiShellNavigatorKey]): a branch
/// navigator would leave the bottom bar live beside the barrier, and the
/// root would put a modal above pages pushed from it. From
/// [AnsiLayout.medium] up a sheet is presented as a centred dialog.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/router/app_router.dart';
import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import 'ansi_layout.dart';

/// The widest a sheet-turned-dialog is drawn; narrower than the measure.
const double kAnsiDialogWidth = 560;

/// The tallest a sheet-turned-dialog is drawn, and the fixed height of the
/// search-driven ones, so a long list scrolls inside the dialog.
const double kAnsiDialogHeight = 640;

/// The navigator a modal opens on, as a context to hand Forui: the shell
/// navigator's overlay, or the caller's context with the root requested when
/// no shell is mounted.
({BuildContext context, bool root}) _modalHost(BuildContext context) {
  final overlay = ansiShellNavigatorKey.currentState?.overlay;
  return overlay == null
      ? (context: context, root: true)
      : (context: overlay.context, root: false);
}

/// Shows a modal sheet above the whole shell: bottom-up on a phone, a
/// centred dialog from [AnsiLayout.medium] up. [side] applies to the sheet
/// form only.
Future<T?> showAnsiSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  FLayout side = FLayout.btt,
}) {
  // A focused field behind the sheet would scroll its page to the caret each
  // time the view metrics move, so drop focus first.
  FocusManager.instance.primaryFocus?.unfocus();
  final host = _modalHost(context);
  if (AnsiLayout.of(context) == AnsiLayout.compact) {
    return showFSheet<T>(
      context: host.context,
      useRootNavigator: host.root,
      side: side,
      // Null lifts Forui's 9/16 cap: sheets size to their content.
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
      // Clip the content to the surface's rounded corners.
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

/// Which surface a sheet's content is drawn on, for
/// `shared/ansi_sheet_shell.dart`'s bottom pad. Absent means the sheet form.
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

/// Asks a yes/no question: true when the reader took [confirm], false on
/// [cancel] or a dismissal.
///
/// [destructive] paints the confirm red. [caveat] is a mono aside under the
/// prose, with [caveatLabel] naming it.
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

/// A refusal that names why; returns true when the reader took the [door].
/// With no door it is an OK-only note.
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
