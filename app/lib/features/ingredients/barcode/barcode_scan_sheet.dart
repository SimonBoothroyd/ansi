/// The barcode scan sheet.
///
/// Two ways in, always: the camera reticle, and a typed number beneath it. The
/// typed field is the no-permission path, the scuffed-label path, and the only
/// path the iOS Simulator can use. Every failure returns to this surface with
/// the reason under it, never a dialog. The sheet resolves with an
/// [IngredientDraft] and writes nothing.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_sheet_shell.dart';
import 'ingredient_draft.dart';
import 'off_lookup.dart';

/// Builds the pane above the typed field, reporting each decoded code. Defaults
/// to the plugin's preview; injectable because the plugin needs a real camera,
/// so widget tests pass a pane that reports codes on command.
typedef BarcodeCameraPane =
    Widget Function(BuildContext context, ValueChanged<String> onCode);

/// The scan surface. Call `scanBarcodeForDraft` (barcode_add.dart) rather
/// than building this directly — it owns the presentation and the pop value.
class BarcodeScanSheet extends HookWidget {
  const BarcodeScanSheet({
    required this.onResolved,
    required this.onDismiss,
    this.lookup,
    this.cameraPane,
    super.key,
  });

  /// Called once, with the draft the user is taking to the form.
  final ValueChanged<IngredientDraft> onResolved;

  /// Called when the user closes without a draft.
  final VoidCallback onDismiss;

  /// The Open Food Facts reader. Defaults to a real [OffLookup] owned and
  /// closed by this widget.
  final OffLookup? lookup;

  final BarcodeCameraPane? cameraPane;

  @override
  Widget build(BuildContext context) {
    final injected = lookup;
    final client = useMemoized(() => injected ?? OffLookup(), [injected]);
    useEffect(() {
      // Only a client we made is ours to close.
      return injected == null ? client.close : null;
    }, [client]);

    final typed = useState('');
    final busy = useState(false);
    final failure = useState<BarcodeLookupFailed?>(null);
    // Single-fire: the detector reports the same barcode every frame. The first
    // attempt claims the code, and only "Try again" spends another request.
    final attempted = useRef<String?>(null);

    Future<void> run(String raw, {required bool fromCamera}) async {
      if (busy.value) return;
      final code = normalizeBarcode(raw);
      if (code == null) return;
      if (fromCamera && attempted.value == code) return;
      attempted.value = code;
      busy.value = true;
      failure.value = null;
      final result = await client.lookup(code);
      // The sheet can be dismissed while the GET is in flight; touching hook
      // state then throws (the same guard every sibling sheet uses).
      if (!context.mounted) return;
      busy.value = false;
      switch (result) {
        case BarcodeFound(:final draft):
          onResolved(draft);
        case final BarcodeLookupFailed failed:
          failure.value = failed;
      }
    }

    final code = normalizeBarcode(typed.value);
    final failed = failure.value;

    return AnsiSheetShell(
      title: 'Scan a barcode',
      onDismiss: onDismiss,
      scrollable: true,
      children: [
        const SizedBox(height: 14),
        _CameraFrame(
          child: (cameraPane ?? _defaultCameraPane)(
            context,
            (c) => run(c, fromCamera: true),
          ),
        ),
        const SizedBox(height: 16),
        Text('OR TYPE THE NUMBER', style: ansiLabel()),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FTextField(
                hint: '13 digits',
                keyboardType: TextInputType.number,
                control: FTextFieldControl.managed(
                  onChange: (v) => typed.value = v.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FButton(
              size: FButtonSizeVariant.sm,
              onPress: code == null || busy.value
                  ? null
                  : () => run(code, fromCamera: false),
              child: const Text('Look up'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (busy.value)
          Text(
            'Looking it up…',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          )
        else if (typed.value.trim().isNotEmpty && code == null)
          Text(
            'a barcode is 8 to 14 digits — the small ones printed beside the '
            'bars count too',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        if (failed != null) ...[
          const SizedBox(height: 12),
          BarcodeFailurePanel(
            failure: failed,
            onRetry: () => run(failed.barcode, fromCamera: false),
            onAddByHand: () =>
                onResolved(IngredientDraft.blank(barcode: failed.barcode)),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'Product data from Open Food Facts · ODbL',
          textAlign: TextAlign.center,
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
      ],
    );
  }
}

/// The camera preview. Never built in a browser: `mobile_scanner`'s web build
/// fetches its detector from a CDN at run time. The sheet draws its "no camera"
/// state there, and `ingredient_detail_view.dart` does not offer the door on
/// the web either.
Widget _defaultCameraPane(BuildContext context, ValueChanged<String> onCode) =>
    kIsWeb
    ? const CameraOffNotice(permissionDenied: false)
    : _MobileScannerPane(onCode: onCode);

/// The plugin's preview, with a permission refusal rendered as a designed state
/// rather than a crash.
class _MobileScannerPane extends StatefulWidget {
  const _MobileScannerPane({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_MobileScannerPane> createState() => _MobileScannerPaneState();
}

class _MobileScannerPaneState extends State<_MobileScannerPane> {
  // Only the linear product symbologies a grocery pack carries — narrowing
  // the formats keeps the detector off QR codes on the same shelf label.
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      errorBuilder: (context, error) => CameraOffNotice(
        // Anything else (no camera on this device, a busy camera) is not the
        // user's permission to fix, so it does not offer the Settings door.
        permissionDenied:
            error.errorCode == MobileScannerErrorCode.permissionDenied,
      ),
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null && raw.isNotEmpty) {
            widget.onCode(raw);
            return;
          }
        }
      },
    );
  }
}

/// The reticle: a fixed-height window with a rounded inner frame and a hint
/// under it. Painted, because a [Row] of [Expanded] inside a [Stack] collapses
/// to nothing.
class _CameraFrame extends StatelessWidget {
  const _CameraFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 190,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ColoredBox(
              color: AnsiColors.ink,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 220,
                        height: 96,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AnsiColors.surface,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'line up the barcode',
          textAlign: TextAlign.center,
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
      ],
    );
  }
}

/// "Ansi can't open the camera": shown in place of the preview, with the typed
/// field below still live. Public so widget tests can assert the copy.
class CameraOffNotice extends HookWidget {
  const CameraOffNotice({
    required this.permissionDenied,
    this.canOpenSettings = _canOpenAppSettings,
    super.key,
  });

  final bool permissionDenied;

  /// Whether this platform can open the app's settings pane. The button is
  /// drawn only when it can. Injectable for tests.
  final Future<bool> Function() canOpenSettings;

  @override
  Widget build(BuildContext context) {
    // Starts false: a button that appears a frame late is honest, and one
    // drawn on a hunch and then removed is a flicker.
    final canOpen =
        useFuture(
          useMemoized(canOpenSettings, [canOpenSettings]),
          initialData: false,
        ).data ??
        false;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Ansi can't open the camera",
            textAlign: TextAlign.center,
            style: ansiSans(size: 14, color: AnsiColors.surface),
          ),
          const SizedBox(height: 6),
          Text(
            permissionDenied
                ? 'Camera access is turned off for Ansi. Turn it on in '
                      'Settings, or type the barcode below — both end in the '
                      'same place.'
                : 'No camera is available here. Type the barcode below — it '
                      'ends in the same place.',
            textAlign: TextAlign.center,
            style: ansiMono(size: 10, color: AnsiColors.line),
          ),
          if (permissionDenied && canOpen) ...[
            const SizedBox(height: 10),
            FButton(
              variant: FButtonVariant.outline,
              size: FButtonSizeVariant.sm,
              onPress: _openSettings,
              child: const Text('Open Settings'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Only iOS opens the app's settings pane for this scheme. Where this answers
/// false the button is not drawn.
Future<bool> _canOpenAppSettings() async {
  try {
    return await canLaunchUrl(_appSettings);
  } on Object {
    // No launcher on this platform (or none registered, as in a widget test).
    return false;
  }
}

final _appSettings = Uri.parse('app-settings:');

/// Opens that pane. A refusal is swallowed: the typed field always works.
Future<void> _openSettings() async {
  try {
    await launchUrl(_appSettings);
  } on PlatformException {
    // nothing to do — the typed field below is the working path
  }
}

/// The lookup's failure states. Each offers a way on.
class BarcodeFailurePanel extends StatelessWidget {
  const BarcodeFailurePanel({
    required this.failure,
    required this.onRetry,
    required this.onAddByHand,
    super.key,
  });

  final BarcodeLookupFailed failure;

  /// Spends another request on the same code — the only thing that may,
  /// since the detector's repeat frames are suppressed after the first try.
  final VoidCallback onRetry;

  /// Leaves with a blank draft carrying the code (the not-found exit).
  final VoidCallback onAddByHand;

  @override
  Widget build(BuildContext context) {
    final notFound = failure.reason == BarcodeLookupFailure.notFound;
    final (title, body) = switch (failure.reason) {
      BarcodeLookupFailure.notFound => (
        "${failure.barcode} isn't in Open Food Facts",
        'Nobody has added this product yet. Add it by hand — the name and '
            'macros are the only parts a barcode was going to fill in anyway.',
      ),
      BarcodeLookupFailure.offline => (
        "Can't reach Open Food Facts",
        'The lookup needs a connection. Everything else on the form works '
            "offline and syncs when you're back.",
      ),
      BarcodeLookupFailure.unavailable => (
        'Open Food Facts turned us away',
        'It limits how often it will answer. Wait a moment and try again, or '
            'fill the form in by hand.',
      ),
      BarcodeLookupFailure.malformed => (
        "Open Food Facts sent something we can't read",
        "This isn't a missing product — the answer came back in a shape we "
            'do not understand. Try again, or fill the form in by hand.',
      ),
      BarcodeLookupFailure.invalidCode => (
        "That isn't a barcode",
        'A product barcode is 8 to 14 digits. Check the number and try again.',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.surface,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: ansiSans(size: 14, weight: FontWeight.w500)),
          const SizedBox(height: 5),
          Text(body, style: ansiMono(size: 10.5, color: AnsiColors.muted)),
          const SizedBox(height: 10),
          FButton(
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            onPress: notFound ? onAddByHand : onRetry,
            child: Text(notFound ? 'Add it by hand' : 'Try again'),
          ),
          if (!notFound) ...[
            const SizedBox(height: 6),
            FButton(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              onPress: onAddByHand,
              child: const Text('Add it by hand'),
            ),
          ],
        ],
      ),
    );
  }
}
