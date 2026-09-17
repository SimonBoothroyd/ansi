// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'planning.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Member {

 String get id; String get displayName;/// The person's usual portion as a multiple of one recipe serving: `0.75`
/// for someone who eats three-quarters of a serving. A standing fact about
/// the person, spent wherever a demand is counted — the cook plan, the
/// shopping list and the macro lens all read it through [demandPortions].
/// Quarter steps from 0.25 to 3; the default `1` makes a member weigh
/// exactly one head.
 double get portionFactor;
/// Create a copy of Member
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MemberCopyWith<Member> get copyWith => _$MemberCopyWithImpl<Member>(this as Member, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Member&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.portionFactor, portionFactor) || other.portionFactor == portionFactor));
}


@override
int get hashCode => Object.hash(runtimeType,id,displayName,portionFactor);

@override
String toString() {
  return 'Member(id: $id, displayName: $displayName, portionFactor: $portionFactor)';
}


}

/// @nodoc
abstract mixin class $MemberCopyWith<$Res>  {
  factory $MemberCopyWith(Member value, $Res Function(Member) _then) = _$MemberCopyWithImpl;
@useResult
$Res call({
 String id, String displayName, double portionFactor
});




}
/// @nodoc
class _$MemberCopyWithImpl<$Res>
    implements $MemberCopyWith<$Res> {
  _$MemberCopyWithImpl(this._self, this._then);

  final Member _self;
  final $Res Function(Member) _then;

/// Create a copy of Member
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? portionFactor = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,portionFactor: null == portionFactor ? _self.portionFactor : portionFactor // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [Member].
extension MemberPatterns on Member {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Member value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Member() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Member value)  $default,){
final _that = this;
switch (_that) {
case _Member():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Member value)?  $default,){
final _that = this;
switch (_that) {
case _Member() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String displayName,  double portionFactor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Member() when $default != null:
return $default(_that.id,_that.displayName,_that.portionFactor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String displayName,  double portionFactor)  $default,) {final _that = this;
switch (_that) {
case _Member():
return $default(_that.id,_that.displayName,_that.portionFactor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String displayName,  double portionFactor)?  $default,) {final _that = this;
switch (_that) {
case _Member() when $default != null:
return $default(_that.id,_that.displayName,_that.portionFactor);case _:
  return null;

}
}

}

/// @nodoc


class _Member extends Member {
  const _Member({required this.id, required this.displayName, this.portionFactor = 1.0}): super._();
  

@override final  String id;
@override final  String displayName;
/// The person's usual portion as a multiple of one recipe serving: `0.75`
/// for someone who eats three-quarters of a serving. A standing fact about
/// the person, spent wherever a demand is counted — the cook plan, the
/// shopping list and the macro lens all read it through [demandPortions].
/// Quarter steps from 0.25 to 3; the default `1` makes a member weigh
/// exactly one head.
@override@JsonKey() final  double portionFactor;

/// Create a copy of Member
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MemberCopyWith<_Member> get copyWith => __$MemberCopyWithImpl<_Member>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Member&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.portionFactor, portionFactor) || other.portionFactor == portionFactor));
}


@override
int get hashCode => Object.hash(runtimeType,id,displayName,portionFactor);

@override
String toString() {
  return 'Member(id: $id, displayName: $displayName, portionFactor: $portionFactor)';
}


}

/// @nodoc
abstract mixin class _$MemberCopyWith<$Res> implements $MemberCopyWith<$Res> {
  factory _$MemberCopyWith(_Member value, $Res Function(_Member) _then) = __$MemberCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName, double portionFactor
});




}
/// @nodoc
class __$MemberCopyWithImpl<$Res>
    implements _$MemberCopyWith<$Res> {
  __$MemberCopyWithImpl(this._self, this._then);

  final _Member _self;
  final $Res Function(_Member) _then;

/// Create a copy of Member
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? portionFactor = null,}) {
  return _then(_Member(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,portionFactor: null == portionFactor ? _self.portionFactor : portionFactor // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc
mixin _$PlanEntry {

 String get id; int get dayOfWeek; String get mealSlot;/// The dish, when this meal is one. Null exactly when one of
/// [ingredientId] / [label] is set (the XOR).
 String? get recipeId; String? get recipeTitle;/// The thing this meal IS, when it is a bare ingredient. Null exactly when
/// one of [recipeId] / [label] is set.
 String? get ingredientId; String? get ingredientName;/// The words a meal eaten out IS — "Office lunch". Null exactly when one
/// of [recipeId] / [ingredientId] is set. There is nothing behind these
/// words: no recipe, no vocabulary row, nothing to open.
 String? get label;/// What ONE portion of a meal eaten out was worth, as STATED. Null means
/// not stated — never zero (invariant 3): the week names such a meal as
/// uncounted rather than weighing it at nothing. Always null on the other
/// two kinds, whose figures come from their recipe's lines or their
/// vocabulary row.
 Macros? get macros;/// The amount of ONE portion of an ingredient meal. Null (with [unit]) on
/// a meal that states no amount — which contributes nothing to a total and
/// says so, rather than being completed by a guess (invariant 3). Always
/// null on a recipe meal and on a meal eaten out.
 double? get quantity; Unit? get unit;/// The persisted `measure_id`, verbatim — kept even while [measure] is
/// unresolved (the row has not synced, or was soft-deleted) so a re-save
/// never wipes the FK, exactly as a recipe line's does.
 String? get measureId;/// The resolved named measure the amount is counted in ("1 bar"), when it
/// is. [unit] then holds the honest count fallback (`piece`).
 Measure? get measure;/// The vocab row's macros / basis / density, denormalised for the same
/// reason [recipeTitle] is: the week's macro sum is a pure function of the
/// week it already loaded, and reading it a second way — a whole-vocabulary
/// watch behind the Week screen — would be a second place to drift.
///
/// Null on a recipe meal, and null on an ingredient meal whose row has not
/// synced; `ingredientPortionMacros` (week_macros.dart) tells that apart
/// from a row that is present but a stub, and names each.
 IngredientNutrition? get nutrition; List<String> get eaterIds;/// How many portions to cook for. Null means "track the eater count"; a
/// number is an explicit override for big/small appetites (spec §8).
 int? get portions;
/// Create a copy of PlanEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanEntryCopyWith<PlanEntry> get copyWith => _$PlanEntryCopyWithImpl<PlanEntry>(this as PlanEntry, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.dayOfWeek, dayOfWeek) || other.dayOfWeek == dayOfWeek)&&(identical(other.mealSlot, mealSlot) || other.mealSlot == mealSlot)&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.recipeTitle, recipeTitle) || other.recipeTitle == recipeTitle)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.ingredientName, ingredientName) || other.ingredientName == ingredientName)&&(identical(other.label, label) || other.label == label)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.measureId, measureId) || other.measureId == measureId)&&(identical(other.measure, measure) || other.measure == measure)&&(identical(other.nutrition, nutrition) || other.nutrition == nutrition)&&const DeepCollectionEquality().equals(other.eaterIds, eaterIds)&&(identical(other.portions, portions) || other.portions == portions));
}


@override
int get hashCode => Object.hash(runtimeType,id,dayOfWeek,mealSlot,recipeId,recipeTitle,ingredientId,ingredientName,label,macros,quantity,unit,measureId,measure,nutrition,const DeepCollectionEquality().hash(eaterIds),portions);

@override
String toString() {
  return 'PlanEntry(id: $id, dayOfWeek: $dayOfWeek, mealSlot: $mealSlot, recipeId: $recipeId, recipeTitle: $recipeTitle, ingredientId: $ingredientId, ingredientName: $ingredientName, label: $label, macros: $macros, quantity: $quantity, unit: $unit, measureId: $measureId, measure: $measure, nutrition: $nutrition, eaterIds: $eaterIds, portions: $portions)';
}


}

/// @nodoc
abstract mixin class $PlanEntryCopyWith<$Res>  {
  factory $PlanEntryCopyWith(PlanEntry value, $Res Function(PlanEntry) _then) = _$PlanEntryCopyWithImpl;
@useResult
$Res call({
 String id, int dayOfWeek, String mealSlot, String? recipeId, String? recipeTitle, String? ingredientId, String? ingredientName, String? label, Macros? macros, double? quantity, Unit? unit, String? measureId, Measure? measure, IngredientNutrition? nutrition, List<String> eaterIds, int? portions
});




}
/// @nodoc
class _$PlanEntryCopyWithImpl<$Res>
    implements $PlanEntryCopyWith<$Res> {
  _$PlanEntryCopyWithImpl(this._self, this._then);

  final PlanEntry _self;
  final $Res Function(PlanEntry) _then;

/// Create a copy of PlanEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? dayOfWeek = null,Object? mealSlot = null,Object? recipeId = freezed,Object? recipeTitle = freezed,Object? ingredientId = freezed,Object? ingredientName = freezed,Object? label = freezed,Object? macros = freezed,Object? quantity = freezed,Object? unit = freezed,Object? measureId = freezed,Object? measure = freezed,Object? nutrition = freezed,Object? eaterIds = null,Object? portions = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,dayOfWeek: null == dayOfWeek ? _self.dayOfWeek : dayOfWeek // ignore: cast_nullable_to_non_nullable
as int,mealSlot: null == mealSlot ? _self.mealSlot : mealSlot // ignore: cast_nullable_to_non_nullable
as String,recipeId: freezed == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String?,recipeTitle: freezed == recipeTitle ? _self.recipeTitle : recipeTitle // ignore: cast_nullable_to_non_nullable
as String?,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,ingredientName: freezed == ingredientName ? _self.ingredientName : ingredientName // ignore: cast_nullable_to_non_nullable
as String?,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as Macros?,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit?,measureId: freezed == measureId ? _self.measureId : measureId // ignore: cast_nullable_to_non_nullable
as String?,measure: freezed == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as Measure?,nutrition: freezed == nutrition ? _self.nutrition : nutrition // ignore: cast_nullable_to_non_nullable
as IngredientNutrition?,eaterIds: null == eaterIds ? _self.eaterIds : eaterIds // ignore: cast_nullable_to_non_nullable
as List<String>,portions: freezed == portions ? _self.portions : portions // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [PlanEntry].
extension PlanEntryPatterns on PlanEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlanEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlanEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlanEntry value)  $default,){
final _that = this;
switch (_that) {
case _PlanEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlanEntry value)?  $default,){
final _that = this;
switch (_that) {
case _PlanEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  int dayOfWeek,  String mealSlot,  String? recipeId,  String? recipeTitle,  String? ingredientId,  String? ingredientName,  String? label,  Macros? macros,  double? quantity,  Unit? unit,  String? measureId,  Measure? measure,  IngredientNutrition? nutrition,  List<String> eaterIds,  int? portions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlanEntry() when $default != null:
return $default(_that.id,_that.dayOfWeek,_that.mealSlot,_that.recipeId,_that.recipeTitle,_that.ingredientId,_that.ingredientName,_that.label,_that.macros,_that.quantity,_that.unit,_that.measureId,_that.measure,_that.nutrition,_that.eaterIds,_that.portions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  int dayOfWeek,  String mealSlot,  String? recipeId,  String? recipeTitle,  String? ingredientId,  String? ingredientName,  String? label,  Macros? macros,  double? quantity,  Unit? unit,  String? measureId,  Measure? measure,  IngredientNutrition? nutrition,  List<String> eaterIds,  int? portions)  $default,) {final _that = this;
switch (_that) {
case _PlanEntry():
return $default(_that.id,_that.dayOfWeek,_that.mealSlot,_that.recipeId,_that.recipeTitle,_that.ingredientId,_that.ingredientName,_that.label,_that.macros,_that.quantity,_that.unit,_that.measureId,_that.measure,_that.nutrition,_that.eaterIds,_that.portions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  int dayOfWeek,  String mealSlot,  String? recipeId,  String? recipeTitle,  String? ingredientId,  String? ingredientName,  String? label,  Macros? macros,  double? quantity,  Unit? unit,  String? measureId,  Measure? measure,  IngredientNutrition? nutrition,  List<String> eaterIds,  int? portions)?  $default,) {final _that = this;
switch (_that) {
case _PlanEntry() when $default != null:
return $default(_that.id,_that.dayOfWeek,_that.mealSlot,_that.recipeId,_that.recipeTitle,_that.ingredientId,_that.ingredientName,_that.label,_that.macros,_that.quantity,_that.unit,_that.measureId,_that.measure,_that.nutrition,_that.eaterIds,_that.portions);case _:
  return null;

}
}

}

/// @nodoc


class _PlanEntry extends PlanEntry {
  const _PlanEntry({required this.id, required this.dayOfWeek, required this.mealSlot, this.recipeId, this.recipeTitle, this.ingredientId, this.ingredientName, this.label, this.macros, this.quantity, this.unit, this.measureId, this.measure, this.nutrition, final  List<String> eaterIds = const <String>[], this.portions}): _eaterIds = eaterIds,super._();
  

@override final  String id;
@override final  int dayOfWeek;
@override final  String mealSlot;
/// The dish, when this meal is one. Null exactly when one of
/// [ingredientId] / [label] is set (the XOR).
@override final  String? recipeId;
@override final  String? recipeTitle;
/// The thing this meal IS, when it is a bare ingredient. Null exactly when
/// one of [recipeId] / [label] is set.
@override final  String? ingredientId;
@override final  String? ingredientName;
/// The words a meal eaten out IS — "Office lunch". Null exactly when one
/// of [recipeId] / [ingredientId] is set. There is nothing behind these
/// words: no recipe, no vocabulary row, nothing to open.
@override final  String? label;
/// What ONE portion of a meal eaten out was worth, as STATED. Null means
/// not stated — never zero (invariant 3): the week names such a meal as
/// uncounted rather than weighing it at nothing. Always null on the other
/// two kinds, whose figures come from their recipe's lines or their
/// vocabulary row.
@override final  Macros? macros;
/// The amount of ONE portion of an ingredient meal. Null (with [unit]) on
/// a meal that states no amount — which contributes nothing to a total and
/// says so, rather than being completed by a guess (invariant 3). Always
/// null on a recipe meal and on a meal eaten out.
@override final  double? quantity;
@override final  Unit? unit;
/// The persisted `measure_id`, verbatim — kept even while [measure] is
/// unresolved (the row has not synced, or was soft-deleted) so a re-save
/// never wipes the FK, exactly as a recipe line's does.
@override final  String? measureId;
/// The resolved named measure the amount is counted in ("1 bar"), when it
/// is. [unit] then holds the honest count fallback (`piece`).
@override final  Measure? measure;
/// The vocab row's macros / basis / density, denormalised for the same
/// reason [recipeTitle] is: the week's macro sum is a pure function of the
/// week it already loaded, and reading it a second way — a whole-vocabulary
/// watch behind the Week screen — would be a second place to drift.
///
/// Null on a recipe meal, and null on an ingredient meal whose row has not
/// synced; `ingredientPortionMacros` (week_macros.dart) tells that apart
/// from a row that is present but a stub, and names each.
@override final  IngredientNutrition? nutrition;
 final  List<String> _eaterIds;
@override@JsonKey() List<String> get eaterIds {
  if (_eaterIds is EqualUnmodifiableListView) return _eaterIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_eaterIds);
}

/// How many portions to cook for. Null means "track the eater count"; a
/// number is an explicit override for big/small appetites (spec §8).
@override final  int? portions;

/// Create a copy of PlanEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanEntryCopyWith<_PlanEntry> get copyWith => __$PlanEntryCopyWithImpl<_PlanEntry>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.dayOfWeek, dayOfWeek) || other.dayOfWeek == dayOfWeek)&&(identical(other.mealSlot, mealSlot) || other.mealSlot == mealSlot)&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.recipeTitle, recipeTitle) || other.recipeTitle == recipeTitle)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.ingredientName, ingredientName) || other.ingredientName == ingredientName)&&(identical(other.label, label) || other.label == label)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.measureId, measureId) || other.measureId == measureId)&&(identical(other.measure, measure) || other.measure == measure)&&(identical(other.nutrition, nutrition) || other.nutrition == nutrition)&&const DeepCollectionEquality().equals(other._eaterIds, _eaterIds)&&(identical(other.portions, portions) || other.portions == portions));
}


@override
int get hashCode => Object.hash(runtimeType,id,dayOfWeek,mealSlot,recipeId,recipeTitle,ingredientId,ingredientName,label,macros,quantity,unit,measureId,measure,nutrition,const DeepCollectionEquality().hash(_eaterIds),portions);

@override
String toString() {
  return 'PlanEntry(id: $id, dayOfWeek: $dayOfWeek, mealSlot: $mealSlot, recipeId: $recipeId, recipeTitle: $recipeTitle, ingredientId: $ingredientId, ingredientName: $ingredientName, label: $label, macros: $macros, quantity: $quantity, unit: $unit, measureId: $measureId, measure: $measure, nutrition: $nutrition, eaterIds: $eaterIds, portions: $portions)';
}


}

/// @nodoc
abstract mixin class _$PlanEntryCopyWith<$Res> implements $PlanEntryCopyWith<$Res> {
  factory _$PlanEntryCopyWith(_PlanEntry value, $Res Function(_PlanEntry) _then) = __$PlanEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, int dayOfWeek, String mealSlot, String? recipeId, String? recipeTitle, String? ingredientId, String? ingredientName, String? label, Macros? macros, double? quantity, Unit? unit, String? measureId, Measure? measure, IngredientNutrition? nutrition, List<String> eaterIds, int? portions
});




}
/// @nodoc
class __$PlanEntryCopyWithImpl<$Res>
    implements _$PlanEntryCopyWith<$Res> {
  __$PlanEntryCopyWithImpl(this._self, this._then);

  final _PlanEntry _self;
  final $Res Function(_PlanEntry) _then;

/// Create a copy of PlanEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? dayOfWeek = null,Object? mealSlot = null,Object? recipeId = freezed,Object? recipeTitle = freezed,Object? ingredientId = freezed,Object? ingredientName = freezed,Object? label = freezed,Object? macros = freezed,Object? quantity = freezed,Object? unit = freezed,Object? measureId = freezed,Object? measure = freezed,Object? nutrition = freezed,Object? eaterIds = null,Object? portions = freezed,}) {
  return _then(_PlanEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,dayOfWeek: null == dayOfWeek ? _self.dayOfWeek : dayOfWeek // ignore: cast_nullable_to_non_nullable
as int,mealSlot: null == mealSlot ? _self.mealSlot : mealSlot // ignore: cast_nullable_to_non_nullable
as String,recipeId: freezed == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String?,recipeTitle: freezed == recipeTitle ? _self.recipeTitle : recipeTitle // ignore: cast_nullable_to_non_nullable
as String?,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,ingredientName: freezed == ingredientName ? _self.ingredientName : ingredientName // ignore: cast_nullable_to_non_nullable
as String?,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as Macros?,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit?,measureId: freezed == measureId ? _self.measureId : measureId // ignore: cast_nullable_to_non_nullable
as String?,measure: freezed == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as Measure?,nutrition: freezed == nutrition ? _self.nutrition : nutrition // ignore: cast_nullable_to_non_nullable
as IngredientNutrition?,eaterIds: null == eaterIds ? _self._eaterIds : eaterIds // ignore: cast_nullable_to_non_nullable
as List<String>,portions: freezed == portions ? _self.portions : portions // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$WeekPlan {

 String get id; DateTime get weekStart; String? get label; List<PlanEntry> get entries;
/// Create a copy of WeekPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WeekPlanCopyWith<WeekPlan> get copyWith => _$WeekPlanCopyWithImpl<WeekPlan>(this as WeekPlan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WeekPlan&&(identical(other.id, id) || other.id == id)&&(identical(other.weekStart, weekStart) || other.weekStart == weekStart)&&(identical(other.label, label) || other.label == label)&&const DeepCollectionEquality().equals(other.entries, entries));
}


@override
int get hashCode => Object.hash(runtimeType,id,weekStart,label,const DeepCollectionEquality().hash(entries));

@override
String toString() {
  return 'WeekPlan(id: $id, weekStart: $weekStart, label: $label, entries: $entries)';
}


}

/// @nodoc
abstract mixin class $WeekPlanCopyWith<$Res>  {
  factory $WeekPlanCopyWith(WeekPlan value, $Res Function(WeekPlan) _then) = _$WeekPlanCopyWithImpl;
@useResult
$Res call({
 String id, DateTime weekStart, String? label, List<PlanEntry> entries
});




}
/// @nodoc
class _$WeekPlanCopyWithImpl<$Res>
    implements $WeekPlanCopyWith<$Res> {
  _$WeekPlanCopyWithImpl(this._self, this._then);

  final WeekPlan _self;
  final $Res Function(WeekPlan) _then;

/// Create a copy of WeekPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? weekStart = null,Object? label = freezed,Object? entries = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,weekStart: null == weekStart ? _self.weekStart : weekStart // ignore: cast_nullable_to_non_nullable
as DateTime,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<PlanEntry>,
  ));
}

}


/// Adds pattern-matching-related methods to [WeekPlan].
extension WeekPlanPatterns on WeekPlan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WeekPlan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WeekPlan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WeekPlan value)  $default,){
final _that = this;
switch (_that) {
case _WeekPlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WeekPlan value)?  $default,){
final _that = this;
switch (_that) {
case _WeekPlan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  DateTime weekStart,  String? label,  List<PlanEntry> entries)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WeekPlan() when $default != null:
return $default(_that.id,_that.weekStart,_that.label,_that.entries);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  DateTime weekStart,  String? label,  List<PlanEntry> entries)  $default,) {final _that = this;
switch (_that) {
case _WeekPlan():
return $default(_that.id,_that.weekStart,_that.label,_that.entries);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  DateTime weekStart,  String? label,  List<PlanEntry> entries)?  $default,) {final _that = this;
switch (_that) {
case _WeekPlan() when $default != null:
return $default(_that.id,_that.weekStart,_that.label,_that.entries);case _:
  return null;

}
}

}

/// @nodoc


class _WeekPlan extends WeekPlan {
  const _WeekPlan({required this.id, required this.weekStart, this.label, final  List<PlanEntry> entries = const <PlanEntry>[]}): _entries = entries,super._();
  

@override final  String id;
@override final  DateTime weekStart;
@override final  String? label;
 final  List<PlanEntry> _entries;
@override@JsonKey() List<PlanEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}


/// Create a copy of WeekPlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WeekPlanCopyWith<_WeekPlan> get copyWith => __$WeekPlanCopyWithImpl<_WeekPlan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WeekPlan&&(identical(other.id, id) || other.id == id)&&(identical(other.weekStart, weekStart) || other.weekStart == weekStart)&&(identical(other.label, label) || other.label == label)&&const DeepCollectionEquality().equals(other._entries, _entries));
}


@override
int get hashCode => Object.hash(runtimeType,id,weekStart,label,const DeepCollectionEquality().hash(_entries));

@override
String toString() {
  return 'WeekPlan(id: $id, weekStart: $weekStart, label: $label, entries: $entries)';
}


}

/// @nodoc
abstract mixin class _$WeekPlanCopyWith<$Res> implements $WeekPlanCopyWith<$Res> {
  factory _$WeekPlanCopyWith(_WeekPlan value, $Res Function(_WeekPlan) _then) = __$WeekPlanCopyWithImpl;
@override @useResult
$Res call({
 String id, DateTime weekStart, String? label, List<PlanEntry> entries
});




}
/// @nodoc
class __$WeekPlanCopyWithImpl<$Res>
    implements _$WeekPlanCopyWith<$Res> {
  __$WeekPlanCopyWithImpl(this._self, this._then);

  final _WeekPlan _self;
  final $Res Function(_WeekPlan) _then;

/// Create a copy of WeekPlan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? weekStart = null,Object? label = freezed,Object? entries = null,}) {
  return _then(_WeekPlan(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,weekStart: null == weekStart ? _self.weekStart : weekStart // ignore: cast_nullable_to_non_nullable
as DateTime,label: freezed == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String?,entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<PlanEntry>,
  ));
}


}

// dart format on
