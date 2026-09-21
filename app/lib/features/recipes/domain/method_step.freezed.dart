// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'method_step.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$StepPortion {

 double? get qty; double? get qtyLow; double? get qtyHigh; String? get unit; String? get qualifier;
/// Create a copy of StepPortion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepPortionCopyWith<StepPortion> get copyWith => _$StepPortionCopyWithImpl<StepPortion>(this as StepPortion, _$identity);

  /// Serializes this StepPortion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StepPortion&&(identical(other.qty, qty) || other.qty == qty)&&(identical(other.qtyLow, qtyLow) || other.qtyLow == qtyLow)&&(identical(other.qtyHigh, qtyHigh) || other.qtyHigh == qtyHigh)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.qualifier, qualifier) || other.qualifier == qualifier));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,qty,qtyLow,qtyHigh,unit,qualifier);

@override
String toString() {
  return 'StepPortion(qty: $qty, qtyLow: $qtyLow, qtyHigh: $qtyHigh, unit: $unit, qualifier: $qualifier)';
}


}

/// @nodoc
abstract mixin class $StepPortionCopyWith<$Res>  {
  factory $StepPortionCopyWith(StepPortion value, $Res Function(StepPortion) _then) = _$StepPortionCopyWithImpl;
@useResult
$Res call({
 double? qty, double? qtyLow, double? qtyHigh, String? unit, String? qualifier
});




}
/// @nodoc
class _$StepPortionCopyWithImpl<$Res>
    implements $StepPortionCopyWith<$Res> {
  _$StepPortionCopyWithImpl(this._self, this._then);

  final StepPortion _self;
  final $Res Function(StepPortion) _then;

/// Create a copy of StepPortion
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


/// Adds pattern-matching-related methods to [StepPortion].
extension StepPortionPatterns on StepPortion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StepPortion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StepPortion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StepPortion value)  $default,){
final _that = this;
switch (_that) {
case _StepPortion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StepPortion value)?  $default,){
final _that = this;
switch (_that) {
case _StepPortion() when $default != null:
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
case _StepPortion() when $default != null:
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
case _StepPortion():
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
case _StepPortion() when $default != null:
return $default(_that.qty,_that.qtyLow,_that.qtyHigh,_that.unit,_that.qualifier);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _StepPortion implements StepPortion {
  const _StepPortion({this.qty, this.qtyLow, this.qtyHigh, this.unit, this.qualifier});
  factory _StepPortion.fromJson(Map<String, dynamic> json) => _$StepPortionFromJson(json);

@override final  double? qty;
@override final  double? qtyLow;
@override final  double? qtyHigh;
@override final  String? unit;
@override final  String? qualifier;

/// Create a copy of StepPortion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StepPortionCopyWith<_StepPortion> get copyWith => __$StepPortionCopyWithImpl<_StepPortion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StepPortionToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StepPortion&&(identical(other.qty, qty) || other.qty == qty)&&(identical(other.qtyLow, qtyLow) || other.qtyLow == qtyLow)&&(identical(other.qtyHigh, qtyHigh) || other.qtyHigh == qtyHigh)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.qualifier, qualifier) || other.qualifier == qualifier));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,qty,qtyLow,qtyHigh,unit,qualifier);

@override
String toString() {
  return 'StepPortion(qty: $qty, qtyLow: $qtyLow, qtyHigh: $qtyHigh, unit: $unit, qualifier: $qualifier)';
}


}

/// @nodoc
abstract mixin class _$StepPortionCopyWith<$Res> implements $StepPortionCopyWith<$Res> {
  factory _$StepPortionCopyWith(_StepPortion value, $Res Function(_StepPortion) _then) = __$StepPortionCopyWithImpl;
@override @useResult
$Res call({
 double? qty, double? qtyLow, double? qtyHigh, String? unit, String? qualifier
});




}
/// @nodoc
class __$StepPortionCopyWithImpl<$Res>
    implements _$StepPortionCopyWith<$Res> {
  __$StepPortionCopyWithImpl(this._self, this._then);

  final _StepPortion _self;
  final $Res Function(_StepPortion) _then;

/// Create a copy of StepPortion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? qty = freezed,Object? qtyLow = freezed,Object? qtyHigh = freezed,Object? unit = freezed,Object? qualifier = freezed,}) {
  return _then(_StepPortion(
qty: freezed == qty ? _self.qty : qty // ignore: cast_nullable_to_non_nullable
as double?,qtyLow: freezed == qtyLow ? _self.qtyLow : qtyLow // ignore: cast_nullable_to_non_nullable
as double?,qtyHigh: freezed == qtyHigh ? _self.qtyHigh : qtyHigh // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,qualifier: freezed == qualifier ? _self.qualifier : qualifier // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

MethodToken _$MethodTokenFromJson(
  Map<String, dynamic> json
) {
        switch (json['t']) {
                  case 'text':
          return MethodText.fromJson(
            json
          );
                case 'ref':
          return MethodRef.fromJson(
            json
          );
                case 'timer':
          return MethodTimer.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  't',
  'MethodToken',
  'Invalid union type "${json['t']}"!'
);
        }
      
}

/// @nodoc
mixin _$MethodToken {



  /// Serializes this MethodToken to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MethodToken);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MethodToken()';
}


}

/// @nodoc
class $MethodTokenCopyWith<$Res>  {
$MethodTokenCopyWith(MethodToken _, $Res Function(MethodToken) __);
}


/// Adds pattern-matching-related methods to [MethodToken].
extension MethodTokenPatterns on MethodToken {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MethodText value)?  text,TResult Function( MethodRef value)?  ref,TResult Function( MethodTimer value)?  timer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MethodText() when text != null:
return text(_that);case MethodRef() when ref != null:
return ref(_that);case MethodTimer() when timer != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MethodText value)  text,required TResult Function( MethodRef value)  ref,required TResult Function( MethodTimer value)  timer,}){
final _that = this;
switch (_that) {
case MethodText():
return text(_that);case MethodRef():
return ref(_that);case MethodTimer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MethodText value)?  text,TResult? Function( MethodRef value)?  ref,TResult? Function( MethodTimer value)?  timer,}){
final _that = this;
switch (_that) {
case MethodText() when text != null:
return text(_that);case MethodRef() when ref != null:
return ref(_that);case MethodTimer() when timer != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String s)?  text,TResult Function( List<String> refs,  String label, @JsonKey(name: 'mention')  ChipAmountRule amountRule,  StepPortion? portion)?  ref,TResult Function( int lowSeconds,  int highSeconds)?  timer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MethodText() when text != null:
return text(_that.s);case MethodRef() when ref != null:
return ref(_that.refs,_that.label,_that.amountRule,_that.portion);case MethodTimer() when timer != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String s)  text,required TResult Function( List<String> refs,  String label, @JsonKey(name: 'mention')  ChipAmountRule amountRule,  StepPortion? portion)  ref,required TResult Function( int lowSeconds,  int highSeconds)  timer,}) {final _that = this;
switch (_that) {
case MethodText():
return text(_that.s);case MethodRef():
return ref(_that.refs,_that.label,_that.amountRule,_that.portion);case MethodTimer():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String s)?  text,TResult? Function( List<String> refs,  String label, @JsonKey(name: 'mention')  ChipAmountRule amountRule,  StepPortion? portion)?  ref,TResult? Function( int lowSeconds,  int highSeconds)?  timer,}) {final _that = this;
switch (_that) {
case MethodText() when text != null:
return text(_that.s);case MethodRef() when ref != null:
return ref(_that.refs,_that.label,_that.amountRule,_that.portion);case MethodTimer() when timer != null:
return timer(_that.lowSeconds,_that.highSeconds);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class MethodText implements MethodToken {
  const MethodText({required this.s, final  String? $type}): $type = $type ?? 'text';
  factory MethodText.fromJson(Map<String, dynamic> json) => _$MethodTextFromJson(json);

 final  String s;

@JsonKey(name: 't')
final String $type;


/// Create a copy of MethodToken
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MethodTextCopyWith<MethodText> get copyWith => _$MethodTextCopyWithImpl<MethodText>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MethodTextToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MethodText&&(identical(other.s, s) || other.s == s));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,s);

@override
String toString() {
  return 'MethodToken.text(s: $s)';
}


}

/// @nodoc
abstract mixin class $MethodTextCopyWith<$Res> implements $MethodTokenCopyWith<$Res> {
  factory $MethodTextCopyWith(MethodText value, $Res Function(MethodText) _then) = _$MethodTextCopyWithImpl;
@useResult
$Res call({
 String s
});




}
/// @nodoc
class _$MethodTextCopyWithImpl<$Res>
    implements $MethodTextCopyWith<$Res> {
  _$MethodTextCopyWithImpl(this._self, this._then);

  final MethodText _self;
  final $Res Function(MethodText) _then;

/// Create a copy of MethodToken
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? s = null,}) {
  return _then(MethodText(
s: null == s ? _self.s : s // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class MethodRef implements MethodToken {
  const MethodRef({required final  List<String> refs, required this.label, @JsonKey(name: 'mention') this.amountRule = ChipAmountRule.showAmount, this.portion, final  String? $type}): _refs = refs,$type = $type ?? 'ref';
  factory MethodRef.fromJson(Map<String, dynamic> json) => _$MethodRefFromJson(json);

 final  List<String> _refs;
 List<String> get refs {
  if (_refs is EqualUnmodifiableListView) return _refs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_refs);
}

 final  String label;
/// Whether this chip shows its line's amount. The JSON key is `mention`.
@JsonKey(name: 'mention') final  ChipAmountRule amountRule;
 final  StepPortion? portion;

@JsonKey(name: 't')
final String $type;


/// Create a copy of MethodToken
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MethodRefCopyWith<MethodRef> get copyWith => _$MethodRefCopyWithImpl<MethodRef>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MethodRefToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MethodRef&&const DeepCollectionEquality().equals(other._refs, _refs)&&(identical(other.label, label) || other.label == label)&&(identical(other.amountRule, amountRule) || other.amountRule == amountRule)&&(identical(other.portion, portion) || other.portion == portion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_refs),label,amountRule,portion);

@override
String toString() {
  return 'MethodToken.ref(refs: $refs, label: $label, amountRule: $amountRule, portion: $portion)';
}


}

/// @nodoc
abstract mixin class $MethodRefCopyWith<$Res> implements $MethodTokenCopyWith<$Res> {
  factory $MethodRefCopyWith(MethodRef value, $Res Function(MethodRef) _then) = _$MethodRefCopyWithImpl;
@useResult
$Res call({
 List<String> refs, String label,@JsonKey(name: 'mention') ChipAmountRule amountRule, StepPortion? portion
});


$StepPortionCopyWith<$Res>? get portion;

}
/// @nodoc
class _$MethodRefCopyWithImpl<$Res>
    implements $MethodRefCopyWith<$Res> {
  _$MethodRefCopyWithImpl(this._self, this._then);

  final MethodRef _self;
  final $Res Function(MethodRef) _then;

/// Create a copy of MethodToken
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? refs = null,Object? label = null,Object? amountRule = null,Object? portion = freezed,}) {
  return _then(MethodRef(
refs: null == refs ? _self._refs : refs // ignore: cast_nullable_to_non_nullable
as List<String>,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,amountRule: null == amountRule ? _self.amountRule : amountRule // ignore: cast_nullable_to_non_nullable
as ChipAmountRule,portion: freezed == portion ? _self.portion : portion // ignore: cast_nullable_to_non_nullable
as StepPortion?,
  ));
}

/// Create a copy of MethodToken
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StepPortionCopyWith<$Res>? get portion {
    if (_self.portion == null) {
    return null;
  }

  return $StepPortionCopyWith<$Res>(_self.portion!, (value) {
    return _then(_self.copyWith(portion: value));
  });
}
}

/// @nodoc
@JsonSerializable()

class MethodTimer implements MethodToken {
  const MethodTimer({required this.lowSeconds, required this.highSeconds, final  String? $type}): $type = $type ?? 'timer';
  factory MethodTimer.fromJson(Map<String, dynamic> json) => _$MethodTimerFromJson(json);

 final  int lowSeconds;
 final  int highSeconds;

@JsonKey(name: 't')
final String $type;


/// Create a copy of MethodToken
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MethodTimerCopyWith<MethodTimer> get copyWith => _$MethodTimerCopyWithImpl<MethodTimer>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MethodTimerToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MethodTimer&&(identical(other.lowSeconds, lowSeconds) || other.lowSeconds == lowSeconds)&&(identical(other.highSeconds, highSeconds) || other.highSeconds == highSeconds));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,lowSeconds,highSeconds);

@override
String toString() {
  return 'MethodToken.timer(lowSeconds: $lowSeconds, highSeconds: $highSeconds)';
}


}

/// @nodoc
abstract mixin class $MethodTimerCopyWith<$Res> implements $MethodTokenCopyWith<$Res> {
  factory $MethodTimerCopyWith(MethodTimer value, $Res Function(MethodTimer) _then) = _$MethodTimerCopyWithImpl;
@useResult
$Res call({
 int lowSeconds, int highSeconds
});




}
/// @nodoc
class _$MethodTimerCopyWithImpl<$Res>
    implements $MethodTimerCopyWith<$Res> {
  _$MethodTimerCopyWithImpl(this._self, this._then);

  final MethodTimer _self;
  final $Res Function(MethodTimer) _then;

/// Create a copy of MethodToken
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? lowSeconds = null,Object? highSeconds = null,}) {
  return _then(MethodTimer(
lowSeconds: null == lowSeconds ? _self.lowSeconds : lowSeconds // ignore: cast_nullable_to_non_nullable
as int,highSeconds: null == highSeconds ? _self.highSeconds : highSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$MethodStep {

 List<MethodToken> get tokens;
/// Create a copy of MethodStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MethodStepCopyWith<MethodStep> get copyWith => _$MethodStepCopyWithImpl<MethodStep>(this as MethodStep, _$identity);

  /// Serializes this MethodStep to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MethodStep&&const DeepCollectionEquality().equals(other.tokens, tokens));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(tokens));

@override
String toString() {
  return 'MethodStep(tokens: $tokens)';
}


}

/// @nodoc
abstract mixin class $MethodStepCopyWith<$Res>  {
  factory $MethodStepCopyWith(MethodStep value, $Res Function(MethodStep) _then) = _$MethodStepCopyWithImpl;
@useResult
$Res call({
 List<MethodToken> tokens
});




}
/// @nodoc
class _$MethodStepCopyWithImpl<$Res>
    implements $MethodStepCopyWith<$Res> {
  _$MethodStepCopyWithImpl(this._self, this._then);

  final MethodStep _self;
  final $Res Function(MethodStep) _then;

/// Create a copy of MethodStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tokens = null,}) {
  return _then(_self.copyWith(
tokens: null == tokens ? _self.tokens : tokens // ignore: cast_nullable_to_non_nullable
as List<MethodToken>,
  ));
}

}


/// Adds pattern-matching-related methods to [MethodStep].
extension MethodStepPatterns on MethodStep {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MethodStep value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MethodStep() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MethodStep value)  $default,){
final _that = this;
switch (_that) {
case _MethodStep():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MethodStep value)?  $default,){
final _that = this;
switch (_that) {
case _MethodStep() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<MethodToken> tokens)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MethodStep() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<MethodToken> tokens)  $default,) {final _that = this;
switch (_that) {
case _MethodStep():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<MethodToken> tokens)?  $default,) {final _that = this;
switch (_that) {
case _MethodStep() when $default != null:
return $default(_that.tokens);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MethodStep implements MethodStep {
  const _MethodStep({final  List<MethodToken> tokens = const <MethodToken>[]}): _tokens = tokens;
  factory _MethodStep.fromJson(Map<String, dynamic> json) => _$MethodStepFromJson(json);

 final  List<MethodToken> _tokens;
@override@JsonKey() List<MethodToken> get tokens {
  if (_tokens is EqualUnmodifiableListView) return _tokens;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tokens);
}


/// Create a copy of MethodStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MethodStepCopyWith<_MethodStep> get copyWith => __$MethodStepCopyWithImpl<_MethodStep>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MethodStepToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MethodStep&&const DeepCollectionEquality().equals(other._tokens, _tokens));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_tokens));

@override
String toString() {
  return 'MethodStep(tokens: $tokens)';
}


}

/// @nodoc
abstract mixin class _$MethodStepCopyWith<$Res> implements $MethodStepCopyWith<$Res> {
  factory _$MethodStepCopyWith(_MethodStep value, $Res Function(_MethodStep) _then) = __$MethodStepCopyWithImpl;
@override @useResult
$Res call({
 List<MethodToken> tokens
});




}
/// @nodoc
class __$MethodStepCopyWithImpl<$Res>
    implements _$MethodStepCopyWith<$Res> {
  __$MethodStepCopyWithImpl(this._self, this._then);

  final _MethodStep _self;
  final $Res Function(_MethodStep) _then;

/// Create a copy of MethodStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tokens = null,}) {
  return _then(_MethodStep(
tokens: null == tokens ? _self._tokens : tokens // ignore: cast_nullable_to_non_nullable
as List<MethodToken>,
  ));
}


}

// dart format on
