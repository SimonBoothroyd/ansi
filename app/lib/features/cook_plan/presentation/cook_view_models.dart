/// Riverpod ViewModels for the Cook screen.
///
/// [currentCookPlan] streams the derived plan for the viewed week (the week the
/// Week screen shows, not the one containing today). The one intent is
/// [chooseWholeBatch]: the side of a session's exact-or-whole-batch switch,
/// kept on its cooking.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../shared/write.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/cook_plan.dart';

part 'cook_view_models.g.dart';

/// The derived cook plan for the viewed week, reacting to plan/recipe changes.
@riverpod
Stream<CookPlan> currentCookPlan(Ref ref) => ref
    .watch(cookPlanRepositoryProvider)
    .watchCookPlan(ref.watch(viewedWeekStartProvider));

/// Says [session] is cooked as a whole batch ([whole]) or at the exact scale,
/// on its cooking: a group of meals not in one yet is born into one. The
/// plan re-derives from the write, so the switch follows it.
void chooseWholeBatch(
  BuildContext context,
  WidgetRef ref,
  CookSession session, {
  required bool whole,
}) {
  final pot = session.cookingId ?? session.covers.firstOrNull?.entryId;
  if (pot == null || session.wholeBatch == whole) return;
  final repository = ref.read(leftoverRepositoryProvider);
  unawaited(
    ref.write(
      context,
      whole ? 'cook the whole batch' : 'cook the exact amount',
      () => repository.setWholeBatch(pot, whole: whole),
    ),
  );
}
