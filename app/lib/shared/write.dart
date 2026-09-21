/// The one door every user-initiated repository write goes through, so a
/// write that throws shows a toast instead of failing silently. Held by
/// `test/structure/no_bare_repo_write_test.dart`.
///
/// The one exception is `ensureDefaultBook` in `core/sync/session.dart`,
/// which runs before there is a screen and fails as a `SessionError`.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/observability/crash_sink.dart';
import '../core/router/app_router.dart';
import 'ansi_toast.dart';

/// Runs one user-initiated write and reports its failure.
///
/// Awaits [action] and returns its value. On a throw it shows the failure
/// toast, "Couldn't [what].", with a Retry that re-runs [action], and returns
/// null; it never rethrows. [action] is a closure, not a future, so Retry can
/// re-run it. [what] is a lowercase verb phrase in the user's words ("save
/// the recipe"). Nothing is shown when [context] is already unmounted; the
/// failure is still logged.
Future<T?> guardedWrite<T>(
  BuildContext context,
  WidgetRef ref, {
  required String what,
  required Future<T> Function() action,
  bool retryable = true,
}) {
  // Resolved before the await: `ref` is unsafe once its widget is gone.
  final crashes = ref.read(crashSinkProvider);
  return _attempt(
    context,
    crashes,
    what: what,
    action: action,
    retryable: retryable,
  );
}

Future<T?> _attempt<T>(
  BuildContext context,
  CrashSink crashes, {
  required String what,
  required Future<T> Function() action,
  bool retryable = true,
}) async {
  try {
    return await action();
  } on Object catch (error, stack) {
    // `note`, not `report`: the toast below already tells the user.
    crashes.note(error, stack);
    if (!context.mounted) return null;
    showAnsiFailureToast(
      context,
      what: what,
      onRetry: retryable
          ? () => unawaited(
              _attempt(context, crashes, what: what, action: action),
            )
          : null,
    );
    return null;
  }
}

/// [guardedWrite] for a `Future<void>` write whose caller branches on
/// success. Returns true when the write landed.
Future<bool> guardedWriteOk(
  BuildContext context,
  WidgetRef ref, {
  required String what,
  required Future<void> Function() action,
  bool retryable = true,
}) async =>
    await guardedWrite<bool>(
      context,
      ref,
      what: what,
      action: () async {
        await action();
        return true;
      },
      retryable: retryable,
    ) ??
    false;

/// A context that outlives the row that opened a sheet: the overlay every
/// modal opens on. Resolve it before the first `await` in a flow that
/// continues after a sheet or dialog.
///
/// A sheet's keyboard can scroll the opening row out and unmount it.
/// Riverpod 3 throws on a `WidgetRef` used after that, and a
/// `context.mounted` bail drops the write the user confirmed. Held by
/// `test/structure/no_ref_after_await_test.dart`.
HostContext hostContextOf(BuildContext context) => HostContext(
  (ansiShellNavigatorKey.currentState?.overlay ??
          Navigator.of(context, rootNavigator: true).overlay!)
      .context,
);

/// A context that is safe across async gaps; see [hostContextOf]. Its own
/// type so `use_build_context_synchronously` is answered once, not with an
/// `ignore` at every call site.
extension type const HostContext(BuildContext context) {}

/// [guardedWrite] for a write that lands after an awaited sheet. [container]
/// (`ProviderScope.containerOf(context, listen: false)`) and [host]
/// ([hostContextOf]) are captured before the await.
Future<T?> guardedWriteFrom<T>(
  ProviderContainer container,
  HostContext host, {
  required String what,
  required Future<T> Function() action,
  bool retryable = true,
}) => _attempt(
  host.context,
  container.read(crashSinkProvider),
  what: what,
  action: action,
  retryable: retryable,
);

/// [guardedWriteOk] in the [guardedWriteFrom] form.
Future<bool> guardedWriteOkFrom(
  ProviderContainer container,
  HostContext host, {
  required String what,
  required Future<void> Function() action,
  bool retryable = true,
}) async =>
    await guardedWriteFrom<bool>(
      container,
      host,
      what: what,
      action: () async {
        await action();
        return true;
      },
      retryable: retryable,
    ) ??
    false;

/// Sugar for [guardedWriteFrom]: `container.write(host, 'rename that
/// book', …)`. The structural write check recognises it as the same door.
extension AnsiContainerWrite on ProviderContainer {
  Future<T?> write<T>(
    HostContext host,
    String what,
    Future<T> Function() action, {
    bool retryable = true,
  }) => guardedWriteFrom(
    this,
    host,
    what: what,
    action: action,
    retryable: retryable,
  );

  Future<bool> writeOk(
    HostContext host,
    String what,
    Future<void> Function() action, {
    bool retryable = true,
  }) => guardedWriteOkFrom(
    this,
    host,
    what: what,
    action: action,
    retryable: retryable,
  );
}

/// Sugar for [guardedWrite] and [guardedWriteOk].
extension AnsiWrite on WidgetRef {
  Future<T?> write<T>(
    BuildContext context,
    String what,
    Future<T> Function() action, {
    bool retryable = true,
  }) => guardedWrite(
    context,
    this,
    what: what,
    action: action,
    retryable: retryable,
  );

  Future<bool> writeOk(
    BuildContext context,
    String what,
    Future<void> Function() action, {
    bool retryable = true,
  }) => guardedWriteOk(
    context,
    this,
    what: what,
    action: action,
    retryable: retryable,
  );
}
