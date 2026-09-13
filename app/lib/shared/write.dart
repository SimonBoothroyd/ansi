/// The one door every user-initiated repository write goes through.
///
/// A write that throws must say so instead of stopping a spinner: without this
/// door a throw clears a `busy` flag, escapes to the zone handler, and becomes
/// a [debugPrint] on a console no phone has, leaving the user with a spinner
/// that stopped and nothing else. The rule is held mechanically rather than by
/// a paragraph in a style guide — `test/structure/no_bare_repo_write_test.dart`
/// fails the build for a call site that skips it.
///
/// **The one documented exception** is the bootstrap write in
/// `core/sync/session.dart`: `ensureDefaultBook` runs while the session is
/// still being established, before there is a screen to toast onto, and its
/// failure already lands on the connecting screen as a `SessionError` with a
/// reason and a retry — the same posture this door gives, reached the only
/// way it can be reached from there.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../core/observability/crash_sink.dart';
import '../core/router/app_router.dart';
import 'ansi_toast.dart';

/// Runs one user-initiated write and reports its failure honestly.
///
/// Awaits [action] and returns its value. On a throw it shows the shared
/// destructive toast — "Couldn't [what]." with a Retry that re-runs [action] —
/// and returns null. It never rethrows: the caller's happy path is guarded by
/// the null, which composes with the `context.mounted` check every call site in
/// this app already writes.
///
/// ```dart
/// final saved = await ref.write(context, 'save the recipe', notifier.save);
/// if (saved == null || !context.mounted) return;
/// ```
///
/// [what] is a lowercase verb phrase in the user's own noun that completes
/// "Couldn't ___." — "save the recipe", "add Tuesday's dinner", "delete that
/// section". Never a table name, never a method name.
///
/// Two things worth defending in review:
///
/// * **It takes a closure, not a future.** Retry has to *re-run* the write; a
///   `Future` is already running and can only be awaited again. The closure is
///   the entire reason Retry can exist.
/// * **It returns `T?` and never rethrows.** Adopting it is a pure addition at
///   every call site: `onPress: () => repo.deleteSection(id)` becomes
///   `onPress: () => ref.write(context, 'delete that section', …)` with
///   identical control flow.
///
/// Nothing is shown when [context] is already unmounted — a user who backed out
/// of a sheet mid-write is not chased across the app by a toast about it. The
/// failure is still logged.
Future<T?> guardedWrite<T>(
  BuildContext context,
  WidgetRef ref, {
  required String what,
  required Future<T> Function() action,
  bool retryable = true,
}) {
  // Resolved BEFORE the await, and carried by hand from here on. `ref` is
  // unsafe the moment the widget it belongs to is gone, and surviving exactly
  // that is the point of this helper — a sheet dismissed mid-write must not
  // turn a repository failure into a second, different one.
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
    // `note`, not `report`: this failure is handled, and it has its own honest
    // surface below. Reporting it too would produce both "Couldn't save the
    // recipe" and "Something went wrong" — the app arguing with itself.
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

/// [guardedWrite] for a `Future<void>` write whose caller still has to branch —
/// closing the sheet it was started from, navigating on.
///
/// `T?` cannot carry success when `T` is `void`, and a sheet that pops on a
/// write that never landed is the confusing outcome this whole front exists to
/// end. Returns true when the write landed.
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

/// A context that outlives the row that opened a sheet: the root navigator's
/// overlay. Resolve it BEFORE the first `await` in a flow that continues after
/// a sheet or dialog — open the next sheet with it, toast through it, and
/// nothing is lost when the row itself is gone.
///
/// Why a row can be gone: every list here is a viewport, and on a phone the
/// sheet's keyboard shrinks it, so the card that opened the sheet scrolls out
/// and unmounts while the sheet is still up. Riverpod 3 throws when a
/// `WidgetRef` outlives its widget, and a `context.mounted` bail avoids the
/// throw only by dropping the write the user just confirmed. The overlay is
/// the one every modal opens on — the app's shell navigator's while the app
/// is mounted (`shared/ansi_modals.dart`), the root's before it — so every
/// `showAnsi*` door and [showAnsiFailureToast] work from it, and
/// `Navigator.of(host.context).pop()` pops the sheet that is on top of it
/// rather than a page under it. Held by
/// `test/structure/no_ref_after_await_test.dart`.
HostContext hostContextOf(BuildContext context) => HostContext(
  (ansiShellNavigatorKey.currentState?.overlay ??
          Navigator.of(context, rootNavigator: true).overlay!)
      .context,
);

/// A context that is safe across async gaps — see [hostContextOf].
///
/// Its own type rather than a bare `BuildContext` so the
/// `use_build_context_synchronously` lint, which cannot know that the root
/// overlay outlives every row, is answered once here instead of with an
/// `ignore` at every call site. Reach the context through [context].
extension type const HostContext(BuildContext context) {}

/// [guardedWrite] for a write that lands AFTER an awaited sheet, from a
/// widget that may no longer exist: [container] was captured before the await
/// (`ProviderScope.containerOf(context, listen: false)`), [host] is
/// [hostContextOf] from the same moment. Same posture, same toast.
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

/// Sugar for the post-await form — see [guardedWriteFrom]. Reads as
/// `container.write(host, 'rename that book', …)`, so the structural write
/// check recognises it as the same door.
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

/// Sugar so a call site reads as one line — see [guardedWrite] and
/// [guardedWriteOk], which these forward to unchanged.
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
