/// The household's fridge and freezer: what each cooking holds today, and
/// every meal served from one judged on its own day. Pure Dart.
///
/// **No tick means you didn't eat it.** A cooking is cooked on the earliest
/// day anybody ticked one of its meals, in whatever order the ticks came; one
/// nobody ticked is not cooked yet while a meal of it is still to come, and
/// reads as cooked on that meal's day (`cook Thu`); once every meal is behind
/// us it was never cooked and holds nothing ([readCookings]).
///
/// It is good in the fridge until the cook day plus the recipe's fridge life,
/// that day included ([kAssumedFridgeDays] when unknown). A meal later than
/// that, of a dish that freezes and within its freezer life, is a **freezer
/// meal**: its portions are taken to go in the freezer by the fridge date
/// (`freeze by Mon for Wed`), with no write. Freezer dates count from the cook
/// day too.
///
/// The cook plan's session helpers ([cookDayOf], [useByOf], [freezeShareOf])
/// read the same rules off a [CookSession]: what Cook, the Week and the meal's
/// sheet draw for a batch.
library;

import 'dart:math' show min;

import 'package:meta/meta.dart';

import 'cook_plan.dart';
import 'cooking.dart';

export 'cook_plan.dart' show kAssumedFridgeDays;
export 'cooking.dart' show LeftoverPlace;

/// Whether anybody ticked any meal [session] covers: proof it was cooked.
bool wasCooked(CookSession session) =>
    session.covers.any((m) => m.eatenPortions > 1e-9);

/// The date [day] of the week beginning [weekStart] names. [day] may fall
/// outside the week (a cooking's meal in another week).
DateTime dateOfDay(DateTime weekStart, int day) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + day);

/// The day [session] — of the week beginning [weekStart] — is cooked, as an
/// offset from [weekStart], on [today].
///
/// The earliest covered day anybody ticked, in whatever order the ticks came;
/// with no tick, the first covered day not yet behind [today]. Null when no
/// meal was ticked and every one is behind: it was never cooked.
int? cookDayOf(CookSession session, DateTime weekStart, DateTime today) {
  int? earliest(Iterable<int> days) => days.isEmpty ? null : days.reduce(min);
  final ticked = earliest([
    for (final m in session.covers)
      if (m.eatenPortions > 1e-9) m.dayOfWeek,
  ]);
  if (ticked != null) return ticked;
  final day = _dateOnly(today);
  return earliest([
    for (final m in session.covers)
      if (!dateOfDay(weekStart, m.dayOfWeek).isBefore(day)) m.dayOfWeek,
  ]);
}

/// [session] cooked on its day by the ticks ([cookDayOf]) rather than its
/// planned one: what the week strip, the meal's sheet and Cook draw. Its
/// planned day when it was never cooked, and for a component batch.
CookSession sessionByTicks(
  CookSession session,
  DateTime weekStart,
  DateTime today,
) {
  if (session.isComponent) return session;
  final day = cookDayOf(session, weekStart, today);
  return day == null || day == session.cookDay
      ? session
      : session.copyWith(cookDay: day);
}

/// [session]'s fridge date in the week beginning [weekStart], on [today]: its
/// cook day ([cookDayOf]) plus its fridge life, that day included. Null when
/// it was never cooked.
DateTime? useByOf(CookSession session, DateTime weekStart, DateTime today) {
  final cookDay = cookDayOf(session, weekStart, today);
  if (cookDay == null) return null;
  return dateOfDay(
    weekStart,
    cookDay + (session.keepsForDays ?? kAssumedFridgeDays),
  );
}

/// The part of a batch that goes in the freezer for its later meals: the
/// `portions` to freeze, by `freezeBy` (its fridge date), for the meals on
/// `forDays`.
typedef FreezeShare = ({
  double portions,
  DateTime freezeBy,
  List<DateTime> forDays,
});

/// The meals of a freezable [session] past its fridge date ([useByOf]), which
/// it reaches from the freezer: `freeze 2 by Tue for Thu`. Null when it has
/// none, is not freezable, or was never cooked.
FreezeShare? freezeShareOf(
  CookSession session,
  DateTime weekStart,
  DateTime today,
) {
  if (!session.freezable || session.isComponent) return null;
  final until = useByOf(session, weekStart, today);
  if (until == null) return null;
  var portions = 0.0;
  final days = <DateTime>{};
  for (final m in session.covers) {
    final day = dateOfDay(weekStart, m.dayOfWeek);
    final still = m.portions - m.eatenPortions;
    if (!day.isAfter(until) || still <= 1e-9) continue;
    portions += still;
    days.add(day);
  }
  if (days.isEmpty) return null;
  return (portions: portions, freezeBy: until, forDays: days.toList()..sort());
}

/// What is wrong with a meal served from a cooking, on that meal's own day.
/// A warning, never an edit: the plan stays as the household made it.
enum LeftoverWarning {
  /// The meals served before it, and it, ask more than there is; or the
  /// food is gone, or was never cooked.
  notEnoughLeft,

  /// Its day is past every date the cooking can reach.
  pastItsDate,
}

/// One meal linked to a cooking, judged on its own day.
@immutable
class LeftoverMeal {
  const LeftoverMeal({
    required this.day,
    required this.portions,
    this.entryId,
    this.place,
    this.freezeBy,
    this.warning,
  });

  /// The planned meal.
  final String? entryId;

  final DateTime day;

  /// What it takes from the cooking: its planned portions from today on, its
  /// ticked shares behind us.
  final double portions;

  /// The shelf it is eaten from on [day]; null when nothing is good that day.
  final LeftoverPlace? place;

  /// Set while a freezer meal's portions are still in the fridge: the day to
  /// freeze them by, the fridge date.
  final DateTime? freezeBy;

  final LeftoverWarning? warning;

  @override
  String toString() =>
      'LeftoverMeal($entryId, $day, $portions, ${place?.name}'
      '${freezeBy == null ? '' : ', freeze by $freezeBy'}'
      '${warning == null ? '' : ', ${warning!.name}'})';
}

/// One shelf of one cooking: the fridge part or the freezer part, as the
/// Leftovers page, the picker and Cook draw it.
@immutable
class Leftover {
  const Leftover({
    required this.id,
    required this.place,
    required this.title,
    required this.since,
    required this.goodUntil,
    required this.box,
    this.recipeId,
    this.planned = 0,
    this.freezable = false,
    this.freezerUntil,
    this.freezeBy,
    this.meals = const [],
    this.alsoOnOtherShelf = false,
    this.cooked = true,
    this.plannedIn,
  });

  /// The cooking's id: both its shelves share it. For a pot not born yet
  /// ([plannedIn]), its first meal's id, which a pick births it under.
  final String id;

  /// Which shelf this is.
  final LeftoverPlace place;

  /// The recipe, or null for food in the household's own words.
  final String? recipeId;

  /// The recipe's title, or the household's words.
  final String title;

  /// The day it was cooked, which its dates count from. A cooking not cooked
  /// yet has the day it will be.
  final DateTime since;

  /// The last day it is good on [place], inclusive; null when there is no
  /// limit (a freezer with no `freezer_days`, or words in the freezer).
  final DateTime? goodUntil;

  /// What is on this shelf, spoken for or not, unclamped: made, plus the
  /// changes said, less what its meals took. An untick reverses exactly.
  final double box;

  /// The portions the meals still to come take from this shelf: spoken for.
  final double planned;

  /// What is in the box today, never below zero: the `N left` the Leftovers
  /// page and Cook print, and what its stepper sets.
  double get inBox => box > 1e-9 ? box : 0;

  /// What is free to plan from it: [inBox] less what is spoken for, never
  /// below zero. The picker's `N left`.
  double get portions {
    final free = box - planned;
    return free > 1e-9 ? free : 0;
  }

  /// Whether the dish freezes.
  final bool freezable;

  /// For a freezable dish, the last day it is good frozen, counted from the
  /// cook day; null when the freezer has no limit or it does not freeze.
  final DateTime? freezerUntil;

  /// Set on a fridge shelf whose freezer meals' portions are still in it
  /// (`freeze by Mon for Wed`): the fridge date. Also set on a row the
  /// picker offers under Freezer for a day it will need freezing for.
  final DateTime? freezeBy;

  /// The meals served from this shelf, in day order, each judged on its own
  /// day.
  final List<LeftoverMeal> meals;

  /// Whether the same cooking has food on the other shelf too: removing this
  /// shelf's food must leave that.
  final bool alsoOnOtherShelf;

  /// Whether anybody ticked a meal of it, or it was said by hand. A pot not
  /// cooked yet ([since] is the day it will be) holds nothing to eat: a meal
  /// picked from it adds to what it makes.
  final bool cooked;

  /// For a pot not born yet (planned meals no cooking holds), the first day
  /// of the week its meals are planned in; null for a cooking.
  final DateTime? plannedIn;

  /// Whether it has been cooked by [today]: a cooking not cooked yet is
  /// offered for a day from its cook day on, but is not in the fridge.
  bool isCookedBy(DateTime today) => !since.isAfter(_dateOnly(today));

  /// The shelf it is eaten from on [day], or null when nothing of it is good
  /// then: before its cook day, or past every date it can reach. A fridge row
  /// of a freezable dish reaches past its fridge date from the freezer.
  LeftoverPlace? shelfOn(DateTime day) {
    final d = _dateOnly(day);
    if (d.isBefore(since)) return null;
    final inDate = goodUntil == null || !d.isAfter(goodUntil!);
    if (place == LeftoverPlace.freezer) return inDate ? place : null;
    if (inDate) return LeftoverPlace.fridge;
    if (freezable && (freezerUntil == null || !d.isAfter(freezerUntil!))) {
      return LeftoverPlace.freezer;
    }
    return null;
  }

  /// Whether its date is behind [today]. It stays until somebody says it is
  /// gone: nothing clears itself.
  bool pastItsDate(DateTime today) {
    final until = goodUntil;
    return until != null && _dateOnly(today).isAfter(until);
  }

  /// This row as the picker offers it for a day reached only from the
  /// freezer: under Freezer, good until its freezer date, to be frozen by
  /// its fridge date.
  Leftover frozenForLater() => Leftover(
    id: id,
    place: LeftoverPlace.freezer,
    recipeId: recipeId,
    title: title,
    since: since,
    goodUntil: freezerUntil,
    box: box,
    planned: planned,
    freezable: freezable,
    freezerUntil: freezerUntil,
    freezeBy: goodUntil,
    meals: meals,
    alsoOnOtherShelf: alsoOnOtherShelf,
    cooked: cooked,
    plannedIn: plannedIn,
  );

  @override
  String toString() =>
      'Leftover(${place.name}: $title, box $box, spoken $planned, '
      'since $since, until $goodUntil${cooked ? '' : ', not cooked'})';
}

/// [left] as the planning picker offers it for a meal on [day], or null when
/// it is not offered: words, nothing free to plan, past its date on [today],
/// or not good on [day].
///
/// Freshness is judged on [day], not [today]. A fridge row good on [day] is
/// offered from the fridge. One past its fridge date by then, of a dish that
/// freezes and would be in date frozen, is offered under Freezer, to be
/// frozen by its fridge date ([Leftover.frozenForLater]).
///
/// A pot not cooked yet ([Leftover.cooked]) is offered whatever it has free:
/// a meal picked from it adds its portions to what it makes. It is offered
/// from its cook day on, for as long as it would keep.
Leftover? leftoverOfferOn(Leftover left, DateTime day, DateTime today) {
  if (left.recipeId == null ||
      (left.cooked && left.portions <= 1e-9) ||
      left.pastItsDate(today)) {
    return null;
  }
  return switch (left.shelfOn(day)) {
    null => null,
    final shelf when shelf == left.place => left,
    _ => left.frozenForLater(),
  };
}

/// The household's leftovers on a day: the rows the Leftovers page and the
/// picker read, and every meal served from a cooking, by its planned meal's
/// id.
@immutable
class LeftoverShelves {
  const LeftoverShelves({
    this.rows = const [],
    this.meals = const {},
    this.pots = const [],
  });

  /// Fridge first, then freezer; within each, soonest to go off first and
  /// past its date last.
  final List<Leftover> rows;

  /// Each meal linked to a cooking, from its cook day on, judged on its own
  /// day, by `plan_entry` id: the Week's tag. A meal of a cooking that is
  /// gone or was never cooked is here too, warned.
  final Map<String, LeftoverMeal> meals;

  /// Pots not born yet: planned meals from today on that no cooking holds,
  /// grouped as they would be born ([plannedPots]). Never on the Leftovers
  /// page; the picker offers them for a later week.
  final List<Leftover> pots;
}

/// One planned recipe meal from today on that no cooking holds yet: what a
/// pot not born yet is read from.
typedef UnbornMeal = ({
  String entryId,
  String recipeId,
  DateTime weekStart,
  int dayOfWeek,
  CookingShelfLife life,
});

/// The pots not born yet among [meals]: each week's meals of a recipe grouped
/// by shelf life as a birth would group them ([clusterSessions]), one row per
/// group, under its first meal's id. Not cooked: its [Leftover.since] is that
/// first meal's day, and it keeps from then as a cooking would.
List<Leftover> plannedPots(List<UnbornMeal> meals) {
  final groups = <String, List<UnbornMeal>>{};
  for (final m in meals) {
    final week = _dateOnly(m.weekStart);
    (groups['${week.toIso8601String()} ${m.recipeId}'] ??= []).add(m);
  }
  final pots = <Leftover>[];
  for (final group in groups.values) {
    final first = group.first;
    final life = first.life;
    final sessions = clusterSessions(
      PlannedRecipe(
        recipeId: first.recipeId,
        title: life.title,
        servingsBase: 1,
        keepsForDays: life.keepsForDays,
        freezable: life.freezable,
        freezerDays: life.freezerDays,
        meals: [
          for (final m in group)
            CoveredMeal(
              dayOfWeek: m.dayOfWeek,
              mealSlot: '',
              portions: 1,
              entryId: m.entryId,
            ),
        ],
      ),
    );
    for (final s in sessions) {
      final since = dateOfDay(_dateOnly(first.weekStart), s.cookDay);
      pots.add(
        Leftover(
          id: s.covers.first.entryId!,
          place: LeftoverPlace.fridge,
          recipeId: first.recipeId,
          title: life.title,
          since: since,
          goodUntil: _plus(since, life.keepsForDays ?? kAssumedFridgeDays),
          box: 0,
          freezable: life.freezable,
          freezerUntil: life.freezable ? _plus(since, life.freezerDays) : null,
          cooked: false,
          plannedIn: _dateOnly(first.weekStart),
        ),
      );
    }
  }
  return pots;
}

/// One cooking as the shelves read it: the stored row, its recipe's shelf
/// life (null for words, or a recipe since deleted), its live linked meals and
/// the sum of its live change rows.
typedef CookingInput = ({
  Cooking cooking,
  CookingShelfLife? life,
  List<CookingMeal> meals,
  CookingChanges changes,
});

/// What one cooking holds on a day: its rows (a shelf each), every linked meal
/// judged, and each shelf's box unclamped, which a correction is measured
/// against.
typedef CookingRead = ({
  List<Leftover> rows,
  List<LeftoverMeal> meals,
  double fridge,
  double freezer,
});

/// The household's leftovers on [today], from every cooking read
/// ([readCooking]): rows soonest to go off first, and every linked meal
/// judged. [unborn] are the planned meals no cooking holds yet, read as pots
/// ([plannedPots]).
LeftoverShelves readCookings(
  List<CookingInput> cookings,
  DateTime today, {
  List<UnbornMeal> unborn = const [],
}) {
  final day = _dateOnly(today);
  final rows = <Leftover>[];
  final meals = <String, LeftoverMeal>{};
  for (final input in cookings) {
    final read = readCooking(input, day);
    rows.addAll(read.rows);
    for (final m in read.meals) {
      if (m.entryId case final id?) meals[id] = m;
    }
  }
  rows.sort((a, b) {
    final place = a.place.index.compareTo(b.place.index);
    if (place != 0) return place;
    final past = (a.pastItsDate(day) ? 1 : 0) - (b.pastItsDate(day) ? 1 : 0);
    if (past != 0) return past;
    final until = switch ((a.goodUntil, b.goodUntil)) {
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
      (final x?, final y?) => x.compareTo(y),
    };
    if (until != 0) return until;
    final since = a.since.compareTo(b.since);
    return since != 0 ? since : a.title.compareTo(b.title);
  });
  return LeftoverShelves(
    rows: List.unmodifiable(rows),
    meals: meals,
    pots: List.unmodifiable(plannedPots(unborn)),
  );
}

/// What one cooking holds on [today], and how each of its meals stands.
///
/// - **Made** goes on its shelf (the fridge, or where food said by hand
///   went), and every change row adds to (or takes from) the shelf it names.
/// - **Each meal takes**, in day order: behind today, its ticked shares;
///   from today on, its planned portions in full (spoken for). A meal on or
///   before the fridge date takes from the fridge, and from the freezer's
///   spare when the fridge has not got it; a **freezer meal** first moves its
///   portions from the fridge to the freezer (what the freezer has spare
///   already covers that much), then takes from the freezer; a meal past
///   every date takes from the fridge, `past its date`.
/// - Counts are kept unclamped, so an untick reverses exactly; a row shows
///   while its shelf holds anything or a meal still to come takes from it.
/// - A cooking said gone off (`gone_at`) loses its fridge part for good: an
///   untick after it brings nothing back. Its freezer part goes too unless
///   it was still in date that day; with nothing left, the cooking shows
///   nothing and the meals still to come from it warn. One never
///   cooked shows nothing, and every meal from it warns.
CookingRead readCooking(CookingInput input, DateTime today) {
  final day = _dateOnly(today);
  final cooking = input.cooking;
  final life = input.life;
  const none = (
    rows: <Leftover>[],
    meals: <LeftoverMeal>[],
    fridge: 0.0,
    freezer: 0.0,
  );
  // A recipe deleted since (or not yet synced) takes its cooking with it.
  if (cooking.recipeId != null && life == null) return none;

  final meals = [...input.meals]
    ..sort((a, b) {
      final d = _dateOnly(a.day).compareTo(_dateOnly(b.day));
      return d != 0 ? d : a.entryId.compareTo(b.entryId);
    });
  final cookDay = cookDayOfCooking(cooking, meals) ?? nextCookDayOf(meals, day);

  LeftoverMeal warned(CookingMeal m) => LeftoverMeal(
    entryId: m.entryId,
    day: _dateOnly(m.day),
    portions: m.takeOn(day),
    warning: LeftoverWarning.notEnoughLeft,
  );
  if (cookDay == null) {
    // Never cooked: nothing is left, and nothing can be eaten from it.
    return (
      rows: const [],
      meals: [
        for (final m in meals)
          if (!m.removed) warned(m),
      ],
      fridge: 0,
      freezer: 0,
    );
  }

  final title = life?.title ?? cooking.label!;
  final base = cooking.place ?? LeftoverPlace.fridge;
  final inFridge = base == LeftoverPlace.fridge;
  final freezable = life?.freezable ?? false;
  // Words keep the week a recipe with none stated keeps in the fridge, and
  // in the freezer have only an age.
  final fridgeUntil = inFridge
      ? _plus(cookDay, life?.keepsForDays ?? kAssumedFridgeDays)
      : null;
  final freezerUntil = freezable || !inFridge
      ? _plus(cookDay, life?.freezerDays)
      : null;

  // Said gone off: the fridge part is gone for good, whatever is ticked or
  // unticked after. A freezer part still in date that day stays: only what
  // had gone off was said gone. Freezer life runs months, so a cook day an
  // untick moves later does not move that line.
  var fridgeGone = false;
  if (cooking.goneAt case final goneAt?) {
    final goneDay = _dateOnly(goneAt.toLocal());
    final freezerKeeps =
        (freezable || !inFridge) &&
        (freezerUntil == null || !goneDay.isAfter(freezerUntil));
    if (!freezerKeeps) {
      return (
        rows: const [],
        meals: [
          for (final m in meals)
            if (!m.removed && !_dateOnly(m.day).isBefore(day)) warned(m),
        ],
        fridge: 0,
        freezer: 0,
      );
    }
    fridgeGone = true;
  }
  final cooked = cookDayOfCooking(cooking, meals) != null;
  // The assumed freeze happens by the fridge date: until then a freezer
  // meal's portions are still in the fridge.
  final freezePending = fridgeUntil != null && !day.isAfter(fridgeUntil);

  final made = madeOf(cooking, meals);
  var fridge = (inFridge ? made : 0) + input.changes.fridge;
  var freezer = (inFridge ? 0 : made) + input.changes.freezer;
  var spokenFridge = 0.0;
  var spokenFreezer = 0.0;
  final judged = <({LeftoverMeal meal, bool onFridgeRow})>[];
  // A meal taken off the plan has no tag left to judge: it only takes.
  final removed = {
    for (final m in meals)
      if (m.removed) m.entryId,
  };

  for (final m in meals) {
    final mealDay = _dateOnly(m.day);
    final take = m.takeOn(day);
    // A meal removed after it was ticked: eaten, so it takes, and plans
    // nothing more; no tag is left to judge.
    final ahead = !m.removed && !mealDay.isBefore(day);
    if (mealDay.isBefore(cookDay)) {
      // Eaten before it was cooked: a meal of food said by hand planned
      // before its date. A meal skipped before the cook day takes nothing.
      if (take > 1e-9) judged.add((meal: warned(m), onFridgeRow: inFridge));
      continue;
    }
    final inFridgeDate = fridgeUntil == null || !mealDay.isAfter(fridgeUntil);
    final inFreezerDate =
        freezerUntil == null || !mealDay.isAfter(freezerUntil);

    if (inFridge && !inFridgeDate && freezable && inFreezerDate) {
      // A freezer meal: its portions go in the freezer by the fridge date,
      // as far as the freezer has not got them spare already, and as far as
      // the fridge has them: only what is there is frozen. The rest is short.
      final wanted = m.removed ? take : m.portions;
      final covered = min(wanted, freezer > 0 ? freezer : 0.0);
      final needed = wanted - covered;
      final moved = min(needed, fridge > 0 ? fridge : 0.0);
      final short = ahead && needed > moved + 1e-9;
      // Until the fridge date the portions still sit in the fridge, and the
      // meal (and any shortfall) is the fridge row's to say; after it, the
      // freezer's.
      final pending = ahead && freezePending && moved > 1e-9;
      if (pending) {
        fridge -= needed;
        freezer -= covered;
        spokenFridge += needed;
        spokenFreezer += covered;
      } else {
        fridge -= moved;
        freezer += moved - take;
        if (ahead) spokenFreezer += take;
      }
      judged.add((
        meal: LeftoverMeal(
          entryId: m.entryId,
          day: mealDay,
          portions: take,
          place: LeftoverPlace.freezer,
          freezeBy: pending ? fridgeUntil : null,
          warning: short ? LeftoverWarning.notEnoughLeft : null,
        ),
        onFridgeRow: pending,
      ));
      continue;
    }

    // Its own shelf first, then the other's spare; any shortfall is the own
    // shelf's.
    final pastDate = inFridge ? !inFridgeDate : !inFreezerDate;
    final own = inFridge ? fridge : freezer;
    final other = inFridge ? freezer : fridge;
    var fromOwn = min(take, own > 0 ? own : 0.0);
    final fromOther = min(take - fromOwn, other > 0 ? other : 0.0);
    final short = take - fromOwn - fromOther;
    fromOwn += short;
    final fromFridge = inFridge ? fromOwn : fromOther;
    final fromFreezer = inFridge ? fromOther : fromOwn;
    fridge -= fromFridge;
    freezer -= fromFreezer;
    if (ahead) {
      spokenFridge += fromFridge;
      spokenFreezer += fromFreezer;
    }
    final place = fromFreezer > fromFridge + 1e-9
        ? LeftoverPlace.freezer
        : LeftoverPlace.fridge;
    judged.add((
      meal: LeftoverMeal(
        entryId: m.entryId,
        day: mealDay,
        portions: take,
        place: place,
        warning: ahead && short > 1e-9
            ? LeftoverWarning.notEnoughLeft
            : pastDate && (inFridge ? fromFridge : fromFreezer) > 1e-9
            ? LeftoverWarning.pastItsDate
            : null,
      ),
      onFridgeRow: place == LeftoverPlace.fridge,
    ));
  }

  // A fridge part said gone off holds nothing, and shows nothing, ever.
  final fridgeBox = fridgeGone ? 0.0 : fridge + spokenFridge;
  final freezerBox = freezer + spokenFreezer;
  final showFridge = !fridgeGone && (fridgeBox > 1e-9 || spokenFridge > 1e-9);
  final showFreezer = freezerBox > 1e-9 || spokenFreezer > 1e-9;
  List<LeftoverMeal> on({required bool fridgeRow}) => [
    for (final j in judged)
      if (j.onFridgeRow == fridgeRow && !removed.contains(j.meal.entryId))
        j.meal,
  ];
  final fridgeMeals = on(fridgeRow: true);
  final rows = <Leftover>[
    if (showFridge)
      Leftover(
        id: cooking.id,
        place: LeftoverPlace.fridge,
        recipeId: cooking.recipeId,
        title: title,
        since: cookDay,
        goodUntil: fridgeUntil ?? _plus(cookDay, kAssumedFridgeDays),
        box: fridgeBox,
        planned: spokenFridge,
        freezable: freezable,
        freezerUntil: freezerUntil,
        freezeBy:
            fridgeMeals.any((m) => m.freezeBy != null && !m.day.isBefore(day))
            ? fridgeUntil
            : null,
        meals: List.unmodifiable(fridgeMeals),
        alsoOnOtherShelf: showFreezer,
        cooked: cooked,
      ),
    if (showFreezer)
      Leftover(
        id: cooking.id,
        place: LeftoverPlace.freezer,
        recipeId: cooking.recipeId,
        title: title,
        since: cookDay,
        goodUntil: freezerUntil,
        box: freezerBox,
        planned: spokenFreezer,
        freezable: freezable,
        freezerUntil: freezerUntil,
        meals: List.unmodifiable(on(fridgeRow: false)),
        alsoOnOtherShelf: showFridge,
        cooked: cooked,
      ),
  ];
  return (
    rows: rows,
    meals: [
      for (final j in judged)
        if (!removed.contains(j.meal.entryId)) j.meal,
    ],
    fridge: fridgeBox,
    freezer: freezerBox,
  );
}

DateTime? _plus(DateTime day, int? days) =>
    days == null ? null : DateTime(day.year, day.month, day.day + days);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
