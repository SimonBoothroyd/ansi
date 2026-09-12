// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'line_override.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LineOverride {

 LineOverrideAction get action;/// The row's id. Empty on an override [diffLineOverrides] has just
/// computed for a RECIPE line: which row it lands on is the repository's
/// business, since a line may already have one standing. An `add` carries
/// its own id from the moment it is drafted — the drafted line and the row
/// that stores it are the same thing.
 String get id;/// The recipe line this is about; null exactly on [LineOverrideAction.add]
/// (the server's `week_recipe_line_override_action_shape`).
 String? get recipeLineItemId; String? get ingredientId;/// Denormalised for display, exactly as `plan_entry.recipe_title` is: the
/// week's lines are read without a join back to the vocabulary.
 String get ingredientName;/// Ships as a column only in v1: the week rules on WHICH lines it cooks,
/// not on what they point at, so a sub-recipe swap for one week has no
/// door. A replace on a component line carries the line's own target back
/// unchanged.
 String? get subRecipeId; double? get quantity; Unit? get unit; String? get measureId; Measure? get measure; String? get note; int? get sortOrder;
/// Create a copy of LineOverride
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LineOverrideCopyWith<LineOverride> get copyWith => _$LineOverrideCopyWithImpl<LineOverride>(this as LineOverride, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LineOverride&&(identical(other.action, action) || other.action == action)&&(identical(other.id, id) || other.id == id)&&(identical(other.recipeLineItemId, recipeLineItemId) || other.recipeLineItemId == recipeLineItemId)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.ingredientName, ingredientName) || other.ingredientName == ingredientName)&&(identical(other.subRecipeId, subRecipeId) || other.subRecipeId == subRecipeId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.measureId, measureId) || other.measureId == measureId)&&(identical(other.measure, measure) || other.measure == measure)&&(identical(other.note, note) || other.note == note)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder));
}


@override
int get hashCode => Object.hash(runtimeType,action,id,recipeLineItemId,ingredientId,ingredientName,subRecipeId,quantity,unit,measureId,measure,note,sortOrder);

@override
String toString() {
  return 'LineOverride(action: $action, id: $id, recipeLineItemId: $recipeLineItemId, ingredientId: $ingredientId, ingredientName: $ingredientName, subRecipeId: $subRecipeId, quantity: $quantity, unit: $unit, measureId: $measureId, measure: $measure, note: $note, sortOrder: $sortOrder)';
}


}

/// @nodoc
abstract mixin class $LineOverrideCopyWith<$Res>  {
  factory $LineOverrideCopyWith(LineOverride value, $Res Function(LineOverride) _then) = _$LineOverrideCopyWithImpl;
@useResult
$Res call({
 LineOverrideAction action, String id, String? recipeLineItemId, String? ingredientId, String ingredientName, String? subRecipeId, double? quantity, Unit? unit, String? measureId, Measure? measure, String? note, int? sortOrder
});




}
/// @nodoc
class _$LineOverrideCopyWithImpl<$Res>
    implements $LineOverrideCopyWith<$Res> {
  _$LineOverrideCopyWithImpl(this._self, this._then);

  final LineOverride _self;
  final $Res Function(LineOverride) _then;

/// Create a copy of LineOverride
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? action = null,Object? id = null,Object? recipeLineItemId = freezed,Object? ingredientId = freezed,Object? ingredientName = null,Object? subRecipeId = freezed,Object? quantity = freezed,Object? unit = freezed,Object? measureId = freezed,Object? measure = freezed,Object? note = freezed,Object? sortOrder = freezed,}) {
  return _then(_self.copyWith(
action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as LineOverrideAction,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,recipeLineItemId: freezed == recipeLineItemId ? _self.recipeLineItemId : recipeLineItemId // ignore: cast_nullable_to_non_nullable
as String?,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,ingredientName: null == ingredientName ? _self.ingredientName : ingredientName // ignore: cast_nullable_to_non_nullable
as String,subRecipeId: freezed == subRecipeId ? _self.subRecipeId : subRecipeId // ignore: cast_nullable_to_non_nullable
as String?,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit?,measureId: freezed == measureId ? _self.measureId : measureId // ignore: cast_nullable_to_non_nullable
as String?,measure: freezed == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as Measure?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,sortOrder: freezed == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [LineOverride].
extension LineOverridePatterns on LineOverride {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LineOverride value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LineOverride() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LineOverride value)  $default,){
final _that = this;
switch (_that) {
case _LineOverride():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LineOverride value)?  $default,){
final _that = this;
switch (_that) {
case _LineOverride() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LineOverrideAction action,  String id,  String? recipeLineItemId,  String? ingredientId,  String ingredientName,  String? subRecipeId,  double? quantity,  Unit? unit,  String? measureId,  Measure? measure,  String? note,  int? sortOrder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LineOverride() when $default != null:
return $default(_that.action,_that.id,_that.recipeLineItemId,_that.ingredientId,_that.ingredientName,_that.subRecipeId,_that.quantity,_that.unit,_that.measureId,_that.measure,_that.note,_that.sortOrder);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LineOverrideAction action,  String id,  String? recipeLineItemId,  String? ingredientId,  String ingredientName,  String? subRecipeId,  double? quantity,  Unit? unit,  String? measureId,  Measure? measure,  String? note,  int? sortOrder)  $default,) {final _that = this;
switch (_that) {
case _LineOverride():
return $default(_that.action,_that.id,_that.recipeLineItemId,_that.ingredientId,_that.ingredientName,_that.subRecipeId,_that.quantity,_that.unit,_that.measureId,_that.measure,_that.note,_that.sortOrder);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LineOverrideAction action,  String id,  String? recipeLineItemId,  String? ingredientId,  String ingredientName,  String? subRecipeId,  double? quantity,  Unit? unit,  String? measureId,  Measure? measure,  String? note,  int? sortOrder)?  $default,) {final _that = this;
switch (_that) {
case _LineOverride() when $default != null:
return $default(_that.action,_that.id,_that.recipeLineItemId,_that.ingredientId,_that.ingredientName,_that.subRecipeId,_that.quantity,_that.unit,_that.measureId,_that.measure,_that.note,_that.sortOrder);case _:
  return null;

}
}

}

/// @nodoc


class _LineOverride extends LineOverride {
  const _LineOverride({required this.action, this.id = '', this.recipeLineItemId, this.ingredientId, this.ingredientName = '', this.subRecipeId, this.quantity, this.unit, this.measureId, this.measure, this.note, this.sortOrder}): super._();
  

@override final  LineOverrideAction action;
/// The row's id. Empty on an override [diffLineOverrides] has just
/// computed for a RECIPE line: which row it lands on is the repository's
/// business, since a line may already have one standing. An `add` carries
/// its own id from the moment it is drafted — the drafted line and the row
/// that stores it are the same thing.
@override@JsonKey() final  String id;
/// The recipe line this is about; null exactly on [LineOverrideAction.add]
/// (the server's `week_recipe_line_override_action_shape`).
@override final  String? recipeLineItemId;
@override final  String? ingredientId;
/// Denormalised for display, exactly as `plan_entry.recipe_title` is: the
/// week's lines are read without a join back to the vocabulary.
@override@JsonKey() final  String ingredientName;
/// Ships as a column only in v1: the week rules on WHICH lines it cooks,
/// not on what they point at, so a sub-recipe swap for one week has no
/// door. A replace on a component line carries the line's own target back
/// unchanged.
@override final  String? subRecipeId;
@override final  double? quantity;
@override final  Unit? unit;
@override final  String? measureId;
@override final  Measure? measure;
@override final  String? note;
@override final  int? sortOrder;

/// Create a copy of LineOverride
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LineOverrideCopyWith<_LineOverride> get copyWith => __$LineOverrideCopyWithImpl<_LineOverride>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LineOverride&&(identical(other.action, action) || other.action == action)&&(identical(other.id, id) || other.id == id)&&(identical(other.recipeLineItemId, recipeLineItemId) || other.recipeLineItemId == recipeLineItemId)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.ingredientName, ingredientName) || other.ingredientName == ingredientName)&&(identical(other.subRecipeId, subRecipeId) || other.subRecipeId == subRecipeId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.measureId, measureId) || other.measureId == measureId)&&(identical(other.measure, measure) || other.measure == measure)&&(identical(other.note, note) || other.note == note)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder));
}


@override
int get hashCode => Object.hash(runtimeType,action,id,recipeLineItemId,ingredientId,ingredientName,subRecipeId,quantity,unit,measureId,measure,note,sortOrder);

@override
String toString() {
  return 'LineOverride(action: $action, id: $id, recipeLineItemId: $recipeLineItemId, ingredientId: $ingredientId, ingredientName: $ingredientName, subRecipeId: $subRecipeId, quantity: $quantity, unit: $unit, measureId: $measureId, measure: $measure, note: $note, sortOrder: $sortOrder)';
}


}

/// @nodoc
abstract mixin class _$LineOverrideCopyWith<$Res> implements $LineOverrideCopyWith<$Res> {
  factory _$LineOverrideCopyWith(_LineOverride value, $Res Function(_LineOverride) _then) = __$LineOverrideCopyWithImpl;
@override @useResult
$Res call({
 LineOverrideAction action, String id, String? recipeLineItemId, String? ingredientId, String ingredientName, String? subRecipeId, double? quantity, Unit? unit, String? measureId, Measure? measure, String? note, int? sortOrder
});




}
/// @nodoc
class __$LineOverrideCopyWithImpl<$Res>
    implements _$LineOverrideCopyWith<$Res> {
  __$LineOverrideCopyWithImpl(this._self, this._then);

  final _LineOverride _self;
  final $Res Function(_LineOverride) _then;

/// Create a copy of LineOverride
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? action = null,Object? id = null,Object? recipeLineItemId = freezed,Object? ingredientId = freezed,Object? ingredientName = null,Object? subRecipeId = freezed,Object? quantity = freezed,Object? unit = freezed,Object? measureId = freezed,Object? measure = freezed,Object? note = freezed,Object? sortOrder = freezed,}) {
  return _then(_LineOverride(
action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as LineOverrideAction,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,recipeLineItemId: freezed == recipeLineItemId ? _self.recipeLineItemId : recipeLineItemId // ignore: cast_nullable_to_non_nullable
as String?,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,ingredientName: null == ingredientName ? _self.ingredientName : ingredientName // ignore: cast_nullable_to_non_nullable
as String,subRecipeId: freezed == subRecipeId ? _self.subRecipeId : subRecipeId // ignore: cast_nullable_to_non_nullable
as String?,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit?,measureId: freezed == measureId ? _self.measureId : measureId // ignore: cast_nullable_to_non_nullable
as String?,measure: freezed == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as Measure?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,sortOrder: freezed == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
