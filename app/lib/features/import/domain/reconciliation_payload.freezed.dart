// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reconciliation_payload.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TimeRange {

 int get lowSeconds; int get highSeconds;
/// Create a copy of TimeRange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimeRangeCopyWith<TimeRange> get copyWith => _$TimeRangeCopyWithImpl<TimeRange>(this as TimeRange, _$identity);

  /// Serializes this TimeRange to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimeRange&&(identical(other.lowSeconds, lowSeconds) || other.lowSeconds == lowSeconds)&&(identical(other.highSeconds, highSeconds) || other.highSeconds == highSeconds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,lowSeconds,highSeconds);

@override
String toString() {
  return 'TimeRange(lowSeconds: $lowSeconds, highSeconds: $highSeconds)';
}


}

/// @nodoc
abstract mixin class $TimeRangeCopyWith<$Res>  {
  factory $TimeRangeCopyWith(TimeRange value, $Res Function(TimeRange) _then) = _$TimeRangeCopyWithImpl;
@useResult
$Res call({
 int lowSeconds, int highSeconds
});




}
/// @nodoc
class _$TimeRangeCopyWithImpl<$Res>
    implements $TimeRangeCopyWith<$Res> {
  _$TimeRangeCopyWithImpl(this._self, this._then);

  final TimeRange _self;
  final $Res Function(TimeRange) _then;

/// Create a copy of TimeRange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lowSeconds = null,Object? highSeconds = null,}) {
  return _then(_self.copyWith(
lowSeconds: null == lowSeconds ? _self.lowSeconds : lowSeconds // ignore: cast_nullable_to_non_nullable
as int,highSeconds: null == highSeconds ? _self.highSeconds : highSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [TimeRange].
extension TimeRangePatterns on TimeRange {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimeRange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimeRange() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimeRange value)  $default,){
final _that = this;
switch (_that) {
case _TimeRange():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimeRange value)?  $default,){
final _that = this;
switch (_that) {
case _TimeRange() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int lowSeconds,  int highSeconds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimeRange() when $default != null:
return $default(_that.lowSeconds,_that.highSeconds);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int lowSeconds,  int highSeconds)  $default,) {final _that = this;
switch (_that) {
case _TimeRange():
return $default(_that.lowSeconds,_that.highSeconds);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int lowSeconds,  int highSeconds)?  $default,) {final _that = this;
switch (_that) {
case _TimeRange() when $default != null:
return $default(_that.lowSeconds,_that.highSeconds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TimeRange implements TimeRange {
  const _TimeRange({required this.lowSeconds, required this.highSeconds});
  factory _TimeRange.fromJson(Map<String, dynamic> json) => _$TimeRangeFromJson(json);

@override final  int lowSeconds;
@override final  int highSeconds;

/// Create a copy of TimeRange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimeRangeCopyWith<_TimeRange> get copyWith => __$TimeRangeCopyWithImpl<_TimeRange>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TimeRangeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimeRange&&(identical(other.lowSeconds, lowSeconds) || other.lowSeconds == lowSeconds)&&(identical(other.highSeconds, highSeconds) || other.highSeconds == highSeconds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,lowSeconds,highSeconds);

@override
String toString() {
  return 'TimeRange(lowSeconds: $lowSeconds, highSeconds: $highSeconds)';
}


}

/// @nodoc
abstract mixin class _$TimeRangeCopyWith<$Res> implements $TimeRangeCopyWith<$Res> {
  factory _$TimeRangeCopyWith(_TimeRange value, $Res Function(_TimeRange) _then) = __$TimeRangeCopyWithImpl;
@override @useResult
$Res call({
 int lowSeconds, int highSeconds
});




}
/// @nodoc
class __$TimeRangeCopyWithImpl<$Res>
    implements _$TimeRangeCopyWith<$Res> {
  __$TimeRangeCopyWithImpl(this._self, this._then);

  final _TimeRange _self;
  final $Res Function(_TimeRange) _then;

/// Create a copy of TimeRange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? lowSeconds = null,Object? highSeconds = null,}) {
  return _then(_TimeRange(
lowSeconds: null == lowSeconds ? _self.lowSeconds : lowSeconds // ignore: cast_nullable_to_non_nullable
as int,highSeconds: null == highSeconds ? _self.highSeconds : highSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$RawLineItem {

 String get ingredientText;/// A single value; null when the source printed a range (see [qtyLow]).
 double? get qty; double? get qtyLow; double? get qtyHigh;/// Normalized toward the unit vocab; else the printed word (when
/// [unitMappable] is false).
 String? get unit; bool get unitMappable;/// A per-use note ("juiced", "zested", "to serve") — never part of the
/// ingredient identity we match on. Renamed from `prep` (server contract
/// rename): the slot also carries usage notes, not only prep transforms.
 String? get notes;/// The full printed amount, verbatim — never lost (e.g. "2½ x 400g cans").
 String get rawAmount; bool get optional; double get confidence;
/// Create a copy of RawLineItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RawLineItemCopyWith<RawLineItem> get copyWith => _$RawLineItemCopyWithImpl<RawLineItem>(this as RawLineItem, _$identity);

  /// Serializes this RawLineItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RawLineItem&&(identical(other.ingredientText, ingredientText) || other.ingredientText == ingredientText)&&(identical(other.qty, qty) || other.qty == qty)&&(identical(other.qtyLow, qtyLow) || other.qtyLow == qtyLow)&&(identical(other.qtyHigh, qtyHigh) || other.qtyHigh == qtyHigh)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.unitMappable, unitMappable) || other.unitMappable == unitMappable)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.rawAmount, rawAmount) || other.rawAmount == rawAmount)&&(identical(other.optional, optional) || other.optional == optional)&&(identical(other.confidence, confidence) || other.confidence == confidence));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ingredientText,qty,qtyLow,qtyHigh,unit,unitMappable,notes,rawAmount,optional,confidence);

@override
String toString() {
  return 'RawLineItem(ingredientText: $ingredientText, qty: $qty, qtyLow: $qtyLow, qtyHigh: $qtyHigh, unit: $unit, unitMappable: $unitMappable, notes: $notes, rawAmount: $rawAmount, optional: $optional, confidence: $confidence)';
}


}

/// @nodoc
abstract mixin class $RawLineItemCopyWith<$Res>  {
  factory $RawLineItemCopyWith(RawLineItem value, $Res Function(RawLineItem) _then) = _$RawLineItemCopyWithImpl;
@useResult
$Res call({
 String ingredientText, double? qty, double? qtyLow, double? qtyHigh, String? unit, bool unitMappable, String? notes, String rawAmount, bool optional, double confidence
});




}
/// @nodoc
class _$RawLineItemCopyWithImpl<$Res>
    implements $RawLineItemCopyWith<$Res> {
  _$RawLineItemCopyWithImpl(this._self, this._then);

  final RawLineItem _self;
  final $Res Function(RawLineItem) _then;

/// Create a copy of RawLineItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ingredientText = null,Object? qty = freezed,Object? qtyLow = freezed,Object? qtyHigh = freezed,Object? unit = freezed,Object? unitMappable = null,Object? notes = freezed,Object? rawAmount = null,Object? optional = null,Object? confidence = null,}) {
  return _then(_self.copyWith(
ingredientText: null == ingredientText ? _self.ingredientText : ingredientText // ignore: cast_nullable_to_non_nullable
as String,qty: freezed == qty ? _self.qty : qty // ignore: cast_nullable_to_non_nullable
as double?,qtyLow: freezed == qtyLow ? _self.qtyLow : qtyLow // ignore: cast_nullable_to_non_nullable
as double?,qtyHigh: freezed == qtyHigh ? _self.qtyHigh : qtyHigh // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,unitMappable: null == unitMappable ? _self.unitMappable : unitMappable // ignore: cast_nullable_to_non_nullable
as bool,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,rawAmount: null == rawAmount ? _self.rawAmount : rawAmount // ignore: cast_nullable_to_non_nullable
as String,optional: null == optional ? _self.optional : optional // ignore: cast_nullable_to_non_nullable
as bool,confidence: null == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [RawLineItem].
extension RawLineItemPatterns on RawLineItem {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RawLineItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RawLineItem() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RawLineItem value)  $default,){
final _that = this;
switch (_that) {
case _RawLineItem():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RawLineItem value)?  $default,){
final _that = this;
switch (_that) {
case _RawLineItem() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ingredientText,  double? qty,  double? qtyLow,  double? qtyHigh,  String? unit,  bool unitMappable,  String? notes,  String rawAmount,  bool optional,  double confidence)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RawLineItem() when $default != null:
return $default(_that.ingredientText,_that.qty,_that.qtyLow,_that.qtyHigh,_that.unit,_that.unitMappable,_that.notes,_that.rawAmount,_that.optional,_that.confidence);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ingredientText,  double? qty,  double? qtyLow,  double? qtyHigh,  String? unit,  bool unitMappable,  String? notes,  String rawAmount,  bool optional,  double confidence)  $default,) {final _that = this;
switch (_that) {
case _RawLineItem():
return $default(_that.ingredientText,_that.qty,_that.qtyLow,_that.qtyHigh,_that.unit,_that.unitMappable,_that.notes,_that.rawAmount,_that.optional,_that.confidence);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ingredientText,  double? qty,  double? qtyLow,  double? qtyHigh,  String? unit,  bool unitMappable,  String? notes,  String rawAmount,  bool optional,  double confidence)?  $default,) {final _that = this;
switch (_that) {
case _RawLineItem() when $default != null:
return $default(_that.ingredientText,_that.qty,_that.qtyLow,_that.qtyHigh,_that.unit,_that.unitMappable,_that.notes,_that.rawAmount,_that.optional,_that.confidence);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RawLineItem implements RawLineItem {
  const _RawLineItem({required this.ingredientText, this.qty, this.qtyLow, this.qtyHigh, this.unit, this.unitMappable = true, this.notes, this.rawAmount = '', this.optional = false, this.confidence = 1});
  factory _RawLineItem.fromJson(Map<String, dynamic> json) => _$RawLineItemFromJson(json);

@override final  String ingredientText;
/// A single value; null when the source printed a range (see [qtyLow]).
@override final  double? qty;
@override final  double? qtyLow;
@override final  double? qtyHigh;
/// Normalized toward the unit vocab; else the printed word (when
/// [unitMappable] is false).
@override final  String? unit;
@override@JsonKey() final  bool unitMappable;
/// A per-use note ("juiced", "zested", "to serve") — never part of the
/// ingredient identity we match on. Renamed from `prep` (server contract
/// rename): the slot also carries usage notes, not only prep transforms.
@override final  String? notes;
/// The full printed amount, verbatim — never lost (e.g. "2½ x 400g cans").
@override@JsonKey() final  String rawAmount;
@override@JsonKey() final  bool optional;
@override@JsonKey() final  double confidence;

/// Create a copy of RawLineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RawLineItemCopyWith<_RawLineItem> get copyWith => __$RawLineItemCopyWithImpl<_RawLineItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RawLineItemToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RawLineItem&&(identical(other.ingredientText, ingredientText) || other.ingredientText == ingredientText)&&(identical(other.qty, qty) || other.qty == qty)&&(identical(other.qtyLow, qtyLow) || other.qtyLow == qtyLow)&&(identical(other.qtyHigh, qtyHigh) || other.qtyHigh == qtyHigh)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.unitMappable, unitMappable) || other.unitMappable == unitMappable)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.rawAmount, rawAmount) || other.rawAmount == rawAmount)&&(identical(other.optional, optional) || other.optional == optional)&&(identical(other.confidence, confidence) || other.confidence == confidence));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ingredientText,qty,qtyLow,qtyHigh,unit,unitMappable,notes,rawAmount,optional,confidence);

@override
String toString() {
  return 'RawLineItem(ingredientText: $ingredientText, qty: $qty, qtyLow: $qtyLow, qtyHigh: $qtyHigh, unit: $unit, unitMappable: $unitMappable, notes: $notes, rawAmount: $rawAmount, optional: $optional, confidence: $confidence)';
}


}

/// @nodoc
abstract mixin class _$RawLineItemCopyWith<$Res> implements $RawLineItemCopyWith<$Res> {
  factory _$RawLineItemCopyWith(_RawLineItem value, $Res Function(_RawLineItem) _then) = __$RawLineItemCopyWithImpl;
@override @useResult
$Res call({
 String ingredientText, double? qty, double? qtyLow, double? qtyHigh, String? unit, bool unitMappable, String? notes, String rawAmount, bool optional, double confidence
});




}
/// @nodoc
class __$RawLineItemCopyWithImpl<$Res>
    implements _$RawLineItemCopyWith<$Res> {
  __$RawLineItemCopyWithImpl(this._self, this._then);

  final _RawLineItem _self;
  final $Res Function(_RawLineItem) _then;

/// Create a copy of RawLineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ingredientText = null,Object? qty = freezed,Object? qtyLow = freezed,Object? qtyHigh = freezed,Object? unit = freezed,Object? unitMappable = null,Object? notes = freezed,Object? rawAmount = null,Object? optional = null,Object? confidence = null,}) {
  return _then(_RawLineItem(
ingredientText: null == ingredientText ? _self.ingredientText : ingredientText // ignore: cast_nullable_to_non_nullable
as String,qty: freezed == qty ? _self.qty : qty // ignore: cast_nullable_to_non_nullable
as double?,qtyLow: freezed == qtyLow ? _self.qtyLow : qtyLow // ignore: cast_nullable_to_non_nullable
as double?,qtyHigh: freezed == qtyHigh ? _self.qtyHigh : qtyHigh // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,unitMappable: null == unitMappable ? _self.unitMappable : unitMappable // ignore: cast_nullable_to_non_nullable
as bool,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,rawAmount: null == rawAmount ? _self.rawAmount : rawAmount // ignore: cast_nullable_to_non_nullable
as String,optional: null == optional ? _self.optional : optional // ignore: cast_nullable_to_non_nullable
as bool,confidence: null == confidence ? _self.confidence : confidence // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$SourceSpan {

 int get start; int get end;
/// Create a copy of SourceSpan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourceSpanCopyWith<SourceSpan> get copyWith => _$SourceSpanCopyWithImpl<SourceSpan>(this as SourceSpan, _$identity);

  /// Serializes this SourceSpan to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceSpan&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,start,end);

@override
String toString() {
  return 'SourceSpan(start: $start, end: $end)';
}


}

/// @nodoc
abstract mixin class $SourceSpanCopyWith<$Res>  {
  factory $SourceSpanCopyWith(SourceSpan value, $Res Function(SourceSpan) _then) = _$SourceSpanCopyWithImpl;
@useResult
$Res call({
 int start, int end
});




}
/// @nodoc
class _$SourceSpanCopyWithImpl<$Res>
    implements $SourceSpanCopyWith<$Res> {
  _$SourceSpanCopyWithImpl(this._self, this._then);

  final SourceSpan _self;
  final $Res Function(SourceSpan) _then;

/// Create a copy of SourceSpan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? start = null,Object? end = null,}) {
  return _then(_self.copyWith(
start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as int,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [SourceSpan].
extension SourceSpanPatterns on SourceSpan {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SourceSpan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SourceSpan() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SourceSpan value)  $default,){
final _that = this;
switch (_that) {
case _SourceSpan():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SourceSpan value)?  $default,){
final _that = this;
switch (_that) {
case _SourceSpan() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int start,  int end)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SourceSpan() when $default != null:
return $default(_that.start,_that.end);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int start,  int end)  $default,) {final _that = this;
switch (_that) {
case _SourceSpan():
return $default(_that.start,_that.end);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int start,  int end)?  $default,) {final _that = this;
switch (_that) {
case _SourceSpan() when $default != null:
return $default(_that.start,_that.end);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SourceSpan implements SourceSpan {
  const _SourceSpan({required this.start, required this.end});
  factory _SourceSpan.fromJson(Map<String, dynamic> json) => _$SourceSpanFromJson(json);

@override final  int start;
@override final  int end;

/// Create a copy of SourceSpan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SourceSpanCopyWith<_SourceSpan> get copyWith => __$SourceSpanCopyWithImpl<_SourceSpan>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SourceSpanToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SourceSpan&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,start,end);

@override
String toString() {
  return 'SourceSpan(start: $start, end: $end)';
}


}

/// @nodoc
abstract mixin class _$SourceSpanCopyWith<$Res> implements $SourceSpanCopyWith<$Res> {
  factory _$SourceSpanCopyWith(_SourceSpan value, $Res Function(_SourceSpan) _then) = __$SourceSpanCopyWithImpl;
@override @useResult
$Res call({
 int start, int end
});




}
/// @nodoc
class __$SourceSpanCopyWithImpl<$Res>
    implements _$SourceSpanCopyWith<$Res> {
  __$SourceSpanCopyWithImpl(this._self, this._then);

  final _SourceSpan _self;
  final $Res Function(_SourceSpan) _then;

/// Create a copy of SourceSpan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? start = null,Object? end = null,}) {
  return _then(_SourceSpan(
start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as int,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$MatchCandidate {

 String get ingredientId; String get canonicalName; double get score;
/// Create a copy of MatchCandidate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MatchCandidateCopyWith<MatchCandidate> get copyWith => _$MatchCandidateCopyWithImpl<MatchCandidate>(this as MatchCandidate, _$identity);

  /// Serializes this MatchCandidate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MatchCandidate&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.canonicalName, canonicalName) || other.canonicalName == canonicalName)&&(identical(other.score, score) || other.score == score));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ingredientId,canonicalName,score);

@override
String toString() {
  return 'MatchCandidate(ingredientId: $ingredientId, canonicalName: $canonicalName, score: $score)';
}


}

/// @nodoc
abstract mixin class $MatchCandidateCopyWith<$Res>  {
  factory $MatchCandidateCopyWith(MatchCandidate value, $Res Function(MatchCandidate) _then) = _$MatchCandidateCopyWithImpl;
@useResult
$Res call({
 String ingredientId, String canonicalName, double score
});




}
/// @nodoc
class _$MatchCandidateCopyWithImpl<$Res>
    implements $MatchCandidateCopyWith<$Res> {
  _$MatchCandidateCopyWithImpl(this._self, this._then);

  final MatchCandidate _self;
  final $Res Function(MatchCandidate) _then;

/// Create a copy of MatchCandidate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ingredientId = null,Object? canonicalName = null,Object? score = null,}) {
  return _then(_self.copyWith(
ingredientId: null == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String,canonicalName: null == canonicalName ? _self.canonicalName : canonicalName // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [MatchCandidate].
extension MatchCandidatePatterns on MatchCandidate {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MatchCandidate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MatchCandidate() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MatchCandidate value)  $default,){
final _that = this;
switch (_that) {
case _MatchCandidate():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MatchCandidate value)?  $default,){
final _that = this;
switch (_that) {
case _MatchCandidate() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ingredientId,  String canonicalName,  double score)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MatchCandidate() when $default != null:
return $default(_that.ingredientId,_that.canonicalName,_that.score);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ingredientId,  String canonicalName,  double score)  $default,) {final _that = this;
switch (_that) {
case _MatchCandidate():
return $default(_that.ingredientId,_that.canonicalName,_that.score);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ingredientId,  String canonicalName,  double score)?  $default,) {final _that = this;
switch (_that) {
case _MatchCandidate() when $default != null:
return $default(_that.ingredientId,_that.canonicalName,_that.score);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MatchCandidate implements MatchCandidate {
  const _MatchCandidate({required this.ingredientId, required this.canonicalName, this.score = 0});
  factory _MatchCandidate.fromJson(Map<String, dynamic> json) => _$MatchCandidateFromJson(json);

@override final  String ingredientId;
@override final  String canonicalName;
@override@JsonKey() final  double score;

/// Create a copy of MatchCandidate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MatchCandidateCopyWith<_MatchCandidate> get copyWith => __$MatchCandidateCopyWithImpl<_MatchCandidate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MatchCandidateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MatchCandidate&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.canonicalName, canonicalName) || other.canonicalName == canonicalName)&&(identical(other.score, score) || other.score == score));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,ingredientId,canonicalName,score);

@override
String toString() {
  return 'MatchCandidate(ingredientId: $ingredientId, canonicalName: $canonicalName, score: $score)';
}


}

/// @nodoc
abstract mixin class _$MatchCandidateCopyWith<$Res> implements $MatchCandidateCopyWith<$Res> {
  factory _$MatchCandidateCopyWith(_MatchCandidate value, $Res Function(_MatchCandidate) _then) = __$MatchCandidateCopyWithImpl;
@override @useResult
$Res call({
 String ingredientId, String canonicalName, double score
});




}
/// @nodoc
class __$MatchCandidateCopyWithImpl<$Res>
    implements _$MatchCandidateCopyWith<$Res> {
  __$MatchCandidateCopyWithImpl(this._self, this._then);

  final _MatchCandidate _self;
  final $Res Function(_MatchCandidate) _then;

/// Create a copy of MatchCandidate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ingredientId = null,Object? canonicalName = null,Object? score = null,}) {
  return _then(_MatchCandidate(
ingredientId: null == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String,canonicalName: null == canonicalName ? _self.canonicalName : canonicalName // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$RecipeCandidate {

 String get recipeId;/// The recipe's title as stored — the chip's display text.
 String get title;/// 1 for an exact normalized-title hit, else trigram similarity.
 double get score;
/// Create a copy of RecipeCandidate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecipeCandidateCopyWith<RecipeCandidate> get copyWith => _$RecipeCandidateCopyWithImpl<RecipeCandidate>(this as RecipeCandidate, _$identity);

  /// Serializes this RecipeCandidate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecipeCandidate&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.score, score) || other.score == score));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,recipeId,title,score);

@override
String toString() {
  return 'RecipeCandidate(recipeId: $recipeId, title: $title, score: $score)';
}


}

/// @nodoc
abstract mixin class $RecipeCandidateCopyWith<$Res>  {
  factory $RecipeCandidateCopyWith(RecipeCandidate value, $Res Function(RecipeCandidate) _then) = _$RecipeCandidateCopyWithImpl;
@useResult
$Res call({
 String recipeId, String title, double score
});




}
/// @nodoc
class _$RecipeCandidateCopyWithImpl<$Res>
    implements $RecipeCandidateCopyWith<$Res> {
  _$RecipeCandidateCopyWithImpl(this._self, this._then);

  final RecipeCandidate _self;
  final $Res Function(RecipeCandidate) _then;

/// Create a copy of RecipeCandidate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? recipeId = null,Object? title = null,Object? score = null,}) {
  return _then(_self.copyWith(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [RecipeCandidate].
extension RecipeCandidatePatterns on RecipeCandidate {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecipeCandidate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecipeCandidate() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecipeCandidate value)  $default,){
final _that = this;
switch (_that) {
case _RecipeCandidate():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecipeCandidate value)?  $default,){
final _that = this;
switch (_that) {
case _RecipeCandidate() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String recipeId,  String title,  double score)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecipeCandidate() when $default != null:
return $default(_that.recipeId,_that.title,_that.score);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String recipeId,  String title,  double score)  $default,) {final _that = this;
switch (_that) {
case _RecipeCandidate():
return $default(_that.recipeId,_that.title,_that.score);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String recipeId,  String title,  double score)?  $default,) {final _that = this;
switch (_that) {
case _RecipeCandidate() when $default != null:
return $default(_that.recipeId,_that.title,_that.score);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RecipeCandidate implements RecipeCandidate {
  const _RecipeCandidate({required this.recipeId, required this.title, this.score = 0});
  factory _RecipeCandidate.fromJson(Map<String, dynamic> json) => _$RecipeCandidateFromJson(json);

@override final  String recipeId;
/// The recipe's title as stored — the chip's display text.
@override final  String title;
/// 1 for an exact normalized-title hit, else trigram similarity.
@override@JsonKey() final  double score;

/// Create a copy of RecipeCandidate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecipeCandidateCopyWith<_RecipeCandidate> get copyWith => __$RecipeCandidateCopyWithImpl<_RecipeCandidate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RecipeCandidateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecipeCandidate&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.score, score) || other.score == score));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,recipeId,title,score);

@override
String toString() {
  return 'RecipeCandidate(recipeId: $recipeId, title: $title, score: $score)';
}


}

/// @nodoc
abstract mixin class _$RecipeCandidateCopyWith<$Res> implements $RecipeCandidateCopyWith<$Res> {
  factory _$RecipeCandidateCopyWith(_RecipeCandidate value, $Res Function(_RecipeCandidate) _then) = __$RecipeCandidateCopyWithImpl;
@override @useResult
$Res call({
 String recipeId, String title, double score
});




}
/// @nodoc
class __$RecipeCandidateCopyWithImpl<$Res>
    implements _$RecipeCandidateCopyWith<$Res> {
  __$RecipeCandidateCopyWithImpl(this._self, this._then);

  final _RecipeCandidate _self;
  final $Res Function(_RecipeCandidate) _then;

/// Create a copy of RecipeCandidate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? recipeId = null,Object? title = null,Object? score = null,}) {
  return _then(_RecipeCandidate(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$RefPortion {

 double? get qty; double? get qtyLow; double? get qtyHigh; String? get unit;/// A relative word ("the rest" | "half" | "for garnish") with no number.
 String? get qualifier;
/// Create a copy of RefPortion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RefPortionCopyWith<RefPortion> get copyWith => _$RefPortionCopyWithImpl<RefPortion>(this as RefPortion, _$identity);

  /// Serializes this RefPortion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RefPortion&&(identical(other.qty, qty) || other.qty == qty)&&(identical(other.qtyLow, qtyLow) || other.qtyLow == qtyLow)&&(identical(other.qtyHigh, qtyHigh) || other.qtyHigh == qtyHigh)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.qualifier, qualifier) || other.qualifier == qualifier));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,qty,qtyLow,qtyHigh,unit,qualifier);

@override
String toString() {
  return 'RefPortion(qty: $qty, qtyLow: $qtyLow, qtyHigh: $qtyHigh, unit: $unit, qualifier: $qualifier)';
}


}

/// @nodoc
abstract mixin class $RefPortionCopyWith<$Res>  {
  factory $RefPortionCopyWith(RefPortion value, $Res Function(RefPortion) _then) = _$RefPortionCopyWithImpl;
@useResult
$Res call({
 double? qty, double? qtyLow, double? qtyHigh, String? unit, String? qualifier
});




}
/// @nodoc
class _$RefPortionCopyWithImpl<$Res>
    implements $RefPortionCopyWith<$Res> {
  _$RefPortionCopyWithImpl(this._self, this._then);

  final RefPortion _self;
  final $Res Function(RefPortion) _then;

/// Create a copy of RefPortion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? qty = freezed,Object? qtyLow = freezed,Object? qtyHigh = freezed,Object? unit = freezed,Object? qualifier = freezed,}) {
  return _then(_self.copyWith(
qty: freezed == qty ? _self.qty : qty // ignore: cast_nullable_to_non_nullable
as double?,qtyLow: freezed == qtyLow ? _self.qtyLow : qtyLow // ignore: cast_nullable_to_non_nullable
as double?,qtyHigh: freezed == qtyHigh ? _self.qtyHigh : qtyHigh // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,qualifier: freezed == qualifier ? _self.qualifier : qualifier // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [RefPortion].
extension RefPortionPatterns on RefPortion {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RefPortion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RefPortion() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RefPortion value)  $default,){
final _that = this;
switch (_that) {
case _RefPortion():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RefPortion value)?  $default,){
final _that = this;
switch (_that) {
case _RefPortion() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double? qty,  double? qtyLow,  double? qtyHigh,  String? unit,  String? qualifier)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RefPortion() when $default != null:
return $default(_that.qty,_that.qtyLow,_that.qtyHigh,_that.unit,_that.qualifier);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double? qty,  double? qtyLow,  double? qtyHigh,  String? unit,  String? qualifier)  $default,) {final _that = this;
switch (_that) {
case _RefPortion():
return $default(_that.qty,_that.qtyLow,_that.qtyHigh,_that.unit,_that.qualifier);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double? qty,  double? qtyLow,  double? qtyHigh,  String? unit,  String? qualifier)?  $default,) {final _that = this;
switch (_that) {
case _RefPortion() when $default != null:
return $default(_that.qty,_that.qtyLow,_that.qtyHigh,_that.unit,_that.qualifier);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RefPortion implements RefPortion {
  const _RefPortion({this.qty, this.qtyLow, this.qtyHigh, this.unit, this.qualifier});
  factory _RefPortion.fromJson(Map<String, dynamic> json) => _$RefPortionFromJson(json);

@override final  double? qty;
@override final  double? qtyLow;
@override final  double? qtyHigh;
@override final  String? unit;
/// A relative word ("the rest" | "half" | "for garnish") with no number.
@override final  String? qualifier;

/// Create a copy of RefPortion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RefPortionCopyWith<_RefPortion> get copyWith => __$RefPortionCopyWithImpl<_RefPortion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RefPortionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RefPortion&&(identical(other.qty, qty) || other.qty == qty)&&(identical(other.qtyLow, qtyLow) || other.qtyLow == qtyLow)&&(identical(other.qtyHigh, qtyHigh) || other.qtyHigh == qtyHigh)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.qualifier, qualifier) || other.qualifier == qualifier));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,qty,qtyLow,qtyHigh,unit,qualifier);

@override
String toString() {
  return 'RefPortion(qty: $qty, qtyLow: $qtyLow, qtyHigh: $qtyHigh, unit: $unit, qualifier: $qualifier)';
}


}

/// @nodoc
abstract mixin class _$RefPortionCopyWith<$Res> implements $RefPortionCopyWith<$Res> {
  factory _$RefPortionCopyWith(_RefPortion value, $Res Function(_RefPortion) _then) = __$RefPortionCopyWithImpl;
@override @useResult
$Res call({
 double? qty, double? qtyLow, double? qtyHigh, String? unit, String? qualifier
});




}
/// @nodoc
class __$RefPortionCopyWithImpl<$Res>
    implements _$RefPortionCopyWith<$Res> {
  __$RefPortionCopyWithImpl(this._self, this._then);

  final _RefPortion _self;
  final $Res Function(_RefPortion) _then;

/// Create a copy of RefPortion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? qty = freezed,Object? qtyLow = freezed,Object? qtyHigh = freezed,Object? unit = freezed,Object? qualifier = freezed,}) {
  return _then(_RefPortion(
qty: freezed == qty ? _self.qty : qty // ignore: cast_nullable_to_non_nullable
as double?,qtyLow: freezed == qtyLow ? _self.qtyLow : qtyLow // ignore: cast_nullable_to_non_nullable
as double?,qtyHigh: freezed == qtyHigh ? _self.qtyHigh : qtyHigh // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,qualifier: freezed == qualifier ? _self.qualifier : qualifier // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

StepToken _$StepTokenFromJson(
  Map<String, dynamic> json
) {
        switch (json['t']) {
                  case 'text':
          return TextToken.fromJson(
            json
          );
                case 'ref':
          return RefToken.fromJson(
            json
          );
                case 'timer':
          return TimerToken.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  't',
  'StepToken',
  'Invalid union type "${json['t']}"!'
);
        }
      
}

/// @nodoc
mixin _$StepToken {



  /// Serializes this StepToken to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StepToken);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StepToken()';
}


}

/// @nodoc
class $StepTokenCopyWith<$Res>  {
$StepTokenCopyWith(StepToken _, $Res Function(StepToken) __);
}


/// Adds pattern-matching-related methods to [StepToken].
extension StepTokenPatterns on StepToken {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TextToken value)?  text,TResult Function( RefToken value)?  ref,TResult Function( TimerToken value)?  timer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TextToken() when text != null:
return text(_that);case RefToken() when ref != null:
return ref(_that);case TimerToken() when timer != null:
return timer(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TextToken value)  text,required TResult Function( RefToken value)  ref,required TResult Function( TimerToken value)  timer,}){
final _that = this;
switch (_that) {
case TextToken():
return text(_that);case RefToken():
return ref(_that);case TimerToken():
return timer(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TextToken value)?  text,TResult? Function( RefToken value)?  ref,TResult? Function( TimerToken value)?  timer,}){
final _that = this;
switch (_that) {
case TextToken() when text != null:
return text(_that);case RefToken() when ref != null:
return ref(_that);case TimerToken() when timer != null:
return timer(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String s)?  text,TResult Function( List<int> refs,  String label,  MentionKind mention,  RefPortion? portion)?  ref,TResult Function( int lowSeconds,  int highSeconds)?  timer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TextToken() when text != null:
return text(_that.s);case RefToken() when ref != null:
return ref(_that.refs,_that.label,_that.mention,_that.portion);case TimerToken() when timer != null:
return timer(_that.lowSeconds,_that.highSeconds);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String s)  text,required TResult Function( List<int> refs,  String label,  MentionKind mention,  RefPortion? portion)  ref,required TResult Function( int lowSeconds,  int highSeconds)  timer,}) {final _that = this;
switch (_that) {
case TextToken():
return text(_that.s);case RefToken():
return ref(_that.refs,_that.label,_that.mention,_that.portion);case TimerToken():
return timer(_that.lowSeconds,_that.highSeconds);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String s)?  text,TResult? Function( List<int> refs,  String label,  MentionKind mention,  RefPortion? portion)?  ref,TResult? Function( int lowSeconds,  int highSeconds)?  timer,}) {final _that = this;
switch (_that) {
case TextToken() when text != null:
return text(_that.s);case RefToken() when ref != null:
return ref(_that.refs,_that.label,_that.mention,_that.portion);case TimerToken() when timer != null:
return timer(_that.lowSeconds,_that.highSeconds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class TextToken implements StepToken {
  const TextToken({required this.s, final  String? $type}): $type = $type ?? 'text';
  factory TextToken.fromJson(Map<String, dynamic> json) => _$TextTokenFromJson(json);

 final  String s;

@JsonKey(name: 't')
final String $type;


/// Create a copy of StepToken
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TextTokenCopyWith<TextToken> get copyWith => _$TextTokenCopyWithImpl<TextToken>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TextTokenToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TextToken&&(identical(other.s, s) || other.s == s));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,s);

@override
String toString() {
  return 'StepToken.text(s: $s)';
}


}

/// @nodoc
abstract mixin class $TextTokenCopyWith<$Res> implements $StepTokenCopyWith<$Res> {
  factory $TextTokenCopyWith(TextToken value, $Res Function(TextToken) _then) = _$TextTokenCopyWithImpl;
@useResult
$Res call({
 String s
});




}
/// @nodoc
class _$TextTokenCopyWithImpl<$Res>
    implements $TextTokenCopyWith<$Res> {
  _$TextTokenCopyWithImpl(this._self, this._then);

  final TextToken _self;
  final $Res Function(TextToken) _then;

/// Create a copy of StepToken
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? s = null,}) {
  return _then(TextToken(
s: null == s ? _self.s : s // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class RefToken implements StepToken {
  const RefToken({required final  List<int> refs, required this.label, this.mention = MentionKind.isNew, this.portion, final  String? $type}): _refs = refs,$type = $type ?? 'ref';
  factory RefToken.fromJson(Map<String, dynamic> json) => _$RefTokenFromJson(json);

 final  List<int> _refs;
 List<int> get refs {
  if (_refs is EqualUnmodifiableListView) return _refs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_refs);
}

 final  String label;
@JsonKey() final  MentionKind mention;
 final  RefPortion? portion;

@JsonKey(name: 't')
final String $type;


/// Create a copy of StepToken
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RefTokenCopyWith<RefToken> get copyWith => _$RefTokenCopyWithImpl<RefToken>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RefTokenToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RefToken&&const DeepCollectionEquality().equals(other._refs, _refs)&&(identical(other.label, label) || other.label == label)&&(identical(other.mention, mention) || other.mention == mention)&&(identical(other.portion, portion) || other.portion == portion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_refs),label,mention,portion);

@override
String toString() {
  return 'StepToken.ref(refs: $refs, label: $label, mention: $mention, portion: $portion)';
}


}

/// @nodoc
abstract mixin class $RefTokenCopyWith<$Res> implements $StepTokenCopyWith<$Res> {
  factory $RefTokenCopyWith(RefToken value, $Res Function(RefToken) _then) = _$RefTokenCopyWithImpl;
@useResult
$Res call({
 List<int> refs, String label, MentionKind mention, RefPortion? portion
});


$RefPortionCopyWith<$Res>? get portion;

}
/// @nodoc
class _$RefTokenCopyWithImpl<$Res>
    implements $RefTokenCopyWith<$Res> {
  _$RefTokenCopyWithImpl(this._self, this._then);

  final RefToken _self;
  final $Res Function(RefToken) _then;

/// Create a copy of StepToken
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? refs = null,Object? label = null,Object? mention = null,Object? portion = freezed,}) {
  return _then(RefToken(
refs: null == refs ? _self._refs : refs // ignore: cast_nullable_to_non_nullable
as List<int>,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,mention: null == mention ? _self.mention : mention // ignore: cast_nullable_to_non_nullable
as MentionKind,portion: freezed == portion ? _self.portion : portion // ignore: cast_nullable_to_non_nullable
as RefPortion?,
  ));
}

/// Create a copy of StepToken
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RefPortionCopyWith<$Res>? get portion {
    if (_self.portion == null) {
    return null;
  }

  return $RefPortionCopyWith<$Res>(_self.portion!, (value) {
    return _then(_self.copyWith(portion: value));
  });
}
}

/// @nodoc
@JsonSerializable()

class TimerToken implements StepToken {
  const TimerToken({required this.lowSeconds, required this.highSeconds, final  String? $type}): $type = $type ?? 'timer';
  factory TimerToken.fromJson(Map<String, dynamic> json) => _$TimerTokenFromJson(json);

 final  int lowSeconds;
 final  int highSeconds;

@JsonKey(name: 't')
final String $type;


/// Create a copy of StepToken
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimerTokenCopyWith<TimerToken> get copyWith => _$TimerTokenCopyWithImpl<TimerToken>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TimerTokenToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimerToken&&(identical(other.lowSeconds, lowSeconds) || other.lowSeconds == lowSeconds)&&(identical(other.highSeconds, highSeconds) || other.highSeconds == highSeconds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,lowSeconds,highSeconds);

@override
String toString() {
  return 'StepToken.timer(lowSeconds: $lowSeconds, highSeconds: $highSeconds)';
}


}

/// @nodoc
abstract mixin class $TimerTokenCopyWith<$Res> implements $StepTokenCopyWith<$Res> {
  factory $TimerTokenCopyWith(TimerToken value, $Res Function(TimerToken) _then) = _$TimerTokenCopyWithImpl;
@useResult
$Res call({
 int lowSeconds, int highSeconds
});




}
/// @nodoc
class _$TimerTokenCopyWithImpl<$Res>
    implements $TimerTokenCopyWith<$Res> {
  _$TimerTokenCopyWithImpl(this._self, this._then);

  final TimerToken _self;
  final $Res Function(TimerToken) _then;

/// Create a copy of StepToken
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? lowSeconds = null,Object? highSeconds = null,}) {
  return _then(TimerToken(
lowSeconds: null == lowSeconds ? _self.lowSeconds : lowSeconds // ignore: cast_nullable_to_non_nullable
as int,highSeconds: null == highSeconds ? _self.highSeconds : highSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$Step {

 List<StepToken> get tokens;
/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepCopyWith<Step> get copyWith => _$StepCopyWithImpl<Step>(this as Step, _$identity);

  /// Serializes this Step to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Step&&const DeepCollectionEquality().equals(other.tokens, tokens));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(tokens));

@override
String toString() {
  return 'Step(tokens: $tokens)';
}


}

/// @nodoc
abstract mixin class $StepCopyWith<$Res>  {
  factory $StepCopyWith(Step value, $Res Function(Step) _then) = _$StepCopyWithImpl;
@useResult
$Res call({
 List<StepToken> tokens
});




}
/// @nodoc
class _$StepCopyWithImpl<$Res>
    implements $StepCopyWith<$Res> {
  _$StepCopyWithImpl(this._self, this._then);

  final Step _self;
  final $Res Function(Step) _then;

/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tokens = null,}) {
  return _then(_self.copyWith(
tokens: null == tokens ? _self.tokens : tokens // ignore: cast_nullable_to_non_nullable
as List<StepToken>,
  ));
}

}


/// Adds pattern-matching-related methods to [Step].
extension StepPatterns on Step {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Step value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Step() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Step value)  $default,){
final _that = this;
switch (_that) {
case _Step():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Step value)?  $default,){
final _that = this;
switch (_that) {
case _Step() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<StepToken> tokens)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Step() when $default != null:
return $default(_that.tokens);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<StepToken> tokens)  $default,) {final _that = this;
switch (_that) {
case _Step():
return $default(_that.tokens);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<StepToken> tokens)?  $default,) {final _that = this;
switch (_that) {
case _Step() when $default != null:
return $default(_that.tokens);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Step implements Step {
  const _Step({final  List<StepToken> tokens = const <StepToken>[]}): _tokens = tokens;
  factory _Step.fromJson(Map<String, dynamic> json) => _$StepFromJson(json);

 final  List<StepToken> _tokens;
@override@JsonKey() List<StepToken> get tokens {
  if (_tokens is EqualUnmodifiableListView) return _tokens;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tokens);
}


/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StepCopyWith<_Step> get copyWith => __$StepCopyWithImpl<_Step>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StepToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Step&&const DeepCollectionEquality().equals(other._tokens, _tokens));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_tokens));

@override
String toString() {
  return 'Step(tokens: $tokens)';
}


}

/// @nodoc
abstract mixin class _$StepCopyWith<$Res> implements $StepCopyWith<$Res> {
  factory _$StepCopyWith(_Step value, $Res Function(_Step) _then) = __$StepCopyWithImpl;
@override @useResult
$Res call({
 List<StepToken> tokens
});




}
/// @nodoc
class __$StepCopyWithImpl<$Res>
    implements _$StepCopyWith<$Res> {
  __$StepCopyWithImpl(this._self, this._then);

  final _Step _self;
  final $Res Function(_Step) _then;

/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tokens = null,}) {
  return _then(_Step(
tokens: null == tokens ? _self._tokens : tokens // ignore: cast_nullable_to_non_nullable
as List<StepToken>,
  ));
}


}


/// @nodoc
mixin _$ReconLine {

 RawLineItem get raw; MatchBand get band; List<MatchCandidate> get candidates;/// The D6 recipe offers. The server OMITS the field entirely when there
/// are none — and when no recipe-title matcher is wired at all — so an
/// absent field must decode to exactly what it decoded before this
/// existed: the empty list, no chip, and a byte-identical commit.
 List<RecipeCandidate> get recipeCandidates;/// Where this line sits in [ReconciliationPayload.sourceText], when the
/// extractor knows. Omitted by the server otherwise, exactly as
/// [recipeCandidates] is, so a payload without it decodes to the same
/// bytes it always did.
 SourceSpan? get sourceSpan;
/// Create a copy of ReconLine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReconLineCopyWith<ReconLine> get copyWith => _$ReconLineCopyWithImpl<ReconLine>(this as ReconLine, _$identity);

  /// Serializes this ReconLine to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconLine&&(identical(other.raw, raw) || other.raw == raw)&&(identical(other.band, band) || other.band == band)&&const DeepCollectionEquality().equals(other.candidates, candidates)&&const DeepCollectionEquality().equals(other.recipeCandidates, recipeCandidates)&&(identical(other.sourceSpan, sourceSpan) || other.sourceSpan == sourceSpan));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,raw,band,const DeepCollectionEquality().hash(candidates),const DeepCollectionEquality().hash(recipeCandidates),sourceSpan);

@override
String toString() {
  return 'ReconLine(raw: $raw, band: $band, candidates: $candidates, recipeCandidates: $recipeCandidates, sourceSpan: $sourceSpan)';
}


}

/// @nodoc
abstract mixin class $ReconLineCopyWith<$Res>  {
  factory $ReconLineCopyWith(ReconLine value, $Res Function(ReconLine) _then) = _$ReconLineCopyWithImpl;
@useResult
$Res call({
 RawLineItem raw, MatchBand band, List<MatchCandidate> candidates, List<RecipeCandidate> recipeCandidates, SourceSpan? sourceSpan
});


$RawLineItemCopyWith<$Res> get raw;$SourceSpanCopyWith<$Res>? get sourceSpan;

}
/// @nodoc
class _$ReconLineCopyWithImpl<$Res>
    implements $ReconLineCopyWith<$Res> {
  _$ReconLineCopyWithImpl(this._self, this._then);

  final ReconLine _self;
  final $Res Function(ReconLine) _then;

/// Create a copy of ReconLine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,Object? band = null,Object? candidates = null,Object? recipeCandidates = null,Object? sourceSpan = freezed,}) {
  return _then(_self.copyWith(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as RawLineItem,band: null == band ? _self.band : band // ignore: cast_nullable_to_non_nullable
as MatchBand,candidates: null == candidates ? _self.candidates : candidates // ignore: cast_nullable_to_non_nullable
as List<MatchCandidate>,recipeCandidates: null == recipeCandidates ? _self.recipeCandidates : recipeCandidates // ignore: cast_nullable_to_non_nullable
as List<RecipeCandidate>,sourceSpan: freezed == sourceSpan ? _self.sourceSpan : sourceSpan // ignore: cast_nullable_to_non_nullable
as SourceSpan?,
  ));
}
/// Create a copy of ReconLine
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RawLineItemCopyWith<$Res> get raw {
  
  return $RawLineItemCopyWith<$Res>(_self.raw, (value) {
    return _then(_self.copyWith(raw: value));
  });
}/// Create a copy of ReconLine
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceSpanCopyWith<$Res>? get sourceSpan {
    if (_self.sourceSpan == null) {
    return null;
  }

  return $SourceSpanCopyWith<$Res>(_self.sourceSpan!, (value) {
    return _then(_self.copyWith(sourceSpan: value));
  });
}
}


/// Adds pattern-matching-related methods to [ReconLine].
extension ReconLinePatterns on ReconLine {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReconLine value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReconLine() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReconLine value)  $default,){
final _that = this;
switch (_that) {
case _ReconLine():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReconLine value)?  $default,){
final _that = this;
switch (_that) {
case _ReconLine() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RawLineItem raw,  MatchBand band,  List<MatchCandidate> candidates,  List<RecipeCandidate> recipeCandidates,  SourceSpan? sourceSpan)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReconLine() when $default != null:
return $default(_that.raw,_that.band,_that.candidates,_that.recipeCandidates,_that.sourceSpan);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RawLineItem raw,  MatchBand band,  List<MatchCandidate> candidates,  List<RecipeCandidate> recipeCandidates,  SourceSpan? sourceSpan)  $default,) {final _that = this;
switch (_that) {
case _ReconLine():
return $default(_that.raw,_that.band,_that.candidates,_that.recipeCandidates,_that.sourceSpan);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RawLineItem raw,  MatchBand band,  List<MatchCandidate> candidates,  List<RecipeCandidate> recipeCandidates,  SourceSpan? sourceSpan)?  $default,) {final _that = this;
switch (_that) {
case _ReconLine() when $default != null:
return $default(_that.raw,_that.band,_that.candidates,_that.recipeCandidates,_that.sourceSpan);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ReconLine implements ReconLine {
  const _ReconLine({required this.raw, required this.band, final  List<MatchCandidate> candidates = const <MatchCandidate>[], final  List<RecipeCandidate> recipeCandidates = const <RecipeCandidate>[], this.sourceSpan}): _candidates = candidates,_recipeCandidates = recipeCandidates;
  factory _ReconLine.fromJson(Map<String, dynamic> json) => _$ReconLineFromJson(json);

@override final  RawLineItem raw;
@override final  MatchBand band;
 final  List<MatchCandidate> _candidates;
@override@JsonKey() List<MatchCandidate> get candidates {
  if (_candidates is EqualUnmodifiableListView) return _candidates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_candidates);
}

/// The D6 recipe offers. The server OMITS the field entirely when there
/// are none — and when no recipe-title matcher is wired at all — so an
/// absent field must decode to exactly what it decoded before this
/// existed: the empty list, no chip, and a byte-identical commit.
 final  List<RecipeCandidate> _recipeCandidates;
/// The D6 recipe offers. The server OMITS the field entirely when there
/// are none — and when no recipe-title matcher is wired at all — so an
/// absent field must decode to exactly what it decoded before this
/// existed: the empty list, no chip, and a byte-identical commit.
@override@JsonKey() List<RecipeCandidate> get recipeCandidates {
  if (_recipeCandidates is EqualUnmodifiableListView) return _recipeCandidates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recipeCandidates);
}

/// Where this line sits in [ReconciliationPayload.sourceText], when the
/// extractor knows. Omitted by the server otherwise, exactly as
/// [recipeCandidates] is, so a payload without it decodes to the same
/// bytes it always did.
@override final  SourceSpan? sourceSpan;

/// Create a copy of ReconLine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReconLineCopyWith<_ReconLine> get copyWith => __$ReconLineCopyWithImpl<_ReconLine>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ReconLineToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReconLine&&(identical(other.raw, raw) || other.raw == raw)&&(identical(other.band, band) || other.band == band)&&const DeepCollectionEquality().equals(other._candidates, _candidates)&&const DeepCollectionEquality().equals(other._recipeCandidates, _recipeCandidates)&&(identical(other.sourceSpan, sourceSpan) || other.sourceSpan == sourceSpan));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,raw,band,const DeepCollectionEquality().hash(_candidates),const DeepCollectionEquality().hash(_recipeCandidates),sourceSpan);

@override
String toString() {
  return 'ReconLine(raw: $raw, band: $band, candidates: $candidates, recipeCandidates: $recipeCandidates, sourceSpan: $sourceSpan)';
}


}

/// @nodoc
abstract mixin class _$ReconLineCopyWith<$Res> implements $ReconLineCopyWith<$Res> {
  factory _$ReconLineCopyWith(_ReconLine value, $Res Function(_ReconLine) _then) = __$ReconLineCopyWithImpl;
@override @useResult
$Res call({
 RawLineItem raw, MatchBand band, List<MatchCandidate> candidates, List<RecipeCandidate> recipeCandidates, SourceSpan? sourceSpan
});


@override $RawLineItemCopyWith<$Res> get raw;@override $SourceSpanCopyWith<$Res>? get sourceSpan;

}
/// @nodoc
class __$ReconLineCopyWithImpl<$Res>
    implements _$ReconLineCopyWith<$Res> {
  __$ReconLineCopyWithImpl(this._self, this._then);

  final _ReconLine _self;
  final $Res Function(_ReconLine) _then;

/// Create a copy of ReconLine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,Object? band = null,Object? candidates = null,Object? recipeCandidates = null,Object? sourceSpan = freezed,}) {
  return _then(_ReconLine(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as RawLineItem,band: null == band ? _self.band : band // ignore: cast_nullable_to_non_nullable
as MatchBand,candidates: null == candidates ? _self._candidates : candidates // ignore: cast_nullable_to_non_nullable
as List<MatchCandidate>,recipeCandidates: null == recipeCandidates ? _self._recipeCandidates : recipeCandidates // ignore: cast_nullable_to_non_nullable
as List<RecipeCandidate>,sourceSpan: freezed == sourceSpan ? _self.sourceSpan : sourceSpan // ignore: cast_nullable_to_non_nullable
as SourceSpan?,
  ));
}

/// Create a copy of ReconLine
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RawLineItemCopyWith<$Res> get raw {
  
  return $RawLineItemCopyWith<$Res>(_self.raw, (value) {
    return _then(_self.copyWith(raw: value));
  });
}/// Create a copy of ReconLine
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceSpanCopyWith<$Res>? get sourceSpan {
    if (_self.sourceSpan == null) {
    return null;
  }

  return $SourceSpanCopyWith<$Res>(_self.sourceSpan!, (value) {
    return _then(_self.copyWith(sourceSpan: value));
  });
}
}


/// @nodoc
mixin _$ReconGroup {

 String? get name; List<ReconLine> get lines;
/// Create a copy of ReconGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReconGroupCopyWith<ReconGroup> get copyWith => _$ReconGroupCopyWithImpl<ReconGroup>(this as ReconGroup, _$identity);

  /// Serializes this ReconGroup to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconGroup&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.lines, lines));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(lines));

@override
String toString() {
  return 'ReconGroup(name: $name, lines: $lines)';
}


}

/// @nodoc
abstract mixin class $ReconGroupCopyWith<$Res>  {
  factory $ReconGroupCopyWith(ReconGroup value, $Res Function(ReconGroup) _then) = _$ReconGroupCopyWithImpl;
@useResult
$Res call({
 String? name, List<ReconLine> lines
});




}
/// @nodoc
class _$ReconGroupCopyWithImpl<$Res>
    implements $ReconGroupCopyWith<$Res> {
  _$ReconGroupCopyWithImpl(this._self, this._then);

  final ReconGroup _self;
  final $Res Function(ReconGroup) _then;

/// Create a copy of ReconGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = freezed,Object? lines = null,}) {
  return _then(_self.copyWith(
name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as List<ReconLine>,
  ));
}

}


/// Adds pattern-matching-related methods to [ReconGroup].
extension ReconGroupPatterns on ReconGroup {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReconGroup value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReconGroup() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReconGroup value)  $default,){
final _that = this;
switch (_that) {
case _ReconGroup():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReconGroup value)?  $default,){
final _that = this;
switch (_that) {
case _ReconGroup() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? name,  List<ReconLine> lines)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReconGroup() when $default != null:
return $default(_that.name,_that.lines);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? name,  List<ReconLine> lines)  $default,) {final _that = this;
switch (_that) {
case _ReconGroup():
return $default(_that.name,_that.lines);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? name,  List<ReconLine> lines)?  $default,) {final _that = this;
switch (_that) {
case _ReconGroup() when $default != null:
return $default(_that.name,_that.lines);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ReconGroup implements ReconGroup {
  const _ReconGroup({this.name, final  List<ReconLine> lines = const <ReconLine>[]}): _lines = lines;
  factory _ReconGroup.fromJson(Map<String, dynamic> json) => _$ReconGroupFromJson(json);

@override final  String? name;
 final  List<ReconLine> _lines;
@override@JsonKey() List<ReconLine> get lines {
  if (_lines is EqualUnmodifiableListView) return _lines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_lines);
}


/// Create a copy of ReconGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReconGroupCopyWith<_ReconGroup> get copyWith => __$ReconGroupCopyWithImpl<_ReconGroup>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ReconGroupToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReconGroup&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._lines, _lines));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(_lines));

@override
String toString() {
  return 'ReconGroup(name: $name, lines: $lines)';
}


}

/// @nodoc
abstract mixin class _$ReconGroupCopyWith<$Res> implements $ReconGroupCopyWith<$Res> {
  factory _$ReconGroupCopyWith(_ReconGroup value, $Res Function(_ReconGroup) _then) = __$ReconGroupCopyWithImpl;
@override @useResult
$Res call({
 String? name, List<ReconLine> lines
});




}
/// @nodoc
class __$ReconGroupCopyWithImpl<$Res>
    implements _$ReconGroupCopyWith<$Res> {
  __$ReconGroupCopyWithImpl(this._self, this._then);

  final _ReconGroup _self;
  final $Res Function(_ReconGroup) _then;

/// Create a copy of ReconGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = freezed,Object? lines = null,}) {
  return _then(_ReconGroup(
name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,lines: null == lines ? _self._lines : lines // ignore: cast_nullable_to_non_nullable
as List<ReconLine>,
  ));
}


}


/// @nodoc
mixin _$ReconciliationPayload {

 String get title; int? get servingsBase; String? get servingsRaw; String? get yieldRaw;@TimeFieldConverter() TimeRange? get totalTimeSeconds;@TimeFieldConverter() TimeRange? get cookTimeSeconds; bool get truncated; ImportImageQuality get imageQuality; List<String> get parseWarnings; List<ReconGroup> get groups; List<Step> get steps;/// The text the server actually read this recipe out of — a **link**
/// import's fetched page, bounded server-side. Null for a
/// photo import, where the pages are images the phone already holds, and
/// null from any server that does not send it.
///
/// It is the source column's copy on a desk. Bounded because a page's
/// text is unbounded and this rides the same response as the recipe: the
/// cap is the server's, stated in `import-recipe/index.ts`.
 String? get sourceText;
/// Create a copy of ReconciliationPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReconciliationPayloadCopyWith<ReconciliationPayload> get copyWith => _$ReconciliationPayloadCopyWithImpl<ReconciliationPayload>(this as ReconciliationPayload, _$identity);

  /// Serializes this ReconciliationPayload to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconciliationPayload&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.servingsRaw, servingsRaw) || other.servingsRaw == servingsRaw)&&(identical(other.yieldRaw, yieldRaw) || other.yieldRaw == yieldRaw)&&(identical(other.totalTimeSeconds, totalTimeSeconds) || other.totalTimeSeconds == totalTimeSeconds)&&(identical(other.cookTimeSeconds, cookTimeSeconds) || other.cookTimeSeconds == cookTimeSeconds)&&(identical(other.truncated, truncated) || other.truncated == truncated)&&(identical(other.imageQuality, imageQuality) || other.imageQuality == imageQuality)&&const DeepCollectionEquality().equals(other.parseWarnings, parseWarnings)&&const DeepCollectionEquality().equals(other.groups, groups)&&const DeepCollectionEquality().equals(other.steps, steps)&&(identical(other.sourceText, sourceText) || other.sourceText == sourceText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,servingsBase,servingsRaw,yieldRaw,totalTimeSeconds,cookTimeSeconds,truncated,imageQuality,const DeepCollectionEquality().hash(parseWarnings),const DeepCollectionEquality().hash(groups),const DeepCollectionEquality().hash(steps),sourceText);

@override
String toString() {
  return 'ReconciliationPayload(title: $title, servingsBase: $servingsBase, servingsRaw: $servingsRaw, yieldRaw: $yieldRaw, totalTimeSeconds: $totalTimeSeconds, cookTimeSeconds: $cookTimeSeconds, truncated: $truncated, imageQuality: $imageQuality, parseWarnings: $parseWarnings, groups: $groups, steps: $steps, sourceText: $sourceText)';
}


}

/// @nodoc
abstract mixin class $ReconciliationPayloadCopyWith<$Res>  {
  factory $ReconciliationPayloadCopyWith(ReconciliationPayload value, $Res Function(ReconciliationPayload) _then) = _$ReconciliationPayloadCopyWithImpl;
@useResult
$Res call({
 String title, int? servingsBase, String? servingsRaw, String? yieldRaw,@TimeFieldConverter() TimeRange? totalTimeSeconds,@TimeFieldConverter() TimeRange? cookTimeSeconds, bool truncated, ImportImageQuality imageQuality, List<String> parseWarnings, List<ReconGroup> groups, List<Step> steps, String? sourceText
});


$TimeRangeCopyWith<$Res>? get totalTimeSeconds;$TimeRangeCopyWith<$Res>? get cookTimeSeconds;

}
/// @nodoc
class _$ReconciliationPayloadCopyWithImpl<$Res>
    implements $ReconciliationPayloadCopyWith<$Res> {
  _$ReconciliationPayloadCopyWithImpl(this._self, this._then);

  final ReconciliationPayload _self;
  final $Res Function(ReconciliationPayload) _then;

/// Create a copy of ReconciliationPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? servingsBase = freezed,Object? servingsRaw = freezed,Object? yieldRaw = freezed,Object? totalTimeSeconds = freezed,Object? cookTimeSeconds = freezed,Object? truncated = null,Object? imageQuality = null,Object? parseWarnings = null,Object? groups = null,Object? steps = null,Object? sourceText = freezed,}) {
  return _then(_self.copyWith(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: freezed == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as int?,servingsRaw: freezed == servingsRaw ? _self.servingsRaw : servingsRaw // ignore: cast_nullable_to_non_nullable
as String?,yieldRaw: freezed == yieldRaw ? _self.yieldRaw : yieldRaw // ignore: cast_nullable_to_non_nullable
as String?,totalTimeSeconds: freezed == totalTimeSeconds ? _self.totalTimeSeconds : totalTimeSeconds // ignore: cast_nullable_to_non_nullable
as TimeRange?,cookTimeSeconds: freezed == cookTimeSeconds ? _self.cookTimeSeconds : cookTimeSeconds // ignore: cast_nullable_to_non_nullable
as TimeRange?,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,imageQuality: null == imageQuality ? _self.imageQuality : imageQuality // ignore: cast_nullable_to_non_nullable
as ImportImageQuality,parseWarnings: null == parseWarnings ? _self.parseWarnings : parseWarnings // ignore: cast_nullable_to_non_nullable
as List<String>,groups: null == groups ? _self.groups : groups // ignore: cast_nullable_to_non_nullable
as List<ReconGroup>,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<Step>,sourceText: freezed == sourceText ? _self.sourceText : sourceText // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of ReconciliationPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TimeRangeCopyWith<$Res>? get totalTimeSeconds {
    if (_self.totalTimeSeconds == null) {
    return null;
  }

  return $TimeRangeCopyWith<$Res>(_self.totalTimeSeconds!, (value) {
    return _then(_self.copyWith(totalTimeSeconds: value));
  });
}/// Create a copy of ReconciliationPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TimeRangeCopyWith<$Res>? get cookTimeSeconds {
    if (_self.cookTimeSeconds == null) {
    return null;
  }

  return $TimeRangeCopyWith<$Res>(_self.cookTimeSeconds!, (value) {
    return _then(_self.copyWith(cookTimeSeconds: value));
  });
}
}


/// Adds pattern-matching-related methods to [ReconciliationPayload].
extension ReconciliationPayloadPatterns on ReconciliationPayload {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReconciliationPayload value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReconciliationPayload() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReconciliationPayload value)  $default,){
final _that = this;
switch (_that) {
case _ReconciliationPayload():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReconciliationPayload value)?  $default,){
final _that = this;
switch (_that) {
case _ReconciliationPayload() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String title,  int? servingsBase,  String? servingsRaw,  String? yieldRaw, @TimeFieldConverter()  TimeRange? totalTimeSeconds, @TimeFieldConverter()  TimeRange? cookTimeSeconds,  bool truncated,  ImportImageQuality imageQuality,  List<String> parseWarnings,  List<ReconGroup> groups,  List<Step> steps,  String? sourceText)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReconciliationPayload() when $default != null:
return $default(_that.title,_that.servingsBase,_that.servingsRaw,_that.yieldRaw,_that.totalTimeSeconds,_that.cookTimeSeconds,_that.truncated,_that.imageQuality,_that.parseWarnings,_that.groups,_that.steps,_that.sourceText);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String title,  int? servingsBase,  String? servingsRaw,  String? yieldRaw, @TimeFieldConverter()  TimeRange? totalTimeSeconds, @TimeFieldConverter()  TimeRange? cookTimeSeconds,  bool truncated,  ImportImageQuality imageQuality,  List<String> parseWarnings,  List<ReconGroup> groups,  List<Step> steps,  String? sourceText)  $default,) {final _that = this;
switch (_that) {
case _ReconciliationPayload():
return $default(_that.title,_that.servingsBase,_that.servingsRaw,_that.yieldRaw,_that.totalTimeSeconds,_that.cookTimeSeconds,_that.truncated,_that.imageQuality,_that.parseWarnings,_that.groups,_that.steps,_that.sourceText);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String title,  int? servingsBase,  String? servingsRaw,  String? yieldRaw, @TimeFieldConverter()  TimeRange? totalTimeSeconds, @TimeFieldConverter()  TimeRange? cookTimeSeconds,  bool truncated,  ImportImageQuality imageQuality,  List<String> parseWarnings,  List<ReconGroup> groups,  List<Step> steps,  String? sourceText)?  $default,) {final _that = this;
switch (_that) {
case _ReconciliationPayload() when $default != null:
return $default(_that.title,_that.servingsBase,_that.servingsRaw,_that.yieldRaw,_that.totalTimeSeconds,_that.cookTimeSeconds,_that.truncated,_that.imageQuality,_that.parseWarnings,_that.groups,_that.steps,_that.sourceText);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ReconciliationPayload implements ReconciliationPayload {
  const _ReconciliationPayload({required this.title, this.servingsBase, this.servingsRaw, this.yieldRaw, @TimeFieldConverter() this.totalTimeSeconds, @TimeFieldConverter() this.cookTimeSeconds, this.truncated = false, this.imageQuality = ImportImageQuality.ok, final  List<String> parseWarnings = const <String>[], final  List<ReconGroup> groups = const <ReconGroup>[], final  List<Step> steps = const <Step>[], this.sourceText}): _parseWarnings = parseWarnings,_groups = groups,_steps = steps;
  factory _ReconciliationPayload.fromJson(Map<String, dynamic> json) => _$ReconciliationPayloadFromJson(json);

@override final  String title;
@override final  int? servingsBase;
@override final  String? servingsRaw;
@override final  String? yieldRaw;
@override@TimeFieldConverter() final  TimeRange? totalTimeSeconds;
@override@TimeFieldConverter() final  TimeRange? cookTimeSeconds;
@override@JsonKey() final  bool truncated;
@override@JsonKey() final  ImportImageQuality imageQuality;
 final  List<String> _parseWarnings;
@override@JsonKey() List<String> get parseWarnings {
  if (_parseWarnings is EqualUnmodifiableListView) return _parseWarnings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_parseWarnings);
}

 final  List<ReconGroup> _groups;
@override@JsonKey() List<ReconGroup> get groups {
  if (_groups is EqualUnmodifiableListView) return _groups;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_groups);
}

 final  List<Step> _steps;
@override@JsonKey() List<Step> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}

/// The text the server actually read this recipe out of — a **link**
/// import's fetched page, bounded server-side. Null for a
/// photo import, where the pages are images the phone already holds, and
/// null from any server that does not send it.
///
/// It is the source column's copy on a desk. Bounded because a page's
/// text is unbounded and this rides the same response as the recipe: the
/// cap is the server's, stated in `import-recipe/index.ts`.
@override final  String? sourceText;

/// Create a copy of ReconciliationPayload
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReconciliationPayloadCopyWith<_ReconciliationPayload> get copyWith => __$ReconciliationPayloadCopyWithImpl<_ReconciliationPayload>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ReconciliationPayloadToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReconciliationPayload&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.servingsRaw, servingsRaw) || other.servingsRaw == servingsRaw)&&(identical(other.yieldRaw, yieldRaw) || other.yieldRaw == yieldRaw)&&(identical(other.totalTimeSeconds, totalTimeSeconds) || other.totalTimeSeconds == totalTimeSeconds)&&(identical(other.cookTimeSeconds, cookTimeSeconds) || other.cookTimeSeconds == cookTimeSeconds)&&(identical(other.truncated, truncated) || other.truncated == truncated)&&(identical(other.imageQuality, imageQuality) || other.imageQuality == imageQuality)&&const DeepCollectionEquality().equals(other._parseWarnings, _parseWarnings)&&const DeepCollectionEquality().equals(other._groups, _groups)&&const DeepCollectionEquality().equals(other._steps, _steps)&&(identical(other.sourceText, sourceText) || other.sourceText == sourceText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,title,servingsBase,servingsRaw,yieldRaw,totalTimeSeconds,cookTimeSeconds,truncated,imageQuality,const DeepCollectionEquality().hash(_parseWarnings),const DeepCollectionEquality().hash(_groups),const DeepCollectionEquality().hash(_steps),sourceText);

@override
String toString() {
  return 'ReconciliationPayload(title: $title, servingsBase: $servingsBase, servingsRaw: $servingsRaw, yieldRaw: $yieldRaw, totalTimeSeconds: $totalTimeSeconds, cookTimeSeconds: $cookTimeSeconds, truncated: $truncated, imageQuality: $imageQuality, parseWarnings: $parseWarnings, groups: $groups, steps: $steps, sourceText: $sourceText)';
}


}

/// @nodoc
abstract mixin class _$ReconciliationPayloadCopyWith<$Res> implements $ReconciliationPayloadCopyWith<$Res> {
  factory _$ReconciliationPayloadCopyWith(_ReconciliationPayload value, $Res Function(_ReconciliationPayload) _then) = __$ReconciliationPayloadCopyWithImpl;
@override @useResult
$Res call({
 String title, int? servingsBase, String? servingsRaw, String? yieldRaw,@TimeFieldConverter() TimeRange? totalTimeSeconds,@TimeFieldConverter() TimeRange? cookTimeSeconds, bool truncated, ImportImageQuality imageQuality, List<String> parseWarnings, List<ReconGroup> groups, List<Step> steps, String? sourceText
});


@override $TimeRangeCopyWith<$Res>? get totalTimeSeconds;@override $TimeRangeCopyWith<$Res>? get cookTimeSeconds;

}
/// @nodoc
class __$ReconciliationPayloadCopyWithImpl<$Res>
    implements _$ReconciliationPayloadCopyWith<$Res> {
  __$ReconciliationPayloadCopyWithImpl(this._self, this._then);

  final _ReconciliationPayload _self;
  final $Res Function(_ReconciliationPayload) _then;

/// Create a copy of ReconciliationPayload
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? servingsBase = freezed,Object? servingsRaw = freezed,Object? yieldRaw = freezed,Object? totalTimeSeconds = freezed,Object? cookTimeSeconds = freezed,Object? truncated = null,Object? imageQuality = null,Object? parseWarnings = null,Object? groups = null,Object? steps = null,Object? sourceText = freezed,}) {
  return _then(_ReconciliationPayload(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: freezed == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as int?,servingsRaw: freezed == servingsRaw ? _self.servingsRaw : servingsRaw // ignore: cast_nullable_to_non_nullable
as String?,yieldRaw: freezed == yieldRaw ? _self.yieldRaw : yieldRaw // ignore: cast_nullable_to_non_nullable
as String?,totalTimeSeconds: freezed == totalTimeSeconds ? _self.totalTimeSeconds : totalTimeSeconds // ignore: cast_nullable_to_non_nullable
as TimeRange?,cookTimeSeconds: freezed == cookTimeSeconds ? _self.cookTimeSeconds : cookTimeSeconds // ignore: cast_nullable_to_non_nullable
as TimeRange?,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,imageQuality: null == imageQuality ? _self.imageQuality : imageQuality // ignore: cast_nullable_to_non_nullable
as ImportImageQuality,parseWarnings: null == parseWarnings ? _self._parseWarnings : parseWarnings // ignore: cast_nullable_to_non_nullable
as List<String>,groups: null == groups ? _self._groups : groups // ignore: cast_nullable_to_non_nullable
as List<ReconGroup>,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<Step>,sourceText: freezed == sourceText ? _self.sourceText : sourceText // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ReconciliationPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TimeRangeCopyWith<$Res>? get totalTimeSeconds {
    if (_self.totalTimeSeconds == null) {
    return null;
  }

  return $TimeRangeCopyWith<$Res>(_self.totalTimeSeconds!, (value) {
    return _then(_self.copyWith(totalTimeSeconds: value));
  });
}/// Create a copy of ReconciliationPayload
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TimeRangeCopyWith<$Res>? get cookTimeSeconds {
    if (_self.cookTimeSeconds == null) {
    return null;
  }

  return $TimeRangeCopyWith<$Res>(_self.cookTimeSeconds!, (value) {
    return _then(_self.copyWith(cookTimeSeconds: value));
  });
}
}

// dart format on
