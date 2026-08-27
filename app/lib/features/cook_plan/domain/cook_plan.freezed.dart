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
mixin _$CookSession {

 String get recipeId; String get recipeTitle; double get servingsBase; int get cookDay; int? get keepsForDays; bool get freezable; int? get freezerDays;/// The meals this batch covers, ascending by day (may include repeats on a
/// day — e.g. a lunch and a dinner of the same dish).
 List<CoveredMeal> get covers;
/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CookSessionCopyWith<CookSession> get copyWith => _$CookSessionCopyWithImpl<CookSession>(this as CookSession, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CookSession&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.recipeTitle, recipeTitle) || other.recipeTitle == recipeTitle)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&const DeepCollectionEquality().equals(other.covers, covers));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,recipeTitle,servingsBase,cookDay,keepsForDays,freezable,freezerDays,const DeepCollectionEquality().hash(covers));

@override
String toString() {
  return 'CookSession(recipeId: $recipeId, recipeTitle: $recipeTitle, servingsBase: $servingsBase, cookDay: $cookDay, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, covers: $covers)';
}


}

/// @nodoc
abstract mixin class $CookSessionCopyWith<$Res>  {
  factory $CookSessionCopyWith(CookSession value, $Res Function(CookSession) _then) = _$CookSessionCopyWithImpl;
@useResult
$Res call({
 String recipeId, String recipeTitle, double servingsBase, int cookDay, int? keepsForDays, bool freezable, int? freezerDays, List<CoveredMeal> covers
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
@pragma('vm:prefer-inline') @override $Res call({Object? recipeId = null,Object? recipeTitle = null,Object? servingsBase = null,Object? cookDay = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? covers = null,}) {
  return _then(_self.copyWith(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,recipeTitle: null == recipeTitle ? _self.recipeTitle : recipeTitle // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,cookDay: null == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,covers: null == covers ? _self.covers : covers // ignore: cast_nullable_to_non_nullable
as List<CoveredMeal>,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String recipeId,  String recipeTitle,  double servingsBase,  int cookDay,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CoveredMeal> covers)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CookSession() when $default != null:
return $default(_that.recipeId,_that.recipeTitle,_that.servingsBase,_that.cookDay,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.covers);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String recipeId,  String recipeTitle,  double servingsBase,  int cookDay,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CoveredMeal> covers)  $default,) {final _that = this;
switch (_that) {
case _CookSession():
return $default(_that.recipeId,_that.recipeTitle,_that.servingsBase,_that.cookDay,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.covers);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String recipeId,  String recipeTitle,  double servingsBase,  int cookDay,  int? keepsForDays,  bool freezable,  int? freezerDays,  List<CoveredMeal> covers)?  $default,) {final _that = this;
switch (_that) {
case _CookSession() when $default != null:
return $default(_that.recipeId,_that.recipeTitle,_that.servingsBase,_that.cookDay,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.covers);case _:
  return null;

}
}

}

/// @nodoc


class _CookSession extends CookSession {
  const _CookSession({required this.recipeId, required this.recipeTitle, required this.servingsBase, required this.cookDay, this.keepsForDays, this.freezable = false, this.freezerDays, final  List<CoveredMeal> covers = const <CoveredMeal>[]}): _covers = covers,super._();
  

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


/// Create a copy of CookSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CookSessionCopyWith<_CookSession> get copyWith => __$CookSessionCopyWithImpl<_CookSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CookSession&&(identical(other.recipeId, recipeId) || other.recipeId == recipeId)&&(identical(other.recipeTitle, recipeTitle) || other.recipeTitle == recipeTitle)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&const DeepCollectionEquality().equals(other._covers, _covers));
}


@override
int get hashCode => Object.hash(runtimeType,recipeId,recipeTitle,servingsBase,cookDay,keepsForDays,freezable,freezerDays,const DeepCollectionEquality().hash(_covers));

@override
String toString() {
  return 'CookSession(recipeId: $recipeId, recipeTitle: $recipeTitle, servingsBase: $servingsBase, cookDay: $cookDay, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, covers: $covers)';
}


}

/// @nodoc
abstract mixin class _$CookSessionCopyWith<$Res> implements $CookSessionCopyWith<$Res> {
  factory _$CookSessionCopyWith(_CookSession value, $Res Function(_CookSession) _then) = __$CookSessionCopyWithImpl;
@override @useResult
$Res call({
 String recipeId, String recipeTitle, double servingsBase, int cookDay, int? keepsForDays, bool freezable, int? freezerDays, List<CoveredMeal> covers
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
@override @pragma('vm:prefer-inline') $Res call({Object? recipeId = null,Object? recipeTitle = null,Object? servingsBase = null,Object? cookDay = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? covers = null,}) {
  return _then(_CookSession(
recipeId: null == recipeId ? _self.recipeId : recipeId // ignore: cast_nullable_to_non_nullable
as String,recipeTitle: null == recipeTitle ? _self.recipeTitle : recipeTitle // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,cookDay: null == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,covers: null == covers ? _self._covers : covers // ignore: cast_nullable_to_non_nullable
as List<CoveredMeal>,
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
mixin _$CookPlan {

 List<RecipeCookPlan> get recipes;
/// Create a copy of CookPlan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CookPlanCopyWith<CookPlan> get copyWith => _$CookPlanCopyWithImpl<CookPlan>(this as CookPlan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CookPlan&&const DeepCollectionEquality().equals(other.recipes, recipes));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(recipes));

@override
String toString() {
  return 'CookPlan(recipes: $recipes)';
}


}

/// @nodoc
abstract mixin class $CookPlanCopyWith<$Res>  {
  factory $CookPlanCopyWith(CookPlan value, $Res Function(CookPlan) _then) = _$CookPlanCopyWithImpl;
@useResult
$Res call({
 List<RecipeCookPlan> recipes
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
@pragma('vm:prefer-inline') @override $Res call({Object? recipes = null,}) {
  return _then(_self.copyWith(
recipes: null == recipes ? _self.recipes : recipes // ignore: cast_nullable_to_non_nullable
as List<RecipeCookPlan>,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<RecipeCookPlan> recipes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CookPlan() when $default != null:
return $default(_that.recipes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<RecipeCookPlan> recipes)  $default,) {final _that = this;
switch (_that) {
case _CookPlan():
return $default(_that.recipes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<RecipeCookPlan> recipes)?  $default,) {final _that = this;
switch (_that) {
case _CookPlan() when $default != null:
return $default(_that.recipes);case _:
  return null;

}
}

}

/// @nodoc


class _CookPlan extends CookPlan {
  const _CookPlan({final  List<RecipeCookPlan> recipes = const <RecipeCookPlan>[]}): _recipes = recipes,super._();
  

 final  List<RecipeCookPlan> _recipes;
@override@JsonKey() List<RecipeCookPlan> get recipes {
  if (_recipes is EqualUnmodifiableListView) return _recipes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recipes);
}


/// Create a copy of CookPlan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CookPlanCopyWith<_CookPlan> get copyWith => __$CookPlanCopyWithImpl<_CookPlan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CookPlan&&const DeepCollectionEquality().equals(other._recipes, _recipes));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_recipes));

@override
String toString() {
  return 'CookPlan(recipes: $recipes)';
}


}

/// @nodoc
abstract mixin class _$CookPlanCopyWith<$Res> implements $CookPlanCopyWith<$Res> {
  factory _$CookPlanCopyWith(_CookPlan value, $Res Function(_CookPlan) _then) = __$CookPlanCopyWithImpl;
@override @useResult
$Res call({
 List<RecipeCookPlan> recipes
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
@override @pragma('vm:prefer-inline') $Res call({Object? recipes = null,}) {
  return _then(_CookPlan(
recipes: null == recipes ? _self._recipes : recipes // ignore: cast_nullable_to_non_nullable
as List<RecipeCookPlan>,
  ));
}


}

// dart format on
