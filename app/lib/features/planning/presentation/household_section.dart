/// "Household" — who eats here and how much, as a section of `/account`
/// (plan 0028 E6; the roster and the segment are plan 0027 front P, board
/// frame a).
///
/// A usual portion belongs to the person, not to Tuesday's curry, so it is
/// stated once here and spent wherever a head-count used to be — the entry
/// sheet's Portions row, the cook plan, the shopping list, the macro lens. The
/// override on an entry remains the place for the exception ("cook 3
/// tonight"). Either member may set either's (P-D3): the rows are the whole
/// roster, not "me".
///
/// The segment (P-D2) is the five quick picks ×½ · ×¾ · ×1 · ×1¼ · ×1½ and a
/// `…` that opens a stepper in quarter steps from ¼ to 3 — nobody knows they
/// eat 0.83 of a portion. Every tap writes through; there is no Save.
///
/// This was a sheet off the Library `⋯` until 0028 deleted that menu. It is a
/// section now, not a sheet: a sheet is a place to answer one question, and
/// the household is a thing you look at beside the device and the session.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/portions.dart';
import '../../../shared/write.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart';
import 'meal_fields.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

class HouseholdSection extends ConsumerWidget {
  const HouseholdSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live: the partner's write lands here too, mid-screen.
    final members = ref.watch(membersProvider).asData?.value ?? const [];
    final repo = ref.read(planningRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MealFieldLabel('Usual portion'),
        const SizedBox(height: 8),
        for (final (i, m) in members.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    EaterAvatar(member: m, color: memberColor(i)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(m.displayName, style: ansiSerif(size: 17)),
                    ),
                    Text(
                      '×${formatFraction(m.portionFactor)}',
                      style: ansiMono(size: 12, color: AnsiColors.herbDeep),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PortionFactorSegment(
                  value: m.portionFactor,
                  onChanged: (factor) => unawaited(
                    ref.write(
                      context,
                      'set ${m.displayName}’s usual portion',
                      () => repo.setPortionFactor(m.id, factor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (members.isNotEmpty)
          Text(
            householdDemandLine(members),
            style: ansiMono(size: 10.5, color: AnsiColors.muted),
          ),
      ],
    );
  }
}

/// The section's foot: what a meal for the whole roster now counts as, and the
/// three places that read it that way — *"a meal for both counts as 1¾
/// portions — the cook plan, the shop and the macro lens all read it that
/// way"* (board frame a).
String householdDemandLine(List<Member> members) {
  final demand = eatersDemand(members.map((m) => m.id), {
    for (final m in members) m.id: m,
  });
  final who = switch (members.length) {
    1 => members.single.displayName,
    2 => 'both',
    _ => 'everyone',
  };
  return 'a meal for $who counts as ${formatPortions(demand)} — the cook '
      'plan, the shop and the macro lens all read it that way';
}

/// The segment (P-D2): the five picks, and `…` for a custom value in quarter
/// steps within [kPortionFactorMin]..[kPortionFactorMax]. A stored value that
/// is not one of the picks opens in custom mode, so what the row shows is
/// always the value on file, never the nearest chip.
class PortionFactorSegment extends HookWidget {
  const PortionFactorSegment({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final isPick = kPortionFactorPicks.any((p) => (p - value).abs() < 1e-9);
    final custom = useState(!isPick);
    // A synced value arriving from the partner's phone re-decides the mode.
    useEffect(() {
      if (!isPick) custom.value = true;
      return null;
    }, [value]);

    const step = kPortionFactorStep;
    final canStepDown = value - step >= kPortionFactorMin - 1e-9;
    final canStepUp = value + step <= kPortionFactorMax + 1e-9;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final pick in kPortionFactorPicks)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _FactorChip(
                  label: '×${formatFraction(pick)}',
                  selected: !custom.value && (pick - value).abs() < 1e-9,
                  onTap: () {
                    custom.value = false;
                    onChanged(pick);
                  },
                ),
              ),
            _FactorChip(
              label: '…',
              selected: custom.value,
              onTap: () => custom.value = true,
            ),
          ],
        ),
        if (custom.value)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: canStepDown ? () => onChanged(value - step) : null,
                  child: const Icon(FLucideIcons.minus, size: 16),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '×${formatFraction(value)}',
                    textAlign: TextAlign.center,
                    style: ansiMono(size: 15, weight: FontWeight.w600),
                  ),
                ),
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: canStepUp ? () => onChanged(value + step) : null,
                  child: const Icon(FLucideIcons.plus, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  'quarter steps, ¼ to 3',
                  style: ansiMono(size: 10, color: AnsiColors.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FactorChip extends StatelessWidget {
  const _FactorChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herbSoft : AnsiColors.surface,
          border: Border.all(
            color: selected ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: ansiMono(
            size: 12,
            color: selected ? AnsiColors.ink : AnsiColors.muted,
            weight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
