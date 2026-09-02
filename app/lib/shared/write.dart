/// The one door every user-initiated repository write goes through.
///
/// The audit that produced this file found 38 UI→repository writes, 37 of them
/// with no failure surface at all and 8 not even awaited: a throw cleared a
/// `busy` flag, escaped to the zone handler, and became a `debugPrint` on a
/// console no phone has. The user saw a spinner stop and nothing else.
///
/// The fix is not a longer paragraph in a style guide — it is one helper plus a
/// mechanical check that nothing skips it (`test/structure/
/// no_bare_repo_write_test.dart`).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
/// final id = await ref.write(context, 'save the recipe', notifier.save);
/// if (id == null || !context.mounted) return;
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
  String? reassurance,
  bool retryable = true,
}) async {
  try {
    return await action();
  } on Object catch (error, stack) {
    // Handled, so it is logged here and never reported again by the zone
    // handler — otherwise one failed write produces both "Couldn't save the
    // recipe" and "Something went wrong", which is the app arguing with itself.
    debugPrint('write failed ($what): $error\n$stack');
    if (!context.mounted) return null;
    showAnsiFailureToast(
      context,
      what: what,
      reassurance: reassurance,
      onRetry: retryable
          ? () => unawaited(
              guardedWrite(
                context,
                ref,
                what: what,
                action: action,
                reassurance: reassurance,
              ),
            )
          : null,
    );
    return null;
  }
}

/// Sugar so a call site reads as one line — see [guardedWrite], which this
/// forwards to unchanged.
extension AnsiWrite on WidgetRef {
  Future<T?> write<T>(
    BuildContext context,
    String what,
    Future<T> Function() action, {
    String? reassurance,
    bool retryable = true,
  }) => guardedWrite(
    context,
    this,
    what: what,
    action: action,
    reassurance: reassurance,
    retryable: retryable,
  );
}
