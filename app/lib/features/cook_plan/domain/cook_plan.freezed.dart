// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'cook_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CoveredMeal {

 int get dayOfWeek; String get mealSlot; int get portions;
/// Create a copy of CoveredMeal
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoveredMealCopyWith<CoveredMeal> get copyWith => _$CoveredMealCopyWithImpl<CoveredMeal>(this as CoveredMeal, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CoveredMeal&&(identical(other.dayOfWeek, dayOfWeek) || other.dayOfWeek == dayOfWeek)&&(identical(other.mealSlot, mealSlot) || other.mealSlot == mealSlot)&&(identical(other.portions, portions) || other.portions == portions));
}


@override
int get hashCode => Object.hash(runtimeType,dayOfWeek,mealSlot,portions);

@override
String toString() {
  return 'CoveredMeal(dayOfWeek: $dayOfWeek, mealSlot: $mealSlot, portions: $portions)';
}


}

/// @nodoc
abstract mixin class $CoveredMealCopyWith<$Res>  {
  factory $CoveredMealCopyWith(CoveredMeal value, $Res Function(CoveredMeal) _then) = _$CoveredMealCopyWithImpl;
@useResult
$Res call({
 int dayOfWeek, String mealSlot, int portions
});




}
/// @nodoc
class _$CoveredMealCopyWithImpl<$Res>
    implements $CoveredMealCopyWith<$Res> {
  _$CoveredMealCopyWithImpl(this._self, this._then);

  final CoveredMeal _self;
  final $Res Function(CoveredMeal) _then;

/// Create a copy of CoveredMeal
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? dayOfWeek = null,Object? mealSlot = null,Object? portions = null,}) {
  return _then(_self.copyWith(
dayOfWeek: null == dayOfWeek ? _self.dayOfWeek : dayOfWeek // ignore: cast_nullable_to_non_nullable
as int,mealSlot: null == mealSlot ? _self.mealSlot : mealSlot // ignore: cast_nullable_to_non_nullable
as String,portions: null == portions ? _self.portions : portions // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [CoveredMeal].
extension CoveredMealPatterns on CoveredMeal {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CoveredMeal value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CoveredMeal() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CoveredMeal value)  $default,){
final _that = this;
switch (_that) {
case _CoveredMeal():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CoveredMeal value)?  $default,){
final _that = this;
switch (_that) {
case _CoveredMeal() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int dayOfWeek,  String mealSlot,  int portions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CoveredMeal() when $default != null:
return $default(_that.dayOfWeek,_that.mealSlot,_that.portions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int dayOfWeek,  String mealSlot,  int portions)  $default,) {final _that = this;
switch (_that) {
case _CoveredMeal():
return $default(_that.dayOfWeek,_that.mealSlot,_that.portions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int dayOfWeek,  String mealSlot,  int portions)?  $default,) {final _that = this;
switch (_that) {
case _CoveredMeal() when $default != null:
return $default(_that.dayOfWeek,_that.mealSlot,_that.portions);case _:
  return null;

}
}

}

/// @nodoc


class _CoveredMeal implements CoveredMeal {
  const _CoveredMeal({required this.dayOfWeek, required this.mealSlot, required this.portions});
  

@override final  int dayOfWeek;
@override final  String mealSlot;
@override final  int portions;

/// Create a copy of CoveredMeal
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CoveredMealCopyWith<_CoveredMeal> get copyWith => __$CoveredMealCopyWithImpl<_CoveredMeal>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CoveredMeal&&(identical(other.dayOfWeek, dayOfWeek) || other.dayOfWeek == dayOfWeek)&&(identical(other.mealSlot, mealSlot) || other.mealSlot == mealSlot)&&(identical(other.portions, portions) || other.portions == portions));
}


@override
int get hashCode => Object.hash(runtimeType,dayOfWeek,mealSlot,portions);

@override
String toString() {
  return 'CoveredMeal(dayOfWeek: $dayOfWeek, mealSlot: $mealSlot, portions: $portions)';
}


}

/// @nodoc
abstract mixin class _$CoveredMealCopyWith<$Res> implements $CoveredMealCopyWith<$Res> {
  factory _$CoveredMealCopyWith(_CoveredMeal value, $Res Function(_CoveredMeal) _then) = __$CoveredMealCopyWithImpl;
@override @useResult
$Res call({
 int dayOfWeek, String mealSlot, int portions
});




}
/// @nodoc
class __$CoveredMealCopyWithImpl<$Res>
    implements _$CoveredMealCopyWith<$Res> {
  __$CoveredMealCopyWithImpl(this._self, this._then);

  final _CoveredMeal _self;
  final $Res Function(_CoveredMeal) _then;

/// Create a copy of CoveredMeal
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? dayOfWeek = null,Object? mealSlot = null,Object? portions = null,}) {
  return _then(_CoveredMeal(
dayOfWeek: null == dayOfWeek ? _self.dayOfWeek : dayOfWeek // ignore: cast_nullable_to_non_nullable
as int,mealSlot: null == mealSlot ? _self.mealSlot : mealSlot // ignore: cast_nullable_to_non_nullable
as String,portions: null == portions ? _self.portions : portions // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$PlannedRecipe {

 String get recipeId; String get title; double get servingsBase;/// Fridge shelf life in days; drives clustering. Null = unknown (the recipe
/// has no shelf-life set yet) → the recipe is never split.
 int? get keepsForDays; bool get freezable;/// Freezer shelf life in days (only when [freezable]). Null = no limit.
 int? get freezerDays; List<CoveredMeal> get meals;
/// Create a copy of PlannedRecipe
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlannedRecipeCopyWith<PlannedRecipe> get copyWith => _$PlannedRecipeCopyWithImpl<PlannedRecipe>(this as PlannedRecipe, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlannedRecipe&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&const DeepCollectionEquality().equals(other.meals, meals));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,title,servingsBase,keepsForDays,freezable,freezerDays,const DeepCollectionEquality().hash(meals));

@override
String toString() {
  return 'PlannedRecipe(recipeId: $recipeId, title: $title, servingsBase: $servingsBase, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, meals: $meals)';
}


}

/// @nodoc
abstract mixin class $PlannedRecipeCopyWith<$Res>  {
  factory $PlannedRecipeCopyWith(PlannedRecipe value, $Res Function(PlannedRecipe) _then) = _$PlannedRecipeCopyWithImpl;
@useResult
$Res call({
 String recipeId, String title, double servingsBase, int? keepsForDays, bool freezable, int? freezerDays, List<CoveredMeal> meals
});




}
/// @nodoc
class _$PlannedRecipeCopyWithImpl<$Res>
    implements $PlannedRecipeCopyWith<$Res> {
  _$PlannedRecipeCopyWithImpl(this._self, this._then);

  final PlannedRecipe _self;
  final $Res Function(PlannedRecipe) _then;

/// Create a copy of PlannedRecipe
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? recipeId = null,Object? title = null,Object? servingsBase = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? meals = null,}) {
  return _then(_self.copyWith(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,meals: null == meals ? _self.meals : meals // ignore: cast_nullable_to_non_nullable
as List<CoveredMeal>,
  ));
}

}


/// Adds pattern-matching-related methods to [PlannedRecipe].
extension PlannedRecipePatterns on PlannedRecipe {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlannedRecipe value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlannedRecipe() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlannedRecipe value)  $default,){
final _that = this;
switch (_that) {
case _PlannedRecipe():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlannedRecipe value)?  $default,){
final _that = this;
switch (_that) {
case _PlannedRecipe() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String recipeId,  String title,  double servingsBase,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CoveredMeal> meals)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlannedRecipe() when $default != null:
return $default(_that.recipeId,_that.title,_that.servingsBase,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.meals);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String recipeId,  String title,  double servingsBase,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CoveredMeal> meals)  $default,) {final _that = this;
switch (_that) {
case _PlannedRecipe():
return $default(_that.recipeId,_that.title,_that.servingsBase,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.meals);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String recipeId,  String title,  double servingsBase,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CoveredMeal> meals)?  $default,) {final _that = this;
switch (_that) {
case _PlannedRecipe() when $default != null:
return $default(_that.recipeId,_that.title,_that.servingsBase,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.meals);case _:
  return null;

}
}

}

/// @nodoc


class _PlannedRecipe implements PlannedRecipe {
  const _PlannedRecipe({required this.recipeId, required this.title, required this.servingsBase, this.keepsForDays, this.freezable = false, this.freezerDays, final  List<CoveredMeal> meals = const <CoveredMeal>[]}): _meals = meals;
  

@override final  String recipeId;
@override final  String title;
@override final  double servingsBase;
/// Fridge shelf life in days; drives clustering. Null = unknown (the recipe
/// has no shelf-life set yet) → the recipe is never split.
@override final  int? keepsForDays;
@override@JsonKey() final  bool freezable;
/// Freezer shelf life in days (only when [freezable]). Null = no limit.
@override final  int? freezerDays;
 final  List<CoveredMeal> _meals;
@override@JsonKey() List<CoveredMeal> get meals {
  if (_meals is EqualUnmodifiableListView) return _meals;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_meals);
}


/// Create a copy of PlannedRecipe
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlannedRecipeCopyWith<_PlannedRecipe> get copyWith => __$PlannedRecipeCopyWithImpl<_PlannedRecipe>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlannedRecipe&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&const DeepCollectionEquality().equals(other._meals, _meals));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,title,servingsBase,keepsForDays,freezable,freezerDays,const DeepCollectionEquality().hash(_meals));

@override
String toString() {
  return 'PlannedRecipe(recipeId: $recipeId, title: $title, servingsBase: $servingsBase, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, meals: $meals)';
}


}

/// @nodoc
abstract mixin class _$PlannedRecipeCopyWith<$Res> implements $PlannedRecipeCopyWith<$Res> {
  factory _$PlannedRecipeCopyWith(_PlannedRecipe value, $Res Function(_PlannedRecipe) _then) = __$PlannedRecipeCopyWithImpl;
@override @useResult
$Res call({
 String recipeId, String title, double servingsBase, int? keepsForDays, bool freezable, int? freezerDays, List<CoveredMeal> meals
});




}
/// @nodoc
class __$PlannedRecipeCopyWithImpl<$Res>
    implements _$PlannedRecipeCopyWith<$Res> {
  __$PlannedRecipeCopyWithImpl(this._self, this._then);

  final _PlannedRecipe _self;
  final $Res Function(_PlannedRecipe) _then;

/// Create a copy of PlannedRecipe
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? recipeId = null,Object? title = null,Object? servingsBase = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? meals = null,}) {
  return _then(_PlannedRecipe(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,meals: null == meals ? _self._meals : meals // ignore: cast_nullable_to_non_nullable
as List<CoveredMeal>,
  ));
}


}

/// @nodoc
mixin _$ComponentDemand {

 String get parentRecipeId; String get parentTitle;/// The demanding parent session's cook day (0=Mon..6=Sun) — the day this
/// batch has to be ready *by*.
 int get cookDay;/// Batches of the sub-recipe, already multiplied through the parent
/// session's own scale factor.
 double get batches; String? get via;
/// Create a copy of ComponentDemand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ComponentDemandCopyWith<ComponentDemand> get copyWith => _$ComponentDemandCopyWithImpl<ComponentDemand>(this as ComponentDemand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ComponentDemand&&(identical(other.parentRecipeId, parentRecipeId) || other.parentRecipeId == parentRecipeId)&&(identical(other.parentTitle, parentTitle) || other.parentTitle == parentTitle)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.batches, batches) || other.batches == batches)&&(identical(other.via, via) || other.via == via));
}


@override
int get hashCode => Object.hash(runtimeType,parentRecipeId,parentTitle,cookDay,batches,via);

@override
String toString() {
  return 'ComponentDemand(parentRecipeId: $parentRecipeId, parentTitle: $parentTitle, cookDay: $cookDay, batches: $batches, via: $via)';
}


}

/// @nodoc
abstract mixin class $ComponentDemandCopyWith<$Res>  {
  factory $ComponentDemandCopyWith(ComponentDemand value, $Res Function(ComponentDemand) _then) = _$ComponentDemandCopyWithImpl;
@useResult
$Res call({
 String parentRecipeId, String parentTitle, int cookDay, double batches, String? via
});




}
/// @nodoc
class _$ComponentDemandCopyWithImpl<$Res>
    implements $ComponentDemandCopyWith<$Res> {
  _$ComponentDemandCopyWithImpl(this._self, this._then);

  final ComponentDemand _self;
  final $Res Function(ComponentDemand) _then;

/// Create a copy of ComponentDemand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? parentRecipeId = null,Object? parentTitle = null,Object? cookDay = null,Object? batches = null,Object? via = freezed,}) {
  return _then(_self.copyWith(
parentRecipeId: null == parentRecipeId ? _self.parentRecipeId : parentRecipeId // ignore: cast_nullable_to_non_nullable
as String,parentTitle: null == parentTitle ? _self.parentTitle : parentTitle // ignore: cast_nullable_to_non_nullable
as String,cookDay: null == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int,batches: null == batches ? _self.batches : batches // ignore: cast_nullable_to_non_nullable
as double,via: freezed == via ? _self.via : via // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ComponentDemand].
extension ComponentDemandPatterns on ComponentDemand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ComponentDemand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ComponentDemand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ComponentDemand value)  $default,){
final _that = this;
switch (_that) {
case _ComponentDemand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ComponentDemand value)?  $default,){
final _that = this;
switch (_that) {
case _ComponentDemand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String parentRecipeId,  String parentTitle,  int cookDay,  double batches,  String? via)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ComponentDemand() when $default != null:
return $default(_that.parentRecipeId,_that.parentTitle,_that.cookDay,_that.batches,_that.via);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String parentRecipeId,  String parentTitle,  int cookDay,  double batches,  String? via)  $default,) {final _that = this;
switch (_that) {
case _ComponentDemand():
return $default(_that.parentRecipeId,_that.parentTitle,_that.cookDay,_that.batches,_that.via);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String parentRecipeId,  String parentTitle,  int cookDay,  double batches,  String? via)?  $default,) {final _that = this;
switch (_that) {
case _ComponentDemand() when $default != null:
return $default(_that.parentRecipeId,_that.parentTitle,_that.cookDay,_that.batches,_that.via);case _:
  return null;

}
}

}

/// @nodoc


class _ComponentDemand implements ComponentDemand {
  const _ComponentDemand({required this.parentRecipeId, required this.parentTitle, required this.cookDay, required this.batches, this.via});
  

@override final  String parentRecipeId;
@override final  String parentTitle;
/// The demanding parent session's cook day (0=Mon..6=Sun) — the day this
/// batch has to be ready *by*.
@override final  int cookDay;
/// Batches of the sub-recipe, already multiplied through the parent
/// session's own scale factor.
@override final  double batches;
@override final  String? via;

/// Create a copy of ComponentDemand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ComponentDemandCopyWith<_ComponentDemand> get copyWith => __$ComponentDemandCopyWithImpl<_ComponentDemand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ComponentDemand&&(identical(other.parentRecipeId, parentRecipeId) || other.parentRecipeId == parentRecipeId)&&(identical(other.parentTitle, parentTitle) || other.parentTitle == parentTitle)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.batches, batches) || other.batches == batches)&&(identical(other.via, via) || other.via == via));
}


@override
int get hashCode => Object.hash(runtimeType,parentRecipeId,parentTitle,cookDay,batches,via);

@override
String toString() {
  return 'ComponentDemand(parentRecipeId: $parentRecipeId, parentTitle: $parentTitle, cookDay: $cookDay, batches: $batches, via: $via)';
}


}

/// @nodoc
abstract mixin class _$ComponentDemandCopyWith<$Res> implements $ComponentDemandCopyWith<$Res> {
  factory _$ComponentDemandCopyWith(_ComponentDemand value, $Res Function(_ComponentDemand) _then) = __$ComponentDemandCopyWithImpl;
@override @useResult
$Res call({
 String parentRecipeId, String parentTitle, int cookDay, double batches, String? via
});




}
/// @nodoc
class __$ComponentDemandCopyWithImpl<$Res>
    implements _$ComponentDemandCopyWith<$Res> {
  __$ComponentDemandCopyWithImpl(this._self, this._then);

  final _ComponentDemand _self;
  final $Res Function(_ComponentDemand) _then;

/// Create a copy of ComponentDemand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? parentRecipeId = null,Object? parentTitle = null,Object? cookDay = null,Object? batches = null,Object? via = freezed,}) {
  return _then(_ComponentDemand(
parentRecipeId: null == parentRecipeId ? _self.parentRecipeId : parentRecipeId // ignore: cast_nullable_to_non_nullable
as String,parentTitle: null == parentTitle ? _self.parentTitle : parentTitle // ignore: cast_nullable_to_non_nullable
as String,cookDay: null == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int,batches: null == batches ? _self.batches : batches // ignore: cast_nullable_to_non_nullable
as double,via: freezed == via ? _self.via : via // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$CookSession {

 String get recipeId; String get recipeTitle; double get servingsBase; int get cookDay; int? get keepsForDays; bool get freezable; int? get freezerDays;/// The meals this batch covers, ascending by day (may include repeats on a
/// day — e.g. a lunch and a dinner of the same dish).
 List<CoveredMeal> get covers;/// The component demands this batch answers (step 8.6). Non-empty exactly
/// for a component session.
 List<ComponentDemand> get demands;
/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CookSessionCopyWith<CookSession> get copyWith => _$CookSessionCopyWithImpl<CookSession>(this as CookSession, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CookSession&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.recipeTitle, recipeTitle) || other.recipeTitle == recipeTitle)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&const DeepCollectionEquality().equals(other.covers, covers)&&const DeepCollectionEquality().equals(other.demands, demands));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,recipeTitle,servingsBase,cookDay,keepsForDays,freezable,freezerDays,const DeepCollectionEquality().hash(covers),const DeepCollectionEquality().hash(demands));

@override
String toString() {
  return 'CookSession(recipeId: $recipeId, recipeTitle: $recipeTitle, servingsBase: $servingsBase, cookDay: $cookDay, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, covers: $covers, demands: $demands)';
}


}

/// @nodoc
abstract mixin class $CookSessionCopyWith<$Res>  {
  factory $CookSessionCopyWith(CookSession value, $Res Function(CookSession) _then) = _$CookSessionCopyWithImpl;
@useResult
$Res call({
 String recipeId, String recipeTitle, double servingsBase, int cookDay, int? keepsForDays, bool freezable, int? freezerDays, List<CoveredMeal> covers, List<ComponentDemand> demands
});




}
/// @nodoc
class _$CookSessionCopyWithImpl<$Res>
    implements $CookSessionCopyWith<$Res> {
  _$CookSessionCopyWithImpl(this._self, this._then);

  final CookSession _self;
  final $Res Function(CookSession) _then;

/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? recipeId = null,Object? recipeTitle = null,Object? servingsBase = null,Object? cookDay = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? covers = null,Object? demands = null,}) {
  return _then(_self.copyWith(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,recipeTitle: null == recipeTitle ? _self.recipeTitle : recipeTitle // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,cookDay: null == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,covers: null == covers ? _self.covers : covers // ignore: cast_nullable_to_non_nullable
as List<CoveredMeal>,demands: null == demands ? _self.demands : demands // ignore: cast_nullable_to_non_nullable
as List<ComponentDemand>,
  ));
}

}


/// Adds pattern-matching-related methods to [CookSession].
extension CookSessionPatterns on CookSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CookSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CookSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CookSession value)  $default,){
final _that = this;
switch (_that) {
case _CookSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CookSession value)?  $default,){
final _that = this;
switch (_that) {
case _CookSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String recipeId,  String recipeTitle,  double servingsBase,  int cookDay,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CoveredMeal> covers,  List<ComponentDemand> demands)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CookSession() when $default != null:
return $default(_that.recipeId,_that.recipeTitle,_that.servingsBase,_that.cookDay,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.covers,_that.demands);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String recipeId,  String recipeTitle,  double servingsBase,  int cookDay,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CoveredMeal> covers,  List<ComponentDemand> demands)  $default,) {final _that = this;
switch (_that) {
case _CookSession():
return $default(_that.recipeId,_that.recipeTitle,_that.servingsBase,_that.cookDay,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.covers,_that.demands);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String recipeId,  String recipeTitle,  double servingsBase,  int cookDay,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CoveredMeal> covers,  List<ComponentDemand> demands)?  $default,) {final _that = this;
switch (_that) {
case _CookSession() when $default != null:
return $default(_that.recipeId,_that.recipeTitle,_that.servingsBase,_that.cookDay,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.covers,_that.demands);case _:
  return null;

}
}

}

/// @nodoc


class _CookSession extends CookSession {
  const _CookSession({required this.recipeId, required this.recipeTitle, required this.servingsBase, required this.cookDay, this.keepsForDays, this.freezable = false, this.freezerDays, final  List<CoveredMeal> covers = const <CoveredMeal>[], final  List<ComponentDemand> demands = const <ComponentDemand>[]}): _covers = covers,_demands = demands,super._();
  

@override final  String recipeId;
@override final  String recipeTitle;
@override final  double servingsBase;
@override final  int cookDay;
@override final  int? keepsForDays;
@override@JsonKey() final  bool freezable;
@override final  int? freezerDays;
/// The meals this batch covers, ascending by day (may include repeats on a
/// day — e.g. a lunch and a dinner of the same dish).
 final  List<CoveredMeal> _covers;
/// The meals this batch covers, ascending by day (may include repeats on a
/// day — e.g. a lunch and a dinner of the same dish).
@override@JsonKey() List<CoveredMeal> get covers {
  if (_covers is EqualUnmodifiableListView) return _covers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_covers);
}

/// The component demands this batch answers (step 8.6). Non-empty exactly
/// for a component session.
 final  List<ComponentDemand> _demands;
/// The component demands this batch answers (step 8.6). Non-empty exactly
/// for a component session.
@override@JsonKey() List<ComponentDemand> get demands {
  if (_demands is EqualUnmodifiableListView) return _demands;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_demands);
}


/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CookSessionCopyWith<_CookSession> get copyWith => __$CookSessionCopyWithImpl<_CookSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CookSession&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.recipeTitle, recipeTitle) || other.recipeTitle == recipeTitle)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&const DeepCollectionEquality().equals(other._covers, _covers)&&const DeepCollectionEquality().equals(other._demands, _demands));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,recipeTitle,servingsBase,cookDay,keepsForDays,freezable,freezerDays,const DeepCollectionEquality().hash(_covers),const DeepCollectionEquality().hash(_demands));

@override
String toString() {
  return 'CookSession(recipeId: $recipeId, recipeTitle: $recipeTitle, servingsBase: $servingsBase, cookDay: $cookDay, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, covers: $covers, demands: $demands)';
}


}

/// @nodoc
abstract mixin class _$CookSessionCopyWith<$Res> implements $CookSessionCopyWith<$Res> {
  factory _$CookSessionCopyWith(_CookSession value, $Res Function(_CookSession) _then) = __$CookSessionCopyWithImpl;
@override @useResult
$Res call({
 String recipeId, String recipeTitle, double servingsBase, int cookDay, int? keepsForDays, bool freezable, int? freezerDays, List<CoveredMeal> covers, List<ComponentDemand> demands
});




}
/// @nodoc
class __$CookSessionCopyWithImpl<$Res>
    implements _$CookSessionCopyWith<$Res> {
  __$CookSessionCopyWithImpl(this._self, this._then);

  final _CookSession _self;
  final $Res Function(_CookSession) _then;

/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? recipeId = null,Object? recipeTitle = null,Object? servingsBase = null,Object? cookDay = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? covers = null,Object? demands = null,}) {
  return _then(_CookSession(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,recipeTitle: null == recipeTitle ? _self.recipeTitle : recipeTitle // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,cookDay: null == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,covers: null == covers ? _self._covers : covers // ignore: cast_nullable_to_non_nullable
as List<CoveredMeal>,demands: null == demands ? _self._demands : demands // ignore: cast_nullable_to_non_nullable
as List<ComponentDemand>,
  ));
}


}

/// @nodoc
mixin _$RecipeCookPlan {

 String get recipeId; String get title; double get servingsBase; int? get keepsForDays; bool get freezable; int? get freezerDays; List<CookSession> get sessions;
/// Create a copy of RecipeCookPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecipeCookPlanCopyWith<RecipeCookPlan> get copyWith => _$RecipeCookPlanCopyWithImpl<RecipeCookPlan>(this as RecipeCookPlan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecipeCookPlan&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&const DeepCollectionEquality().equals(other.sessions, sessions));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,title,servingsBase,keepsForDays,freezable,freezerDays,const DeepCollectionEquality().hash(sessions));

@override
String toString() {
  return 'RecipeCookPlan(recipeId: $recipeId, title: $title, servingsBase: $servingsBase, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, sessions: $sessions)';
}


}

/// @nodoc
abstract mixin class $RecipeCookPlanCopyWith<$Res>  {
  factory $RecipeCookPlanCopyWith(RecipeCookPlan value, $Res Function(RecipeCookPlan) _then) = _$RecipeCookPlanCopyWithImpl;
@useResult
$Res call({
 String recipeId, String title, double servingsBase, int? keepsForDays, bool freezable, int? freezerDays, List<CookSession> sessions
});




}
/// @nodoc
class _$RecipeCookPlanCopyWithImpl<$Res>
    implements $RecipeCookPlanCopyWith<$Res> {
  _$RecipeCookPlanCopyWithImpl(this._self, this._then);

  final RecipeCookPlan _self;
  final $Res Function(RecipeCookPlan) _then;

/// Create a copy of RecipeCookPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? recipeId = null,Object? title = null,Object? servingsBase = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? sessions = null,}) {
  return _then(_self.copyWith(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,sessions: null == sessions ? _self.sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<CookSession>,
  ));
}

}


/// Adds pattern-matching-related methods to [RecipeCookPlan].
extension RecipeCookPlanPatterns on RecipeCookPlan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecipeCookPlan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecipeCookPlan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecipeCookPlan value)  $default,){
final _that = this;
switch (_that) {
case _RecipeCookPlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecipeCookPlan value)?  $default,){
final _that = this;
switch (_that) {
case _RecipeCookPlan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String recipeId,  String title,  double servingsBase,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CookSession> sessions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecipeCookPlan() when $default != null:
return $default(_that.recipeId,_that.title,_that.servingsBase,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.sessions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String recipeId,  String title,  double servingsBase,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CookSession> sessions)  $default,) {final _that = this;
switch (_that) {
case _RecipeCookPlan():
return $default(_that.recipeId,_that.title,_that.servingsBase,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.sessions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String recipeId,  String title,  double servingsBase,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CookSession> sessions)?  $default,) {final _that = this;
switch (_that) {
case _RecipeCookPlan() when $default != null:
return $default(_that.recipeId,_that.title,_that.servingsBase,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.sessions);case _:
  return null;

}
}

}

/// @nodoc


class _RecipeCookPlan extends RecipeCookPlan {
  const _RecipeCookPlan({required this.recipeId, required this.title, required this.servingsBase, this.keepsForDays, this.freezable = false, this.freezerDays, final  List<CookSession> sessions = const <CookSession>[]}): _sessions = sessions,super._();
  

@override final  String recipeId;
@override final  String title;
@override final  double servingsBase;
@override final  int? keepsForDays;
@override@JsonKey() final  bool freezable;
@override final  int? freezerDays;
 final  List<CookSession> _sessions;
@override@JsonKey() List<CookSession> get sessions {
  if (_sessions is EqualUnmodifiableListView) return _sessions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sessions);
}


/// Create a copy of RecipeCookPlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecipeCookPlanCopyWith<_RecipeCookPlan> get copyWith => __$RecipeCookPlanCopyWithImpl<_RecipeCookPlan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecipeCookPlan&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&const DeepCollectionEquality().equals(other._sessions, _sessions));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,title,servingsBase,keepsForDays,freezable,freezerDays,const DeepCollectionEquality().hash(_sessions));

@override
String toString() {
  return 'RecipeCookPlan(recipeId: $recipeId, title: $title, servingsBase: $servingsBase, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, sessions: $sessions)';
}


}

/// @nodoc
abstract mixin class _$RecipeCookPlanCopyWith<$Res> implements $RecipeCookPlanCopyWith<$Res> {
  factory _$RecipeCookPlanCopyWith(_RecipeCookPlan value, $Res Function(_RecipeCookPlan) _then) = __$RecipeCookPlanCopyWithImpl;
@override @useResult
$Res call({
 String recipeId, String title, double servingsBase, int? keepsForDays, bool freezable, int? freezerDays, List<CookSession> sessions
});




}
/// @nodoc
class __$RecipeCookPlanCopyWithImpl<$Res>
    implements _$RecipeCookPlanCopyWith<$Res> {
  __$RecipeCookPlanCopyWithImpl(this._self, this._then);

  final _RecipeCookPlan _self;
  final $Res Function(_RecipeCookPlan) _then;

/// Create a copy of RecipeCookPlan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? recipeId = null,Object? title = null,Object? servingsBase = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? sessions = null,}) {
  return _then(_RecipeCookPlan(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,sessions: null == sessions ? _self._sessions : sessions // ignore: cast_nullable_to_non_nullable
as List<CookSession>,
  ));
}


}

/// @nodoc
mixin _$ComponentDemandSource {

 String get recipeId; String get title; int get cookDay; Unit get unit; double? get quantity;
/// Create a copy of ComponentDemandSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ComponentDemandSourceCopyWith<ComponentDemandSource> get copyWith => _$ComponentDemandSourceCopyWithImpl<ComponentDemandSource>(this as ComponentDemandSource, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ComponentDemandSource&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.quantity, quantity) || other.quantity == quantity));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,title,cookDay,unit,quantity);

@override
String toString() {
  return 'ComponentDemandSource(recipeId: $recipeId, title: $title, cookDay: $cookDay, unit: $unit, quantity: $quantity)';
}


}

/// @nodoc
abstract mixin class $ComponentDemandSourceCopyWith<$Res>  {
  factory $ComponentDemandSourceCopyWith(ComponentDemandSource value, $Res Function(ComponentDemandSource) _then) = _$ComponentDemandSourceCopyWithImpl;
@useResult
$Res call({
 String recipeId, String title, int cookDay, Unit unit, double? quantity
});




}
/// @nodoc
class _$ComponentDemandSourceCopyWithImpl<$Res>
    implements $ComponentDemandSourceCopyWith<$Res> {
  _$ComponentDemandSourceCopyWithImpl(this._self, this._then);

  final ComponentDemandSource _self;
  final $Res Function(ComponentDemandSource) _then;

/// Create a copy of ComponentDemandSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? recipeId = null,Object? title = null,Object? cookDay = null,Object? unit = null,Object? quantity = freezed,}) {
  return _then(_self.copyWith(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,cookDay: null == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [ComponentDemandSource].
extension ComponentDemandSourcePatterns on ComponentDemandSource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ComponentDemandSource value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ComponentDemandSource() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ComponentDemandSource value)  $default,){
final _that = this;
switch (_that) {
case _ComponentDemandSource():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ComponentDemandSource value)?  $default,){
final _that = this;
switch (_that) {
case _ComponentDemandSource() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String recipeId,  String title,  int cookDay,  Unit unit,  double? quantity)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ComponentDemandSource() when $default != null:
return $default(_that.recipeId,_that.title,_that.cookDay,_that.unit,_that.quantity);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String recipeId,  String title,  int cookDay,  Unit unit,  double? quantity)  $default,) {final _that = this;
switch (_that) {
case _ComponentDemandSource():
return $default(_that.recipeId,_that.title,_that.cookDay,_that.unit,_that.quantity);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String recipeId,  String title,  int cookDay,  Unit unit,  double? quantity)?  $default,) {final _that = this;
switch (_that) {
case _ComponentDemandSource() when $default != null:
return $default(_that.recipeId,_that.title,_that.cookDay,_that.unit,_that.quantity);case _:
  return null;

}
}

}

/// @nodoc


class _ComponentDemandSource implements ComponentDemandSource {
  const _ComponentDemandSource({required this.recipeId, required this.title, required this.cookDay, required this.unit, this.quantity});
  

@override final  String recipeId;
@override final  String title;
@override final  int cookDay;
@override final  Unit unit;
@override final  double? quantity;

/// Create a copy of ComponentDemandSource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ComponentDemandSourceCopyWith<_ComponentDemandSource> get copyWith => __$ComponentDemandSourceCopyWithImpl<_ComponentDemandSource>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ComponentDemandSource&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.quantity, quantity) || other.quantity == quantity));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,title,cookDay,unit,quantity);

@override
String toString() {
  return 'ComponentDemandSource(recipeId: $recipeId, title: $title, cookDay: $cookDay, unit: $unit, quantity: $quantity)';
}


}

/// @nodoc
abstract mixin class _$ComponentDemandSourceCopyWith<$Res> implements $ComponentDemandSourceCopyWith<$Res> {
  factory _$ComponentDemandSourceCopyWith(_ComponentDemandSource value, $Res Function(_ComponentDemandSource) _then) = __$ComponentDemandSourceCopyWithImpl;
@override @useResult
$Res call({
 String recipeId, String title, int cookDay, Unit unit, double? quantity
});




}
/// @nodoc
class __$ComponentDemandSourceCopyWithImpl<$Res>
    implements _$ComponentDemandSourceCopyWith<$Res> {
  __$ComponentDemandSourceCopyWithImpl(this._self, this._then);

  final _ComponentDemandSource _self;
  final $Res Function(_ComponentDemandSource) _then;

/// Create a copy of ComponentDemandSource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? recipeId = null,Object? title = null,Object? cookDay = null,Object? unit = null,Object? quantity = freezed,}) {
  return _then(_ComponentDemandSource(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,cookDay: null == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc
mixin _$ComponentGap {

/// The sub-recipe that cannot be derived.
 String get recipeId; String get title; UnresolvedComponentAmount get reason; List<ComponentDemandSource> get demandedBy;
/// Create a copy of ComponentGap
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ComponentGapCopyWith<ComponentGap> get copyWith => _$ComponentGapCopyWithImpl<ComponentGap>(this as ComponentGap, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ComponentGap&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.reason, reason) || other.reason == reason)&&const DeepCollectionEquality().equals(other.demandedBy, demandedBy));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,title,reason,const DeepCollectionEquality().hash(demandedBy));

@override
String toString() {
  return 'ComponentGap(recipeId: $recipeId, title: $title, reason: $reason, demandedBy: $demandedBy)';
}


}

/// @nodoc
abstract mixin class $ComponentGapCopyWith<$Res>  {
  factory $ComponentGapCopyWith(ComponentGap value, $Res Function(ComponentGap) _then) = _$ComponentGapCopyWithImpl;
@useResult
$Res call({
 String recipeId, String title, UnresolvedComponentAmount reason, List<ComponentDemandSource> demandedBy
});




}
/// @nodoc
class _$ComponentGapCopyWithImpl<$Res>
    implements $ComponentGapCopyWith<$Res> {
  _$ComponentGapCopyWithImpl(this._self, this._then);

  final ComponentGap _self;
  final $Res Function(ComponentGap) _then;

/// Create a copy of ComponentGap
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? recipeId = null,Object? title = null,Object? reason = null,Object? demandedBy = null,}) {
  return _then(_self.copyWith(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as UnresolvedComponentAmount,demandedBy: null == demandedBy ? _self.demandedBy : demandedBy // ignore: cast_nullable_to_non_nullable
as List<ComponentDemandSource>,
  ));
}

}


/// Adds pattern-matching-related methods to [ComponentGap].
extension ComponentGapPatterns on ComponentGap {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ComponentGap value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ComponentGap() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ComponentGap value)  $default,){
final _that = this;
switch (_that) {
case _ComponentGap():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ComponentGap value)?  $default,){
final _that = this;
switch (_that) {
case _ComponentGap() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String recipeId,  String title,  UnresolvedComponentAmount reason,  List<ComponentDemandSource> demandedBy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ComponentGap() when $default != null:
return $default(_that.recipeId,_that.title,_that.reason,_that.demandedBy);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String recipeId,  String title,  UnresolvedComponentAmount reason,  List<ComponentDemandSource> demandedBy)  $default,) {final _that = this;
switch (_that) {
case _ComponentGap():
return $default(_that.recipeId,_that.title,_that.reason,_that.demandedBy);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String recipeId,  String title,  UnresolvedComponentAmount reason,  List<ComponentDemandSource> demandedBy)?  $default,) {final _that = this;
switch (_that) {
case _ComponentGap() when $default != null:
return $default(_that.recipeId,_that.title,_that.reason,_that.demandedBy);case _:
  return null;

}
}

}

/// @nodoc


class _ComponentGap implements ComponentGap {
  const _ComponentGap({required this.recipeId, required this.title, required this.reason, final  List<ComponentDemandSource> demandedBy = const <ComponentDemandSource>[]}): _demandedBy = demandedBy;
  

/// The sub-recipe that cannot be derived.
@override final  String recipeId;
@override final  String title;
@override final  UnresolvedComponentAmount reason;
 final  List<ComponentDemandSource> _demandedBy;
@override@JsonKey() List<ComponentDemandSource> get demandedBy {
  if (_demandedBy is EqualUnmodifiableListView) return _demandedBy;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_demandedBy);
}


/// Create a copy of ComponentGap
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ComponentGapCopyWith<_ComponentGap> get copyWith => __$ComponentGapCopyWithImpl<_ComponentGap>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ComponentGap&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.title, title) || other.title == title)&&(identical(other.reason, reason) || other.reason == reason)&&const DeepCollectionEquality().equals(other._demandedBy, _demandedBy));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,title,reason,const DeepCollectionEquality().hash(_demandedBy));

@override
String toString() {
  return 'ComponentGap(recipeId: $recipeId, title: $title, reason: $reason, demandedBy: $demandedBy)';
}


}

/// @nodoc
abstract mixin class _$ComponentGapCopyWith<$Res> implements $ComponentGapCopyWith<$Res> {
  factory _$ComponentGapCopyWith(_ComponentGap value, $Res Function(_ComponentGap) _then) = __$ComponentGapCopyWithImpl;
@override @useResult
$Res call({
 String recipeId, String title, UnresolvedComponentAmount reason, List<ComponentDemandSource> demandedBy
});




}
/// @nodoc
class __$ComponentGapCopyWithImpl<$Res>
    implements _$ComponentGapCopyWith<$Res> {
  __$ComponentGapCopyWithImpl(this._self, this._then);

  final _ComponentGap _self;
  final $Res Function(_ComponentGap) _then;

/// Create a copy of ComponentGap
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? recipeId = null,Object? title = null,Object? reason = null,Object? demandedBy = null,}) {
  return _then(_ComponentGap(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as UnresolvedComponentAmount,demandedBy: null == demandedBy ? _self._demandedBy : demandedBy // ignore: cast_nullable_to_non_nullable
as List<ComponentDemandSource>,
  ));
}


}

/// @nodoc
mixin _$CookPlan {

 List<RecipeCookPlan> get recipes; List<ComponentGap> get gaps;
/// Create a copy of CookPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CookPlanCopyWith<CookPlan> get copyWith => _$CookPlanCopyWithImpl<CookPlan>(this as CookPlan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CookPlan&&const DeepCollectionEquality().equals(other.recipes, recipes)&&const DeepCollectionEquality().equals(other.gaps, gaps));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(recipes),const DeepCollectionEquality().hash(gaps));

@override
String toString() {
  return 'CookPlan(recipes: $recipes, gaps: $gaps)';
}


}

/// @nodoc
abstract mixin class $CookPlanCopyWith<$Res>  {
  factory $CookPlanCopyWith(CookPlan value, $Res Function(CookPlan) _then) = _$CookPlanCopyWithImpl;
@useResult
$Res call({
 List<RecipeCookPlan> recipes, List<ComponentGap> gaps
});




}
/// @nodoc
class _$CookPlanCopyWithImpl<$Res>
    implements $CookPlanCopyWith<$Res> {
  _$CookPlanCopyWithImpl(this._self, this._then);

  final CookPlan _self;
  final $Res Function(CookPlan) _then;

/// Create a copy of CookPlan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? recipes = null,Object? gaps = null,}) {
  return _then(_self.copyWith(
recipes: null == recipes ? _self.recipes : recipes // ignore: cast_nullable_to_non_nullable
as List<RecipeCookPlan>,gaps: null == gaps ? _self.gaps : gaps // ignore: cast_nullable_to_non_nullable
as List<ComponentGap>,
  ));
}

}


/// Adds pattern-matching-related methods to [CookPlan].
extension CookPlanPatterns on CookPlan {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CookPlan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CookPlan() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CookPlan value)  $default,){
final _that = this;
switch (_that) {
case _CookPlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CookPlan value)?  $default,){
final _that = this;
switch (_that) {
case _CookPlan() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<RecipeCookPlan> recipes,  List<ComponentGap> gaps)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CookPlan() when $default != null:
return $default(_that.recipes,_that.gaps);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<RecipeCookPlan> recipes,  List<ComponentGap> gaps)  $default,) {final _that = this;
switch (_that) {
case _CookPlan():
return $default(_that.recipes,_that.gaps);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<RecipeCookPlan> recipes,  List<ComponentGap> gaps)?  $default,) {final _that = this;
switch (_that) {
case _CookPlan() when $default != null:
return $default(_that.recipes,_that.gaps);case _:
  return null;

}
}

}

/// @nodoc


class _CookPlan extends CookPlan {
  const _CookPlan({final  List<RecipeCookPlan> recipes = const <RecipeCookPlan>[], final  List<ComponentGap> gaps = const <ComponentGap>[]}): _recipes = recipes,_gaps = gaps,super._();
  

 final  List<RecipeCookPlan> _recipes;
@override@JsonKey() List<RecipeCookPlan> get recipes {
  if (_recipes is EqualUnmodifiableListView) return _recipes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recipes);
}

 final  List<ComponentGap> _gaps;
@override@JsonKey() List<ComponentGap> get gaps {
  if (_gaps is EqualUnmodifiableListView) return _gaps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_gaps);
}


/// Create a copy of CookPlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CookPlanCopyWith<_CookPlan> get copyWith => __$CookPlanCopyWithImpl<_CookPlan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CookPlan&&const DeepCollectionEquality().equals(other._recipes, _recipes)&&const DeepCollectionEquality().equals(other._gaps, _gaps));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_recipes),const DeepCollectionEquality().hash(_gaps));

@override
String toString() {
  return 'CookPlan(recipes: $recipes, gaps: $gaps)';
}


}

/// @nodoc
abstract mixin class _$CookPlanCopyWith<$Res> implements $CookPlanCopyWith<$Res> {
  factory _$CookPlanCopyWith(_CookPlan value, $Res Function(_CookPlan) _then) = __$CookPlanCopyWithImpl;
@override @useResult
$Res call({
 List<RecipeCookPlan> recipes, List<ComponentGap> gaps
});




}
/// @nodoc
class __$CookPlanCopyWithImpl<$Res>
    implements _$CookPlanCopyWith<$Res> {
  __$CookPlanCopyWithImpl(this._self, this._then);

  final _CookPlan _self;
  final $Res Function(_CookPlan) _then;

/// Create a copy of CookPlan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? recipes = null,Object? gaps = null,}) {
  return _then(_CookPlan(
recipes: null == recipes ? _self._recipes : recipes // ignore: cast_nullable_to_non_nullable
as List<RecipeCookPlan>,gaps: null == gaps ? _self._gaps : gaps // ignore: cast_nullable_to_non_nullable
as List<ComponentGap>,
  ));
}


}

// dart format on
