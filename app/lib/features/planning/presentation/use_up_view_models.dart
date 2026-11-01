/// *Use up*'s read of last week's spare food: the food, every
/// recipe that would use it scored, and the few worth offering.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/planning_providers.dart';
import '../domain/planning.dart';
import '../domain/use_up.dart';
import 'week_view_models.dart';

part 'use_up_view_models.g.dart';

/// What the week before a planned one left spare: the food, every recipe that
/// would use some of it (best first, [scoreUseUp]) and the ones to offer
/// ([rankUseUp]). Read once per picker, for the household's usual meal.
typedef UseUpView = ({
  List<SpareFood> spare,
  List<UseUpSuggestion> scored,
  List<UseUpSuggestion> offered,
});

@riverpod
Future<UseUpView> useUp(Ref ref, DateTime weekStart) async {
  final today = ref.watch(todayProvider);
  final members = ref.watch(membersProvider).asData?.value ?? const <Member>[];
  // A meal for everyone, at each person's usual portion.
  final portions = members.isEmpty
      ? 1.0
      : eatersDemand(
          [for (final m in members) m.id],
          {for (final m in members) m.id: m},
        );
  final facts = await ref
      .watch(useUpRepositoryProvider)
      .lastWeekFor(weekStart, today: today);
  final scored = scoreUseUp(
    recipes: facts.recipes,
    spare: facts.spare,
    portions: portions,
  );
  return (spare: facts.spare, scored: scored, offered: rankUseUp(scored));
}
