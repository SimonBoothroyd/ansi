/// The reconciliation payload — the edge function's output, mirrored in Dart.
///
/// PURE DART (invariant 2): no `package:flutter`. These types mirror the frozen
/// server contract in `supabase/functions/_shared/types.ts`
/// (`ReconciliationPayload` and friends) one-for-one — the real `import-recipe`
/// edge function returns this shape, and the canned test payload parses into
/// it. Field names are camelCase here and serialize to the contract's
/// snake_case via `build.yaml`'s `field_rename`.
///
/// INVARIANT — extraction never invents (0014): absent/ambiguous values arrive
/// as nulls, ranges (`qtyLow`/`qtyHigh`), `unitMappable: false`, or
/// `parseWarnings` — never a guessed number. The reconciliation UI surfaces all
/// of them; it never silently fills one in.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'reconciliation_payload.freezed.dart';
part 'reconciliation_payload.g.dart';

/// The model's honest read of source legibility (photos especially).
enum ImportImageQuality {
  @JsonValue('ok')
  ok,
  @JsonValue('degraded')
  degraded,
  @JsonValue('poor')
  poor,
}

/// Which resolution lane a matched line lands in (§6). `none` carries no
/// candidates — the user resolves it (search / create-new) at reconciliation.
enum MatchBand {
  @JsonValue('auto')
  auto,
  @JsonValue('suggest')
  suggest,
  @JsonValue('none')
  none,
}

/// The LLM's within-recipe classification of a step reference (§4.6). Drives
/// whether the chip renders a number, never the number itself (that is derived
/// live from the line item). `isNew` is the JSON `"new"`.
enum MentionKind {
  @JsonValue('new')
  isNew,
  @JsonValue('rementioned')
  rementioned,
  @JsonValue('fraction')
  fraction,
}

/// A time span in seconds. A single printed time has `low == high`.
@freezed
abstract class TimeRange with _$TimeRange {
  const factory TimeRange({required int lowSeconds, required int highSeconds}) =
      _TimeRange;

  factory TimeRange.fromJson(Map<String, Object?> json) =>
      _$TimeRangeFromJson(json);
}

/// Reads the contract's `TimeField` (`number | {low_seconds, high_seconds} |
/// null`) into a nullable [TimeRange]. A bare number becomes a zero-width
/// range.
class TimeFieldConverter implements JsonConverter<TimeRange?, Object?> {
  const TimeFieldConverter();

  @override
  TimeRange? fromJson(Object? json) {
    if (json == null) return null;
    if (json is num) {
      return TimeRange(lowSeconds: json.toInt(), highSeconds: json.toInt());
    }
    if (json is Map) {
      return TimeRange(
        lowSeconds: (json['low_seconds'] as num).toInt(),
        highSeconds: (json['high_seconds'] as num).toInt(),
      );
    }
    return null;
  }

  @override
  Object? toJson(TimeRange? value) {
    if (value == null) return null;
    if (value.lowSeconds == value.highSeconds) return value.lowSeconds;
    return {'low_seconds': value.lowSeconds, 'high_seconds': value.highSeconds};
  }
}

/// One extracted ingredient line, ingredient-blind and unit-aware. Identity
/// (`ingredientText`) is preserved as-written; only [qty]/[unit] are normalized
/// toward our vocab, and an unmappable amount is preserved + flagged.
@freezed
abstract class RawLineItem with _$RawLineItem {
  const factory RawLineItem({
    required String ingredientText,

    /// A single value; null when the source printed a range (see [qtyLow]).
    double? qty,
    double? qtyLow,
    double? qtyHigh,

    /// Normalized toward the unit vocab; else the printed word (when
    /// [unitMappable] is false).
    String? unit,
    @Default(true) bool unitMappable,

    /// A per-use note ("juiced", "zested", "to serve") — never part of the
    /// ingredient identity we match on. Renamed from `prep` (server contract
    /// rename): the slot also carries usage notes, not only prep transforms.
    String? notes,

    /// The full printed amount, verbatim — never lost (e.g. "2½ x 400g cans").
    @Default('') String rawAmount,
    @Default(false) bool optional,
    @Default(1) double confidence,
  }) = _RawLineItem;

  factory RawLineItem.fromJson(Map<String, Object?> json) =>
      _$RawLineItemFromJson(json);
}

/// A server-scored candidate ingredient for a line (top-N; empty for `none`).
@freezed
abstract class MatchCandidate with _$MatchCandidate {
  const factory MatchCandidate({
    required String ingredientId,
    required String canonicalName,
    @Default(0) double score,
  }) = _MatchCandidate;

  factory MatchCandidate.fromJson(Map<String, Object?> json) =>
      _$MatchCandidateFromJson(json);
}

/// A sub-amount named IN A STEP for one reference (§4.6). Source-derived — a
/// number transcribed from the prose, or a relative [qualifier], never
/// invented.
@freezed
abstract class RefPortion with _$RefPortion {
  const factory RefPortion({
    double? qty,
    double? qtyLow,
    double? qtyHigh,
    String? unit,

    /// A relative word ("the rest" | "half" | "for garnish") with no number.
    String? qualifier,
  }) = _RefPortion;

  factory RefPortion.fromJson(Map<String, Object?> json) =>
      _$RefPortionFromJson(json);
}

/// A step is an ordered token stream (§4.6), rendered by a fold — never
/// render-time text matching. Refs are by **line index** in this payload; the
/// app remaps them to real `line_item_id`s on commit.
@Freezed(unionKey: 't')
sealed class StepToken with _$StepToken {
  /// Plain prose between chips.
  const factory StepToken.text({required String s}) = TextToken;

  /// A chip: [refs] is a flattened line-index list; a set (length > 1) means a
  /// collective chip ("all the remaining ingredients") that shows no number.
  const factory StepToken.ref({
    required List<int> refs,
    required String label,
    @Default(MentionKind.isNew) MentionKind mention,
    RefPortion? portion,
  }) = RefToken;

  /// A timer; a single time has `low == high`.
  const factory StepToken.timer({
    required int lowSeconds,
    required int highSeconds,
  }) = TimerToken;

  factory StepToken.fromJson(Map<String, Object?> json) =>
      _$StepTokenFromJson(json);
}

@freezed
abstract class Step with _$Step {
  const factory Step({@Default(<StepToken>[]) List<StepToken> tokens}) = _Step;

  factory Step.fromJson(Map<String, Object?> json) => _$StepFromJson(json);
}

/// One reconciliation line: the raw extraction, its match [band], and the
/// server's [candidates] (empty for `none`).
@freezed
abstract class ReconLine with _$ReconLine {
  const factory ReconLine({
    required RawLineItem raw,
    required MatchBand band,
    @Default(<MatchCandidate>[]) List<MatchCandidate> candidates,
  }) = _ReconLine;

  factory ReconLine.fromJson(Map<String, Object?> json) =>
      _$ReconLineFromJson(json);
}

@freezed
abstract class ReconGroup with _$ReconGroup {
  const factory ReconGroup({
    String? name,
    @Default(<ReconLine>[]) List<ReconLine> lines,
  }) = _ReconGroup;

  factory ReconGroup.fromJson(Map<String, Object?> json) =>
      _$ReconGroupFromJson(json);
}

/// What `import-recipe` returns. Step refs are still by line index here.
@freezed
abstract class ReconciliationPayload with _$ReconciliationPayload {
  const factory ReconciliationPayload({
    required String title,
    int? servingsBase,
    String? servingsRaw,
    String? yieldRaw,
    @TimeFieldConverter() TimeRange? totalTimeSeconds,
    @TimeFieldConverter() TimeRange? cookTimeSeconds,
    @Default(false) bool truncated,
    @Default(ImportImageQuality.ok) ImportImageQuality imageQuality,
    @Default(<String>[]) List<String> parseWarnings,
    @Default(<ReconGroup>[]) List<ReconGroup> groups,
    @Default(<Step>[]) List<Step> steps,
  }) = _ReconciliationPayload;

  factory ReconciliationPayload.fromJson(Map<String, Object?> json) =>
      _$ReconciliationPayloadFromJson(json);
}

/// The flattened line-index order (§4.6): all lines across all groups, in
/// order. Step refs index into this list, and commit assigns `line_item_id`s in
/// exactly this order.
extension ReconciliationPayloadFlatten on ReconciliationPayload {
  List<ReconLine> get flatLines => [for (final group in groups) ...group.lines];
}
