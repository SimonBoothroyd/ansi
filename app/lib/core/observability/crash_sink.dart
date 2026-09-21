/// Where an unhandled exception ends up.
///
/// `bootstrap.dart`'s zone handler reports here. User writes already go
/// through `shared/write.dart`, so what reaches this is a genuine bug. There
/// is no reporting service; adding one is another [CrashSink] and one
/// provider override.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/ansi_toast.dart';
import '../../shared/describe_failure.dart';

part 'crash_sink.g.dart';

/// At most one crash toast per this long: an exception thrown inside `build`
/// repeats every frame.
const crashToastInterval = Duration(seconds: 10);

abstract interface class CrashSink {
  /// An exception nobody handled.
  void report(Object error, StackTrace stack);

  /// An exception a caller did handle (e.g. `guardedWrite`): logged, never
  /// surfaced a second time.
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
class ToastCrashSink implements CrashSink {
  ToastCrashSink(this._anchor, {DateTime Function() clock = DateTime.now})
    : _clock = clock;

  /// A context below the app's `FToaster`. A function, because the sink is
  /// built before the first frame.
  final BuildContext? Function() _anchor;

  final DateTime Function() _clock;

  DateTime? _lastShown;

  /// Everything since the last Copy details; the limiter suppresses toasts,
  /// never reports. Read when the button is tapped.
  final List<String> _pending = [];

  /// The cap on [_pending]; the oldest go first.
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

/// Where the zone handler and `guardedWrite` report. [NoopCrashSink] by
/// default; `bootstrap.dart` overrides it with a [ToastCrashSink].
@Riverpod(keepAlive: true)
CrashSink crashSink(Ref ref) => const NoopCrashSink();
