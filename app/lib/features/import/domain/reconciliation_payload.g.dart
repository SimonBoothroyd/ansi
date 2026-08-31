// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reconciliation_payload.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TimeRange _$TimeRangeFromJson(Map<String, dynamic> json) => _TimeRange(
  lowSeconds: (json['low_seconds'] as num).toInt(),
  highSeconds: (json['high_seconds'] as num).toInt(),
);

Map<String, dynamic> _$TimeRangeToJson(_TimeRange instance) =>
    <String, dynamic>{
      'low_seconds': instance.lowSeconds,
      'high_seconds': instance.highSeconds,
    };

_RawLineItem _$RawLineItemFromJson(Map<String, dynamic> json) => _RawLineItem(
  ingredientText: json['ingredient_text'] as String,
  qty: (json['qty'] as num?)?.toDouble(),
  qtyLow: (json['qty_low'] as num?)?.toDouble(),
  qtyHigh: (json['qty_high'] as num?)?.toDouble(),
  unit: json['unit'] as String?,
  unitMappable: json['unit_mappable'] as bool? ?? true,
  notes: json['notes'] as String?,
  rawAmount: json['raw_amount'] as String? ?? '',
  optional: json['optional'] as bool? ?? false,
  confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
);

Map<String, dynamic> _$RawLineItemToJson(_RawLineItem instance) =>
    <String, dynamic>{
      'ingredient_text': instance.ingredientText,
      'qty': instance.qty,
      'qty_low': instance.qtyLow,
      'qty_high': instance.qtyHigh,
      'unit': instance.unit,
      'unit_mappable': instance.unitMappable,
      'notes': instance.notes,
      'raw_amount': instance.rawAmount,
      'optional': instance.optional,
      'confidence': instance.confidence,
    };

_MatchCandidate _$MatchCandidateFromJson(Map<String, dynamic> json) =>
    _MatchCandidate(
      ingredientId: json['ingredient_id'] as String,
      canonicalName: json['canonical_name'] as String,
      score: (json['score'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> _$MatchCandidateToJson(_MatchCandidate instance) =>
    <String, dynamic>{
      'ingredient_id': instance.ingredientId,
      'canonical_name': instance.canonicalName,
      'score': instance.score,
    };

_RefPortion _$RefPortionFromJson(Map<String, dynamic> json) => _RefPortion(
  qty: (json['qty'] as num?)?.toDouble(),
  qtyLow: (json['qty_low'] as num?)?.toDouble(),
  qtyHigh: (json['qty_high'] as num?)?.toDouble(),
  unit: json['unit'] as String?,
  qualifier: json['qualifier'] as String?,
);

Map<String, dynamic> _$RefPortionToJson(_RefPortion instance) =>
    <String, dynamic>{
      'qty': instance.qty,
      'qty_low': instance.qtyLow,
      'qty_high': instance.qtyHigh,
      'unit': instance.unit,
      'qualifier': instance.qualifier,
    };

TextToken _$TextTokenFromJson(Map<String, dynamic> json) =>
    TextToken(s: json['s'] as String, $type: json['t'] as String?);

Map<String, dynamic> _$TextTokenToJson(TextToken instance) => <String, dynamic>{
  's': instance.s,
  't': instance.$type,
};

RefToken _$RefTokenFromJson(Map<String, dynamic> json) => RefToken(
  refs: (json['refs'] as List<dynamic>).map((e) => (e as num).toInt()).toList(),
  label: json['label'] as String,
  mention:
      $enumDecodeNullable(_$MentionKindEnumMap, json['mention']) ??
      MentionKind.isNew,
  portion: json['portion'] == null
      ? null
      : RefPortion.fromJson(json['portion'] as Map<String, dynamic>),
  $type: json['t'] as String?,
);

Map<String, dynamic> _$RefTokenToJson(RefToken instance) => <String, dynamic>{
  'refs': instance.refs,
  'label': instance.label,
  'mention': _$MentionKindEnumMap[instance.mention]!,
  'portion': instance.portion,
  't': instance.$type,
};

const _$MentionKindEnumMap = {
  MentionKind.isNew: 'new',
  MentionKind.rementioned: 'rementioned',
  MentionKind.fraction: 'fraction',
};

TimerToken _$TimerTokenFromJson(Map<String, dynamic> json) => TimerToken(
  lowSeconds: (json['low_seconds'] as num).toInt(),
  highSeconds: (json['high_seconds'] as num).toInt(),
  $type: json['t'] as String?,
);

Map<String, dynamic> _$TimerTokenToJson(TimerToken instance) =>
    <String, dynamic>{
      'low_seconds': instance.lowSeconds,
      'high_seconds': instance.highSeconds,
      't': instance.$type,
    };

_Step _$StepFromJson(Map<String, dynamic> json) => _Step(
  tokens:
      (json['tokens'] as List<dynamic>?)
          ?.map((e) => StepToken.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <StepToken>[],
);

Map<String, dynamic> _$StepToJson(_Step instance) => <String, dynamic>{
  'tokens': instance.tokens,
};

_ReconLine _$ReconLineFromJson(Map<String, dynamic> json) => _ReconLine(
  raw: RawLineItem.fromJson(json['raw'] as Map<String, dynamic>),
  band: $enumDecode(_$MatchBandEnumMap, json['band']),
  candidates:
      (json['candidates'] as List<dynamic>?)
          ?.map((e) => MatchCandidate.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MatchCandidate>[],
);

Map<String, dynamic> _$ReconLineToJson(_ReconLine instance) =>
    <String, dynamic>{
      'raw': instance.raw,
      'band': _$MatchBandEnumMap[instance.band]!,
      'candidates': instance.candidates,
    };

const _$MatchBandEnumMap = {
  MatchBand.auto: 'auto',
  MatchBand.suggest: 'suggest',
  MatchBand.none: 'none',
};

_ReconGroup _$ReconGroupFromJson(Map<String, dynamic> json) => _ReconGroup(
  name: json['name'] as String?,
  lines:
      (json['lines'] as List<dynamic>?)
          ?.map((e) => ReconLine.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ReconLine>[],
);

Map<String, dynamic> _$ReconGroupToJson(_ReconGroup instance) =>
    <String, dynamic>{'name': instance.name, 'lines': instance.lines};

_ReconciliationPayload _$ReconciliationPayloadFromJson(
  Map<String, dynamic> json,
) => _ReconciliationPayload(
  title: json['title'] as String,
  servingsBase: (json['servings_base'] as num?)?.toInt(),
  servingsRaw: json['servings_raw'] as String?,
  yieldRaw: json['yield_raw'] as String?,
  totalTimeSeconds: const TimeFieldConverter().fromJson(
    json['total_time_seconds'],
  ),
  cookTimeSeconds: const TimeFieldConverter().fromJson(
    json['cook_time_seconds'],
  ),
  truncated: json['truncated'] as bool? ?? false,
  imageQuality:
      $enumDecodeNullable(_$ImportImageQualityEnumMap, json['image_quality']) ??
      ImportImageQuality.ok,
  parseWarnings:
      (json['parse_warnings'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  groups:
      (json['groups'] as List<dynamic>?)
          ?.map((e) => ReconGroup.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <ReconGroup>[],
  steps:
      (json['steps'] as List<dynamic>?)
          ?.map((e) => Step.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <Step>[],
);

Map<String, dynamic> _$ReconciliationPayloadToJson(
  _ReconciliationPayload instance,
) => <String, dynamic>{
  'title': instance.title,
  'servings_base': instance.servingsBase,
  'servings_raw': instance.servingsRaw,
  'yield_raw': instance.yieldRaw,
  'total_time_seconds': const TimeFieldConverter().toJson(
    instance.totalTimeSeconds,
  ),
  'cook_time_seconds': const TimeFieldConverter().toJson(
    instance.cookTimeSeconds,
  ),
  'truncated': instance.truncated,
  'image_quality': _$ImportImageQualityEnumMap[instance.imageQuality]!,
  'parse_warnings': instance.parseWarnings,
  'groups': instance.groups,
  'steps': instance.steps,
};

const _$ImportImageQualityEnumMap = {
  ImportImageQuality.ok: 'ok',
  ImportImageQuality.degraded: 'degraded',
  ImportImageQuality.poor: 'poor',
};
