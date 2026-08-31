// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'method_step.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_StepPortion _$StepPortionFromJson(Map<String, dynamic> json) => _StepPortion(
  qty: (json['qty'] as num?)?.toDouble(),
  qtyLow: (json['qty_low'] as num?)?.toDouble(),
  qtyHigh: (json['qty_high'] as num?)?.toDouble(),
  unit: json['unit'] as String?,
  qualifier: json['qualifier'] as String?,
);

Map<String, dynamic> _$StepPortionToJson(_StepPortion instance) =>
    <String, dynamic>{
      'qty': instance.qty,
      'qty_low': instance.qtyLow,
      'qty_high': instance.qtyHigh,
      'unit': instance.unit,
      'qualifier': instance.qualifier,
    };

MethodText _$MethodTextFromJson(Map<String, dynamic> json) =>
    MethodText(s: json['s'] as String, $type: json['t'] as String?);

Map<String, dynamic> _$MethodTextToJson(MethodText instance) =>
    <String, dynamic>{'s': instance.s, 't': instance.$type};

MethodRef _$MethodRefFromJson(Map<String, dynamic> json) => MethodRef(
  refs: (json['refs'] as List<dynamic>).map((e) => e as String).toList(),
  label: json['label'] as String,
  mention:
      $enumDecodeNullable(_$StepMentionEnumMap, json['mention']) ??
      StepMention.isNew,
  portion: json['portion'] == null
      ? null
      : StepPortion.fromJson(json['portion'] as Map<String, dynamic>),
  $type: json['t'] as String?,
);

Map<String, dynamic> _$MethodRefToJson(MethodRef instance) => <String, dynamic>{
  'refs': instance.refs,
  'label': instance.label,
  'mention': _$StepMentionEnumMap[instance.mention]!,
  'portion': instance.portion,
  't': instance.$type,
};

const _$StepMentionEnumMap = {
  StepMention.isNew: 'new',
  StepMention.rementioned: 'rementioned',
  StepMention.fraction: 'fraction',
};

MethodTimer _$MethodTimerFromJson(Map<String, dynamic> json) => MethodTimer(
  lowSeconds: (json['low_seconds'] as num).toInt(),
  highSeconds: (json['high_seconds'] as num).toInt(),
  $type: json['t'] as String?,
);

Map<String, dynamic> _$MethodTimerToJson(MethodTimer instance) =>
    <String, dynamic>{
      'low_seconds': instance.lowSeconds,
      'high_seconds': instance.highSeconds,
      't': instance.$type,
    };

_MethodStep _$MethodStepFromJson(Map<String, dynamic> json) => _MethodStep(
  tokens:
      (json['tokens'] as List<dynamic>?)
          ?.map((e) => MethodToken.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <MethodToken>[],
);

Map<String, dynamic> _$MethodStepToJson(_MethodStep instance) =>
    <String, dynamic>{'tokens': instance.tokens};
