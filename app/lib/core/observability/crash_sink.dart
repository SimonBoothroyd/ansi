/// The one seam between "something threw" and "someone finds out".
///
/// `bootstrap.dart`'s zone handler ends here. Making it visible is only
/// tolerable because every user-initiated repository write already goes through
/// the app's one write door (`shared/write.dart`) — so whatever still reaches
/// here is a genuine bug rather than an ordinary failure, and its
/// signal-to-noise is worth a toast.
///
/// **No reporting service, deliberately.** Sentry or Crashlytics is a network
/// dependency, a privacy surface, a build-time key and a vendor, for a
/// two-person household where the two people can text each other. Adding one
/// later means writing a third [CrashSink] and overriding one provider in
/// `bootstrap.dart` — nothing else in the app moves.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/ansi_toast.dart';
import '../../shared/describe_failure.dart';

part 'crash_sink.g.dart';

/// At most one crash toast per this long. An exception thrown inside `build`
/// repeats every frame, and a wall of toasts is worse than the silence it
/// replaced.
const crashToastInterval = Duration(seconds: 10);

abstract interface class CrashSink {
  /// An exception nobody handled — the zone handler's last resort.
  void report(Object error, StackTrace stack);

  /// An exception a caller DID handle (e.g. `guardedWrite`), logged so it is
  /// findable, never surfaced a second time. Otherwise one failed write
  /// produces both "Couldn't save the recipe" and "Something went wrong",
  /// which is the app arguing with itself.
  void note(Object error, StackTrace stack);
}

/// Keeps nothing and shows nothing. What tests use.
class NoopCrashSink implements CrashSink {
  const NoopCrashSink();

  @override
  void report(Object error, StackTrace stack) {}

  @override
  void note(Object error, StackTrace stack) {}
}

/// The default: a quiet, non-blocking toast with the detail on the clipboard.
///
/// Primary, not destructive — it reads as information rather than alarm,
/// because the app did keep going and the user may not have been the one who
/// caused it. A full-screen error page would be a regression: the smoke tests
/// already filter a family of framework assertions
/// (`integration_test/support/drive.dart`), and those are noise, not
/// catastrophe.
class ToastCrashSink implements CrashSink {
  ToastCrashSink(this._anchor, {DateTime Function() clock = DateTime.now})
    : _clock = clock;

  /// Where to raise the toast: a context BELOW the app's one `FToaster`.
  /// A function rather than a context, because the sink is built before the
  /// first frame and the anchor only exists once there is something on screen.
  final BuildContext? Function() _anchor;

  final DateTime Function() _clock;

  DateTime? _lastShown;

  /// Everything since the last Copy details, so one toast can speak for a whole
  /// burst: the limiter suppresses the *toasts*, never the *reports*.
  ///
  /// Read when the button is tapped rather than when the toast is raised —
  /// which is the useful moment, since a build loop keeps throwing while the
  /// toast sits there.
  final List<String> _pending = [];

  /// A throwing `build` can produce thousands before anyone taps. The oldest go
  /// first: the newest are the ones still happening.
  static const _maxPending = 20;

  @override
  void note(Object error, StackTrace stack) =>
      debugPrint('handled: $error\n$stack');

  @override
  void report(Object error, StackTrace stack) {
    debugPrint('Uncaught: $error\n$stack');
    _pending.add(failureDetails(error, stack));
    if (_pending.length > _maxPending) _pending.removeAt(0);

    final now = _clock();
    final last = _lastShown;
    if (last != null && now.difference(last) < crashToastInterval) return;
    _lastShown = now;

    final context = _anchor();
    if (context == null) return; // nothing on screen to toast into yet
    showAnsiProblemToast(context, onCopyDetails: _copyPending);
  }

  void _copyPending() {
    final details = _pending.join('\n\n---\n\n');
    _pending.clear();
    unawaited(Clipboard.setData(ClipboardData(text: details)));
  }
}

/// Where the zone handler and `guardedWrite` speak.
///
/// Overridden in `bootstrap.dart` with a [ToastCrashSink] anchored under the
/// app's toaster. The default is [NoopCrashSink], which is also what a test
/// wanting silence gets for free.
@Riverpod(keepAlive: true)
CrashSink crashSink(Ref ref) => const NoopCrashSink();
