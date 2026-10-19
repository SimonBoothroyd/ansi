/// What Ansi proposes to change, checked and drawn as a card. Pure Dart.
///
/// **Machine proposes, a human confirms.** A `propose_*` tool call writes
/// nothing: it is checked here against the household's own rows and becomes
/// an [AskProposal] — every row it would change, with its date, slot and what
/// it replaces — which the sheet draws as a card. Only the card's Confirm
/// writes, in one transaction (`PlanningRepository.applyPlanChanges`), and a
/// meal edited after the card was drawn refuses the whole set.
library;

import 'package:meta/meta.dart';

import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../../core/words.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../planning/domain/plan_change.dart';
import '../../planning/domain/planning.dart';
import 'ask_tools.dart';

/// One line of a card: when, what, and what happens to it.
@immutable
class AskProposalRow {
  const AskProposalRow({required this.when, required this.what, this.note});

  /// `Mon 26 Oct · Dinner`, or empty for a list row.
  final String when;
  final String what;

  /// `replaces Ragù`, `new`, `removed`, `moves to Thu 29 Oct · Lunch`.
  final String? note;

  Map<String, Object?> toJson() => {
    if (when.isNotEmpty) 'when': when,
    'what': what,
    'note': ?note,
  };
}

/// A change Ansi proposes. Nothing is written until the member confirms.
@immutable
sealed class AskProposal {
  const AskProposal({required this.title, required this.rows});

  /// What the card is about: `Plan 7 changes`, `Add to the list`.
  final String title;

  /// Every row the change touches — the card is the whole change.
  final List<AskProposalRow> rows;
}

/// Changes to the plan, written together or not at all.
class AskPlanProposal extends AskProposal {
  const AskPlanProposal({
    required super.title,
    required super.rows,
    required this.changes,
  });

  final List<PlanChange> changes;
}

/// Last week's meals copied into [weekStart], as the Week's own copy does.
class AskCopyWeekProposal extends AskProposal {
  const AskCopyWeekProposal({
    required super.title,
    required super.rows,
    required this.weekStart,
  });

  final DateTime weekStart;
}

/// A manual top-up on the shopping list for [weekStart]: an ingredient with
/// an amount, or a free-text item.
class AskTopUpProposal extends AskProposal {
  const AskTopUpProposal({
    required super.title,
    required super.rows,
    required this.weekStart,
    this.ingredientId,
    this.quantity,
    this.unit,
    this.item,
  });

  final DateTime weekStart;
  final String? ingredientId;
  final double? quantity;
  final Unit? unit;

  /// The words of a free-text item ("paper towels").
  final String? item;
}

/// What the member did with a card.
enum AskDecision {
  confirmed,
  cancelled,

  /// A meal on the card changed before Confirm; nothing was written.
  changed,

  /// The write failed; nothing was written.
  failed;

  /// The tool result the model reads.
  String get said => switch (this) {
    confirmed => 'the member confirmed; the changes are written',
    cancelled => 'the member cancelled; nothing was written',
    changed =>
      'the plan changed before the member confirmed, so nothing was written; '
          'read the week again and propose afresh if it is still wanted',
    failed => 'the write failed on the phone; nothing was written',
  };
}

/// What a plan proposal is checked against.
@immutable
class AskPlanContext {
  const AskPlanContext({
    required this.shape,
    required this.weeks,
    required this.members,
    required this.recipeTitles,
    required this.ingredients,
  });

  final WeekShape shape;

  /// Every week a change names, by its first day; null where nothing is
  /// planned yet.
  final Map<DateTime, WeekPlan?> weeks;

  final List<Member> members;
  final Map<String, String> recipeTitles;
  final Map<String, Ingredient> ingredients;
}

/// One change as the model sent it, every key present (strict tools).
typedef AskRawChange = Map<String, Object?>;

/// The dates a change set names, so the weeks they fall in can be read
/// before [buildPlanProposal]. Throws [AskToolError] on a malformed date.
List<DateTime> datesNamed(List<AskRawChange> changes) => [
  for (final c in changes)
    if (c['date'] != null) parseAskDate(c['date']),
];

/// A `YYYY-MM-DD` date from the model, as a UTC date.
DateTime parseAskDate(Object? raw) {
  final d = raw is String ? DateTime.tryParse(raw.trim()) : null;
  if (d == null || raw is! String || raw.trim().length != 10) {
    throw AskToolError('`$raw` is not a date; dates are YYYY-MM-DD');
  }
  return DateTime.utc(d.year, d.month, d.day);
}

/// `Mon 26 Oct`, the day named through the household's [shape].
String askDayLabel(WeekShape shape, DateTime date) =>
    '${shape.labelShort(shape.offsetOf(date))} ${formatDayMonth(date)}';

/// Checks [raw] against [context] and draws the card. Throws [AskToolError]
/// in words the model can act on.
AskPlanProposal buildPlanProposal(
  List<AskRawChange> raw,
  AskPlanContext context,
) {
  if (raw.isEmpty) throw const AskToolError('there are no changes');
  final shape = context.shape;
  final byId = <String, ({PlanEntry entry, DateTime weekStart})>{
    for (final w in context.weeks.values)
      if (w != null)
        for (final e in w.entries) e.id: (entry: e, weekStart: w.weekStart),
  };
  final memberIds = {for (final m in context.members) m.id};
  final names = {for (final m in context.members) m.id: m.displayName};

  String eatersSaid(List<String> ids) =>
      ids.map((id) => names[id] ?? 'someone').join(', ');

  String whenOf(DateTime weekStart, int day, String slot) =>
      '${askDayLabel(shape, shape.dateFor(weekStart, day))} · $slot';

  String titleOf(PlanEntry e) => e.title ?? deletedTargetLabel(e);

  /// The slot as the week spells it: a default slot in its own case, a
  /// custom slot as the week already has it, else as said.
  String slotOf(Object? said, DateTime weekStart) {
    final s = said is String ? said.trim() : '';
    if (s.isEmpty) throw const AskToolError('`slot` is missing');
    for (final d in kDefaultMealSlots) {
      if (d.toLowerCase() == s.toLowerCase()) return d;
    }
    for (final e in context.weeks[weekStart]?.entries ?? const <PlanEntry>[]) {
      if (e.mealSlot.toLowerCase() == s.toLowerCase()) return e.mealSlot;
    }
    return s;
  }

  List<String> eatersOf(Object? said, {required bool orEveryone}) {
    if (said == null && orEveryone) return [...memberIds];
    if (said is! List) throw const AskToolError('`eaters` is missing');
    final ids = [for (final id in said) id.toString()];
    for (final id in ids) {
      if (!memberIds.contains(id)) {
        throw AskToolError('`$id` is not a member id; read the week for them');
      }
    }
    return ids.toSet().toList();
  }

  ({PlanEntry entry, DateTime weekStart}) existing(AskRawChange c) {
    final id = c['entry_id'];
    final hit = id is String ? byId[id] : null;
    if (hit == null) {
      throw AskToolError(
        'no planned meal has the id `$id`; read the week with `week` and use '
        'the ids it gives',
      );
    }
    return hit;
  }

  final changes = <PlanChange>[];
  final touched = <String>{};
  // Sort keys beside each row: the date, then the slot's rank.
  final rows = <({DateTime date, int rank, AskProposalRow row})>[];
  // A remove and an add in one slot read as one row: "replaces".
  final removedAt = <String, List<String>>{};
  String slotKey(DateTime weekStart, int day, String slot) =>
      '${isoDateOf(weekStart)}|$day|${slot.toLowerCase()}';

  for (final c in raw) {
    if (c['op'] case 'remove' || 'move' || 'set_eaters') {
      final id = c['entry_id'];
      if (id is String && !touched.add(id)) {
        throw AskToolError('the meal `$id` is changed twice; change it once');
      }
    }
  }

  for (final c in raw) {
    switch (c['op']) {
      case 'remove':
        final hit = existing(c);
        changes.add(PlanRemove(hit.entry));
        removedAt
            .putIfAbsent(
              slotKey(hit.weekStart, hit.entry.dayOfWeek, hit.entry.mealSlot),
              () => [],
            )
            .add(titleOf(hit.entry));
      case 'move':
        final hit = existing(c);
        final date = c['date'] == null
            ? shape.dateFor(hit.weekStart, hit.entry.dayOfWeek)
            : parseAskDate(c['date']);
        final weekStart = shape.weekStartOf(date);
        final day = shape.offsetOf(date);
        final slot = c['slot'] == null
            ? hit.entry.mealSlot
            : slotOf(c['slot'], weekStart);
        changes.add(
          PlanMove(
            hit.entry,
            weekStart: weekStart,
            dayOfWeek: day,
            mealSlot: slot,
          ),
        );
        final from = shape.dateFor(hit.weekStart, hit.entry.dayOfWeek);
        rows.add((
          date: from,
          rank: mealSlotRank(hit.entry.mealSlot),
          row: AskProposalRow(
            when: whenOf(
              hit.weekStart,
              hit.entry.dayOfWeek,
              hit.entry.mealSlot,
            ),
            what: titleOf(hit.entry),
            note: 'moves to ${whenOf(weekStart, day, slot)}',
          ),
        ));
      case 'set_eaters':
        final hit = existing(c);
        final eaters = eatersOf(c['eaters'], orEveryone: false);
        final when = whenOf(
          hit.weekStart,
          hit.entry.dayOfWeek,
          hit.entry.mealSlot,
        );
        final date = shape.dateFor(hit.weekStart, hit.entry.dayOfWeek);
        if (eaters.isEmpty) {
          changes.add(PlanRemove(hit.entry));
          rows.add((
            date: date,
            rank: mealSlotRank(hit.entry.mealSlot),
            row: AskProposalRow(
              when: when,
              what: titleOf(hit.entry),
              note: 'no one left eating it — removed',
            ),
          ));
        } else {
          changes.add(PlanSetEaters(hit.entry, eaters));
          rows.add((
            date: date,
            rank: mealSlotRank(hit.entry.mealSlot),
            row: AskProposalRow(
              when: when,
              what: titleOf(hit.entry),
              note:
                  'eaten by ${eatersSaid(eaters)} '
                  '(was ${eatersSaid(hit.entry.eaterIds)})',
            ),
          ));
        }
      case 'add':
        // Read in a second pass, once every remove is known.
        break;
      default:
        throw AskToolError(
          '`${c['op']}` is not a change; use add, remove, move or set_eaters',
        );
    }
  }

  for (final c in raw.where((c) => c['op'] == 'add')) {
    if (c['date'] == null) throw const AskToolError('`date` is missing');
    final date = parseAskDate(c['date']);
    final weekStart = shape.weekStartOf(date);
    final day = shape.offsetOf(date);
    final slot = slotOf(c['slot'], weekStart);
    final eaters = eatersOf(c['eaters'], orEveryone: true);
    if (eaters.isEmpty) throw const AskToolError('a meal needs an eater');

    final saidRecipe = c['recipe_id'] as String?;
    final saidIngredient = c['ingredient_id'] as String?;
    final saidLabel = c['out_label'] as String?;
    final named = [
      saidRecipe,
      saidIngredient,
      saidLabel,
    ].where((v) => v != null);
    if (named.length != 1) {
      throw const AskToolError(
        'an added meal names exactly one of recipe_id, ingredient_id or '
        'out_label',
      );
    }
    final PlanTarget target;
    final String what;
    String? amount;
    if (saidRecipe case final recipeId?) {
      final title = context.recipeTitles[recipeId];
      if (title == null) {
        throw AskToolError('there is no recipe with the id `$recipeId`');
      }
      target = PlanRecipeTarget(recipeId);
      what = title;
    } else if (saidIngredient case final ingredientId?) {
      final ingredient = context.ingredients[ingredientId];
      if (ingredient == null) {
        throw AskToolError(
          'there is no ingredient with the id `$ingredientId`',
        );
      }
      final q = askAmount(ingredient, c['quantity'], c['unit']);
      target = PlanIngredientTarget(
        ingredient.id,
        quantity: q?.quantity,
        unit: q?.unit,
      );
      what = ingredient.canonicalName;
      amount = q == null
          ? 'no amount — set it on the Week'
          : '${formatQuantityOf(q.quantity, q.unit)} each';
    } else {
      final words = saidLabel!.trim();
      if (words.isEmpty) throw const AskToolError('`out_label` is empty');
      target = PlanOutTarget(words);
      what = '$words (eaten out)';
    }
    changes.add(
      PlanAdd(
        weekStart: weekStart,
        dayOfWeek: day,
        mealSlot: slot,
        target: target,
        eaterIds: eaters,
      ),
    );
    final replaced = removedAt.remove(slotKey(weekStart, day, slot));
    final notes = [
      if (replaced == null) 'new' else 'replaces ${replaced.join(', ')}',
      ?amount,
      if (eaters.length < memberIds.length) 'for ${eatersSaid(eaters)}',
    ];
    rows.add((
      date: shape.dateFor(weekStart, day),
      rank: mealSlotRank(slot),
      row: AskProposalRow(
        when: whenOf(weekStart, day, slot),
        what: what,
        note: notes.join(' · '),
      ),
    ));
  }

  // Removes no add replaced are rows of their own.
  for (final c in raw.where((c) => c['op'] == 'remove')) {
    final hit = existing(c);
    final key = slotKey(hit.weekStart, hit.entry.dayOfWeek, hit.entry.mealSlot);
    if (!removedAt.containsKey(key)) continue;
    rows.add((
      date: shape.dateFor(hit.weekStart, hit.entry.dayOfWeek),
      rank: mealSlotRank(hit.entry.mealSlot),
      row: AskProposalRow(
        when: whenOf(hit.weekStart, hit.entry.dayOfWeek, hit.entry.mealSlot),
        what: titleOf(hit.entry),
        note: 'removed',
      ),
    ));
  }

  rows.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.rank.compareTo(b.rank);
  });
  return AskPlanProposal(
    title: changes.length == 1
        ? 'Plan 1 change'
        : 'Plan ${changes.length} changes',
    rows: [for (final r in rows) r.row],
    changes: changes,
  );
}

/// An amount said for [ingredient]: a number and a unit it allows, both or
/// neither. Throws [AskToolError] naming the units it does allow.
({double quantity, Unit unit})? askAmount(
  Ingredient ingredient,
  Object? quantity,
  Object? unit,
) {
  if (quantity == null && unit == null) return null;
  final allowed = allowedUnitsFor(ingredient);
  final ids = allowed.map((u) => u.id).join(', ');
  if (quantity is! num || !quantity.isFinite || quantity <= 0) {
    throw AskToolError(
      '`quantity` must be a positive number with a unit ($ids)',
    );
  }
  final u = unit is String ? unitById(unit.trim()) : null;
  if (u == null || !allowed.contains(u)) {
    throw AskToolError(
      '${ingredient.canonicalName} is measured in $ids; `$unit` is not one',
    );
  }
  return (quantity: quantity.toDouble(), unit: u);
}

/// `170 g`, `2 tbsp` — an amount as the app prints it.
String formatQuantityOf(double quantity, Unit unit) =>
    '${formatAmountIn(quantity, unit)} ${unit.label}';

/// The copy-last-week card: each meal of [source] at its place in
/// [weekStart], and the variants a copy never carries.
AskCopyWeekProposal buildCopyWeekProposal({
  required WeekShape shape,
  required DateTime weekStart,
  required WeekPlan? source,
  required WeekPlan? target,
}) {
  if (source == null || source.entries.isEmpty) {
    throw const AskToolError('no earlier week has meals to copy');
  }
  final planned = target?.entries.length ?? 0;
  String meals(int n) => '$n ${plural(n, 'meal')}';
  final rows = [
    for (var day = 0; day < 7; day++)
      for (final e in source.entriesForDay(day))
        AskProposalRow(
          when:
              '${askDayLabel(shape, shape.dateFor(weekStart, day))} · '
              '${e.mealSlot}',
          what: e.title ?? deletedTargetLabel(e),
          note: 'copied',
        ),
  ];
  return AskCopyWeekProposal(
    title: planned == 0
        ? 'Copy ${meals(rows.length)} from the week of '
              '${formatDayMonth(source.weekStart)}'
        : 'Copy ${meals(rows.length)} — beside the ${meals(planned)} already '
              'planned',
    rows: rows,
    weekStart: weekStart,
  );
}

/// The top-up card: [ingredient] with an amount, or a free-text [item].
AskTopUpProposal buildTopUpProposal({
  required DateTime weekStart,
  required WeekShape shape,
  Ingredient? ingredient,
  Object? quantity,
  Object? unit,
  String? item,
}) {
  final week = 'the list for the week of ${askDayLabel(shape, weekStart)}';
  if (ingredient != null) {
    final q = askAmount(ingredient, quantity, unit);
    if (q == null) {
      throw AskToolError(
        'a top-up needs an amount; ask how much ${ingredient.canonicalName}',
      );
    }
    return AskTopUpProposal(
      title: 'Add to $week',
      rows: [
        AskProposalRow(
          when: '',
          what: ingredient.canonicalName,
          note: '+ ${formatQuantityOf(q.quantity, q.unit)}',
        ),
      ],
      weekStart: weekStart,
      ingredientId: ingredient.id,
      quantity: q.quantity,
      unit: q.unit,
    );
  }
  final words = item?.trim() ?? '';
  if (words.isEmpty) {
    throw const AskToolError('name an ingredient_id or an item');
  }
  return AskTopUpProposal(
    title: 'Add to $week',
    rows: [AskProposalRow(when: '', what: words, note: 'new item')],
    weekStart: weekStart,
    item: words,
  );
}
