/// Tokenized method steps + the chip **fold** — PURE DART (invariant 2).
///
/// An imported recipe stores its method as token streams in `recipe.steps`
/// (jsonb): plain [MethodText] spans, [MethodRef] chips (referencing line items
/// by id), and [MethodTimer]s. Rendering walks the tokens through [foldMethod]
/// — there is **no render-time text matching** (that would be the on-device
/// matching ADR-0004 forbids). This is the stored twin of the payload's
/// `StepToken` (import/domain), where refs are still by line index; commit
/// remaps those indices to the `line_item_id`s referenced here.
///
/// A chip's number is derived **live** from its line item, never stored (0014):
///
/// - a step-named [StepPortion] wins (its number is transcribed from the prose);
/// - else the line's scaled quantity shows on the **first** mention
///   (`amountRule == ChipAmountRule.showAmount`);
/// - else the chip is quantity-less;
/// - a **collective** chip (more than one ref) never shows a number.
///
/// A collective chip also carries its [MethodChipSpan.constituents] — the
/// display names of the lines it stands for — so "onion mixture" can render as
/// `onion mixture (onion, celery, green bell pepper)` rather than hiding what
/// went into it. A collective with no label of its own is nothing BUT its
/// constituents, and renders as the bare run (plan 0020 **J1**).
library;

// The library doc above spells out the fold rules as prose; a few of its
// sentences run past 80 cols and read worse hard-wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/units.dart';
import 'recipe.dart';

part 'method_step.freezed.dart';
part 'method_step.g.dart';

/// Whether a chip carries its line's amount — the plain-language name for what
/// §4.6 calls `mention` (0022 D9). The rule, said the way the UI says it: *the
/// first time a step calls for something the chip shows the amount; after that
/// it just names it.*
///
/// The **wire format is untouched** — every value keeps its `@JsonValue`, so
/// the `steps` jsonb and the import payload read and write exactly what they
/// did before the rename.
///
/// [partial] (the JSON `"fraction"`) behaves identically to [hideAmount] in
/// [foldMethod]: such a ref almost always carries a [StepPortion], which wins
/// over the line quantity anyway. The name says "a part of the line" rather
/// than implying a third rendering that does not exist.
enum ChipAmountRule {
  @JsonValue('new')
  showAmount,
  @JsonValue('rementioned')
  hideAmount,
  @JsonValue('fraction')
  partial,
}

/// A sub-amount named in a step for one chip. A number (transcribed from the
/// prose) or a relative [qualifier] — never both, never invented.
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

  /// A chip. [refs] holds the referenced `line_item_id`s — a set (more than
  /// one) is a collective chip that shows no number.
  const factory MethodToken.ref({
    required List<String> refs,
    required String label,

    /// Whether this chip shows its line's amount. The JSON key stays
    /// `mention` (§4.6's frozen contract); only the Dart name is plain
    /// language.
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

/// A rendered piece of a folded step. Views map these to widgets; formatting is
/// already done here so the fold stays the single testable source of truth.
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
/// [constituents] is non-empty only for a COLLECTIVE chip (more than one ref):
/// it holds, in ref order, the display name of every line the chip stands for
/// that still resolves. Refs the payload dropped or demoted resolve to nothing
/// and are simply absent — a dangling chip would be a lie.
///
/// How a view draws them follows from [label]:
///
/// - a **named** collective ("onion mixture") draws the label chip, then the
///   constituents as a parenthesised run of smaller chips;
/// - a **blank-labelled** one ([label] empty) has no label to hang them off, so
///   the constituents ARE the chip run: one full-size chip per name, no
///   parentheses, and any step-named [amount] on the first of them (**J1**).
class MethodChipSpan extends MethodSpan {
  const MethodChipSpan({
    required this.label,
    this.amount,
    this.constituents = const [],
  });
  final String label;
  final String? amount;
  final List<String> constituents;
}

/// A timer chip, its span already formatted ("6–8 min").
class MethodTimerSpan extends MethodSpan {
  const MethodTimerSpan(this.text);
  final String text;
}

/// Folds one [step] into render-ready spans, deriving each chip's number live
/// from [lineById] (scaled by [factor]) per the rules in the library doc.
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
          ),
        );
    }
  }
  return spans;
}

/// The ingredient a chip names. The token's own [label] is the surface text
/// the extractor chose and always wins — but it can arrive blank, and a chip
/// with no label renders as a bare number ("Add the chopped 1, 0.5, 0.25"),
/// which is the worst thing this fold can produce. A blank label on a SINGLE
/// ref therefore falls back to that line item's ingredient name.
///
/// A blank label on a COLLECTIVE stays blank and lets [_constituents] carry the
/// names (plan 0020 **J1**): joining them here made one chip label out of seven
/// ingredients, and a chip is one atomic box to the line breaker, so it ran
/// clean off a phone screen instead of wrapping.
///
/// Still an id lookup, never render-time text matching (ADR-0004).
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

/// The lines a collective chip stands for, in ref order — parenthesised after
/// the label when it has one, and the whole chip run when it hasn't (**J1**).
///
/// Empty for a single ref: there is nothing to unpack.
List<String> _constituents(List<String> refs, Map<String, LineItem> lineById) {
  if (refs.length < 2) return const [];
  return _resolvedNames(refs, lineById);
}

/// The ingredient display names [refs] resolve to, in ref order. A ref the
/// payload dropped (or demoted to a line that never landed) resolves to
/// nothing and is skipped rather than named.
List<String> _resolvedNames(List<String> refs, Map<String, LineItem> lineById) {
  final names = <String>[];
  for (final ref in refs) {
    final name = lineById[ref]?.ingredientName.trim() ?? '';
    if (name.isNotEmpty) names.add(name);
  }
  return names;
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

/// The line's scaled amount as the chip shows it: a count reads as a bare
/// number, an imprecise unit as its word, everything else as "num unit". A
/// numberless line falls back to its unit label.
String? _formatLineAmount(LineItem line, double factor) {
  final measure = line.measure;
  final qty = line.quantity;
  if (qty == null) {
    if (line.unit.family == UnitFamily.imprecise) return line.unit.label;
    return measure?.label;
  }
  final scaled = scale(line.asQuantity!, factor);
  if (measure != null) return '${formatNumber(scaled.amount)} ${measure.label}';
  switch (line.unit.family) {
    case UnitFamily.count:
      return formatNumber(scaled.amount);
    case UnitFamily.imprecise:
      return line.unit.label;
    case UnitFamily.mass:
    case UnitFamily.volume:
    // A component line's `batch` reads like any other unit here ("0.25
    // batch") — the batch↔yield arithmetic belongs to the cook plan, not to
    // a method chip.
    case UnitFamily.batch:
      return '${formatNumber(scaled.amount)} ${line.unit.label}';
  }
}

String? _formatPortion(StepPortion portion, double factor) {
  final unit = portion.unit;
  final suffix = unit == null || unit.isEmpty ? '' : ' $unit';
  if (portion.qty != null) {
    return '${formatNumber(portion.qty! * factor)}$suffix';
  }
  if (portion.qtyLow != null && portion.qtyHigh != null) {
    final low = formatNumber(portion.qtyLow! * factor);
    final high = formatNumber(portion.qtyHigh! * factor);
    return '$low–$high$suffix';
  }
  // A relative word ("half", "for garnish") renders as written — never a made-
  // up number.
  return portion.qualifier;
}

/// Formats a number for a chip: no trailing `.0`, at most two decimals.
String formatNumber(double amount) {
  if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
  return amount
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// Formats a timer span. Whole minutes read as "6 min" / "6–8 min"; an
/// hour or more reads as "2 h 30 min". A sub-minute time keeps its seconds.
String formatTimerRange(int lowSeconds, int highSeconds) {
  if (lowSeconds == highSeconds) return formatDuration(lowSeconds);
  return '${_formatDurationValue(lowSeconds)}–${formatDuration(highSeconds)}';
}

/// Formats one duration in the timer's voice — "35 min", "1 h 10 min",
/// "2 h" — the same words the recipe page's cook/total chips and the header
/// form's TIMES steppers print, so a time reads the same wherever it lands.
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

/// The value half of a range endpoint — the unit label rides on the high end
/// only ("6–8 min"), so the low end drops "min" when both share it.
String _formatDurationValue(int seconds) {
  if (seconds < 60 || seconds % 60 != 0) return formatDuration(seconds);
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes';
  return formatDuration(seconds);
}
