/// Tokenized method steps and the chip fold. Pure Dart.
///
/// A method is stored in `recipe.steps` (jsonb) as token streams: [MethodText],
/// [MethodRef] chips referencing line items by id, and [MethodTimer]s.
/// [foldMethod] renders them; there is no render-time text matching (ADR-0004).
///
/// A chip's number is derived live from its line: a step-named [StepPortion]
/// wins; else the line's scaled quantity shows when `amountRule ==
/// ChipAmountRule.showAmount`; else none. A collective chip (more than one ref)
/// shows no number and carries its [MethodChipSpan.constituents].
library;

// The library doc above spells out the fold rules as prose; a few of its
// sentences run past 80 cols and read worse hard-wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import 'line_display.dart';
import 'recipe.dart';

part 'method_step.freezed.dart';
part 'method_step.g.dart';

/// Whether a chip shows its line's amount: the first mention in a step shows
/// it, later ones only name the line. The JSON values are the wire contract's
/// and must not change. [partial] (JSON `"fraction"`) folds like [hideAmount];
/// such a ref usually carries a [StepPortion].
enum ChipAmountRule {
  @JsonValue('new')
  showAmount,
  @JsonValue('rementioned')
  hideAmount,
  @JsonValue('fraction')
  partial,
}

/// A sub-amount a step names for one chip: a number from the prose or a
/// relative [qualifier], never both.
@freezed
abstract class StepPortion with _$StepPortion {
  const factory StepPortion({
    double? qty,
    double? qtyLow,
    double? qtyHigh,
    String? unit,
    String? qualifier,
  }) = _StepPortion;

  factory StepPortion.fromJson(Map<String, Object?> json) =>
      _$StepPortionFromJson(json);
}

/// A stored step token. Refs are by `line_item_id`; the discriminator is `t`.
@Freezed(unionKey: 't')
sealed class MethodToken with _$MethodToken {
  const factory MethodToken.text({required String s}) = MethodText;

  /// A chip. [refs] holds the referenced `line_item_id`s; more than one is a
  /// collective chip with no number.
  const factory MethodToken.ref({
    required List<String> refs,
    required String label,

    /// Whether this chip shows its line's amount. The JSON key is `mention`.
    @JsonKey(name: 'mention')
    @Default(ChipAmountRule.showAmount)
    ChipAmountRule amountRule,
    StepPortion? portion,
  }) = MethodRef;

  const factory MethodToken.timer({
    required int lowSeconds,
    required int highSeconds,
  }) = MethodTimer;

  factory MethodToken.fromJson(Map<String, Object?> json) =>
      _$MethodTokenFromJson(json);
}

@freezed
abstract class MethodStep with _$MethodStep {
  const factory MethodStep({
    @Default(<MethodToken>[]) List<MethodToken> tokens,
  }) = _MethodStep;

  factory MethodStep.fromJson(Map<String, Object?> json) =>
      _$MethodStepFromJson(json);
}

// --- The fold ----------------------------------------------------------------

/// A rendered piece of a folded step, already formatted.
sealed class MethodSpan {
  const MethodSpan();
}

/// Plain prose.
class MethodTextSpan extends MethodSpan {
  const MethodTextSpan(this.text);
  final String text;
}

/// An ingredient chip. [amount] is null for a quantity-less or collective chip.
///
/// [constituents] is non-empty only for a collective chip: the display names,
/// in ref order, of the lines that still resolve. A named collective draws its
/// label then the constituents in parentheses; a blank-labelled one draws the
/// constituents as the chip run, with any [amount] on the first.
class MethodChipSpan extends MethodSpan {
  const MethodChipSpan({
    required this.label,
    this.amount,
    this.constituents = const [],
    this.lineIds = const [],
  });
  final String label;
  final String? amount;
  final List<String> constituents;

  /// The line ids the chip resolved to, in ref order, parallel to
  /// [constituents]. Lets a view tell whether a chip's line is left out this
  /// week.
  final List<String> lineIds;
}

/// A timer chip, its span already formatted ("6–8 min").
class MethodTimerSpan extends MethodSpan {
  const MethodTimerSpan(this.text);
  final String text;
}

/// Folds one [step] into render-ready spans, deriving each chip's number from
/// [lineById] scaled by [factor].
List<MethodSpan> foldMethod(
  MethodStep step, {
  required Map<String, LineItem> lineById,
  double factor = 1,
}) {
  final spans = <MethodSpan>[];
  for (final token in step.tokens) {
    switch (token) {
      case MethodText(:final s):
        spans.add(MethodTextSpan(s));
      case MethodTimer(:final lowSeconds, :final highSeconds):
        spans.add(MethodTimerSpan(formatTimerRange(lowSeconds, highSeconds)));
      case MethodRef(
        :final refs,
        :final label,
        :final amountRule,
        :final portion,
      ):
        spans.add(
          MethodChipSpan(
            label: _chipLabel(label, refs, lineById),
            amount: _chipAmount(refs, amountRule, portion, lineById, factor),
            constituents: _constituents(refs, lineById),
            lineIds: _resolvedRefs(refs, lineById),
          ),
        );
    }
  }
  return spans;
}

/// A chip's label. The token's own [label] wins; a blank label on a single ref
/// falls back to the line's ingredient name, so a chip never renders as a bare
/// number. A blank collective stays blank and [_constituents] carries the
/// names: one joined label would be an unbreakable box wider than a phone. An
/// id lookup, never text matching (ADR-0004).
String _chipLabel(
  String label,
  List<String> refs,
  Map<String, LineItem> lineById,
) {
  final given = label.trim();
  if (given.isNotEmpty) return given;
  if (refs.length > 1) return '';
  return _resolvedNames(refs, lineById).join(', ');
}

/// The lines a collective chip stands for, in ref order. Empty for a single
/// ref.
List<String> _constituents(List<String> refs, Map<String, LineItem> lineById) {
  if (refs.length < 2) return const [];
  return _resolvedNames(refs, lineById);
}

/// The ingredient display names [refs] resolve to, in ref order, skipping any
/// that do not resolve.
List<String> _resolvedNames(List<String> refs, Map<String, LineItem> lineById) {
  final names = <String>[];
  for (final ref in refs) {
    final name = lineById[ref]?.ingredientName.trim() ?? '';
    if (name.isNotEmpty) names.add(name);
  }
  return names;
}

/// The refs [_resolvedNames] kept, in the same order.
List<String> _resolvedRefs(List<String> refs, Map<String, LineItem> lineById) {
  final resolved = <String>[];
  for (final ref in refs) {
    final name = lineById[ref]?.ingredientName.trim() ?? '';
    if (name.isNotEmpty) resolved.add(ref);
  }
  return resolved;
}

/// The number a chip renders, or null when it is quantity-less.
String? _chipAmount(
  List<String> refs,
  ChipAmountRule amountRule,
  StepPortion? portion,
  Map<String, LineItem> lineById,
  double factor,
) {
  // A step-named portion always wins — its number is source-derived prose.
  if (portion != null) return _formatPortion(portion, factor);
  // A collective chip ("the remaining ingredients") never shows a number.
  if (refs.length != 1) return null;
  // Otherwise the line's own quantity, but only on the first mention.
  if (amountRule != ChipAmountRule.showAmount) return null;
  final line = lineById[refs.single];
  if (line == null) return null;
  return _formatLineAmount(line, factor);
}

/// The line's scaled amount as a chip shows it: a count as a bare number, an
/// imprecise unit as its word, otherwise "num unit". A numberless line shows
/// its unit label.
String? _formatLineAmount(LineItem line, double factor) {
  final measure = line.measure;
  final word = recipeMeasureOfLine(line);
  final unit = line.unit;
  final qty = line.quantity;
  if (qty == null) {
    if (unit?.family == UnitFamily.imprecise) return unit?.label;
    return measure?.label ?? word?.label;
  }
  // A line in one of the target recipe's words scales as a count of that word.
  if (word != null) {
    return measuredAmountText(qty * factor, word.label);
  }
  if (unit == null) return formatAmount(qty * factor);
  final scaled = scale(Quantity(qty, unit), factor);
  if (measure != null) return '${formatAmount(scaled.amount)} ${measure.label}';
  switch (unit.family) {
    case UnitFamily.count:
      return formatAmount(scaled.amount);
    case UnitFamily.imprecise:
      return unit.label;
    case UnitFamily.mass:
    case UnitFamily.volume:
    // `batch` reads like any other unit here; batch↔yield math belongs to the
    // cook plan.
    case UnitFamily.batch:
      return '${formatAmountIn(scaled.amount, unit)} ${unit.label}';
  }
}

String? _formatPortion(StepPortion portion, double factor) {
  final unit = portion.unit;
  final suffix = unit == null || unit.isEmpty ? '' : ' $unit';
  if (portion.qty != null) {
    return '${formatAmount(portion.qty! * factor)}$suffix';
  }
  if (portion.qtyLow != null && portion.qtyHigh != null) {
    final low = formatAmount(portion.qtyLow! * factor);
    final high = formatAmount(portion.qtyHigh! * factor);
    return '$low–$high$suffix';
  }
  // A relative word ("half", "for garnish") renders as written.
  return portion.qualifier;
}

/// A timer span: "6 min", "6–8 min", "2 h 30 min"; a sub-minute time keeps its
/// seconds.
String formatTimerRange(int lowSeconds, int highSeconds) {
  if (lowSeconds == highSeconds) return formatDuration(lowSeconds);
  return '${_formatDurationValue(lowSeconds)}–${formatDuration(highSeconds)}';
}

/// One duration: "35 min", "1 h 10 min", "2 h". Shared with the recipe page's
/// time chips and the header form's steppers.
String formatDuration(int seconds) {
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  final remMinutes = minutes % 60;
  if (seconds % 60 != 0) {
    // Uncommon; keep it honest rather than rounding a printed time away.
    return '$minutes min ${seconds % 60} s';
  }
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  return remMinutes == 0 ? '$hours h' : '$hours h $remMinutes min';
}

/// A range endpoint's value; the low end drops "min" when both ends share it.
String _formatDurationValue(int seconds) {
  if (seconds < 60 || seconds % 60 != 0) return formatDuration(seconds);
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes';
  return formatDuration(seconds);
}
