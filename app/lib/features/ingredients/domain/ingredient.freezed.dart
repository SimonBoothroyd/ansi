// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ingredient.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Ingredient {

 String get id; String get canonicalName; Unit get defaultUnit; IngredientStatus get status; String? get category; double? get densityGPerMl; Macros? get macros; MacrosBasis get macrosBasis;/// Distinct live measure labels this ingredient carries — the picker
/// row's "N measures" capability hint (7.7). Populated by list reads;
/// 0 where a caller didn't ask for it.
 int get measureCount;
/// Create a copy of Ingredient
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IngredientCopyWith<Ingredient> get copyWith => _$IngredientCopyWithImpl<Ingredient>(this as Ingredient, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Ingredient&&(identical(other.id, id) || other.id == id)&&(identical(other.canonicalName, canonicalName) || other.canonicalName == canonicalName)&&(identical(other.defaultUnit, defaultUnit) || other.defaultUnit == defaultUnit)&&(identical(other.status, status) || other.status == status)&&(identical(other.category, category) || other.category == category)&&(identical(other.densityGPerMl, densityGPerMl) || other.densityGPerMl == densityGPerMl)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.macrosBasis, macrosBasis) || other.macrosBasis == macrosBasis)&&(identical(other.measureCount, measureCount) || other.measureCount == measureCount));
}


@override
int get hashCode => Object.hash(runtimeType,id,canonicalName,defaultUnit,status,category,densityGPerMl,macros,macrosBasis,measureCount);

@override
String toString() {
  return 'Ingredient(id: $id, canonicalName: $canonicalName, defaultUnit: $defaultUnit, status: $status, category: $category, densityGPerMl: $densityGPerMl, macros: $macros, macrosBasis: $macrosBasis, measureCount: $measureCount)';
}


}

/// @nodoc
abstract mixin class $IngredientCopyWith<$Res>  {
  factory $IngredientCopyWith(Ingredient value, $Res Function(Ingredient) _then) = _$IngredientCopyWithImpl;
@useResult
$Res call({
 String id, String canonicalName, Unit defaultUnit, IngredientStatus status, String? category, double? densityGPerMl, Macros? macros, MacrosBasis macrosBasis, int measureCount
});




}
/// @nodoc
class _$IngredientCopyWithImpl<$Res>
    implements $IngredientCopyWith<$Res> {
  _$IngredientCopyWithImpl(this._self, this._then);

  final Ingredient _self;
  final $Res Function(Ingredient) _then;

/// Create a copy of Ingredient
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? canonicalName = null,Object? defaultUnit = null,Object? status = null,Object? category = freezed,Object? densityGPerMl = freezed,Object? macros = freezed,Object? macrosBasis = null,Object? measureCount = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,canonicalName: null == canonicalName ? _self.canonicalName : canonicalName // ignore: cast_nullable_to_non_nullable
as String,defaultUnit: null == defaultUnit ? _self.defaultUnit : defaultUnit // ignore: cast_nullable_to_non_nullable
as Unit,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as IngredientStatus,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,densityGPerMl: freezed == densityGPerMl ? _self.densityGPerMl : densityGPerMl // ignore: cast_nullable_to_non_nullable
as double?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as Macros?,macrosBasis: null == macrosBasis ? _self.macrosBasis : macrosBasis // ignore: cast_nullable_to_non_nullable
as MacrosBasis,measureCount: null == measureCount ? _self.measureCount : measureCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Ingredient].
extension IngredientPatterns on Ingredient {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Ingredient value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Ingredient() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Ingredient value)  $default,){
final _that = this;
switch (_that) {
case _Ingredient():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Ingredient value)?  $default,){
final _that = this;
switch (_that) {
case _Ingredient() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String canonicalName,  Unit defaultUnit,  IngredientStatus status,  String? category,  double? densityGPerMl,  Macros? macros,  MacrosBasis macrosBasis,  int measureCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Ingredient() when $default != null:
return $default(_that.id,_that.canonicalName,_that.defaultUnit,_that.status,_that.category,_that.densityGPerMl,_that.macros,_that.macrosBasis,_that.measureCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String canonicalName,  Unit defaultUnit,  IngredientStatus status,  String? category,  double? densityGPerMl,  Macros? macros,  MacrosBasis macrosBasis,  int measureCount)  $default,) {final _that = this;
switch (_that) {
case _Ingredient():
return $default(_that.id,_that.canonicalName,_that.defaultUnit,_that.status,_that.category,_that.densityGPerMl,_that.macros,_that.macrosBasis,_that.measureCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String canonicalName,  Unit defaultUnit,  IngredientStatus status,  String? category,  double? densityGPerMl,  Macros? macros,  MacrosBasis macrosBasis,  int measureCount)?  $default,) {final _that = this;
switch (_that) {
case _Ingredient() when $default != null:
return $default(_that.id,_that.canonicalName,_that.defaultUnit,_that.status,_that.category,_that.densityGPerMl,_that.macros,_that.macrosBasis,_that.measureCount);case _:
  return null;

}
}

}

/// @nodoc


class _Ingredient implements Ingredient {
  const _Ingredient({required this.id, required this.canonicalName, required this.defaultUnit, required this.status, this.category, this.densityGPerMl, this.macros, this.macrosBasis = MacrosBasis.perG, this.measureCount = 0});
  

@override final  String id;
@override final  String canonicalName;
@override final  Unit defaultUnit;
@override final  IngredientStatus status;
@override final  String? category;
@override final  double? densityGPerMl;
@override final  Macros? macros;
@override@JsonKey() final  MacrosBasis macrosBasis;
/// Distinct live measure labels this ingredient carries — the picker
/// row's "N measures" capability hint (7.7). Populated by list reads;
/// 0 where a caller didn't ask for it.
@override@JsonKey() final  int measureCount;

/// Create a copy of Ingredient
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IngredientCopyWith<_Ingredient> get copyWith => __$IngredientCopyWithImpl<_Ingredient>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Ingredient&&(identical(other.id, id) || other.id == id)&&(identical(other.canonicalName, canonicalName) || other.canonicalName == canonicalName)&&(identical(other.defaultUnit, defaultUnit) || other.defaultUnit == defaultUnit)&&(identical(other.status, status) || other.status == status)&&(identical(other.category, category) || other.category == category)&&(identical(other.densityGPerMl, densityGPerMl) || other.densityGPerMl == densityGPerMl)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.macrosBasis, macrosBasis) || other.macrosBasis == macrosBasis)&&(identical(other.measureCount, measureCount) || other.measureCount == measureCount));
}


@override
int get hashCode => Object.hash(runtimeType,id,canonicalName,defaultUnit,status,category,densityGPerMl,macros,macrosBasis,measureCount);

@override
String toString() {
  return 'Ingredient(id: $id, canonicalName: $canonicalName, defaultUnit: $defaultUnit, status: $status, category: $category, densityGPerMl: $densityGPerMl, macros: $macros, macrosBasis: $macrosBasis, measureCount: $measureCount)';
}


}

/// @nodoc
abstract mixin class _$IngredientCopyWith<$Res> implements $IngredientCopyWith<$Res> {
  factory _$IngredientCopyWith(_Ingredient value, $Res Function(_Ingredient) _then) = __$IngredientCopyWithImpl;
@override @useResult
$Res call({
 String id, String canonicalName, Unit defaultUnit, IngredientStatus status, String? category, double? densityGPerMl, Macros? macros, MacrosBasis macrosBasis, int measureCount
});




}
/// @nodoc
class __$IngredientCopyWithImpl<$Res>
    implements _$IngredientCopyWith<$Res> {
  __$IngredientCopyWithImpl(this._self, this._then);

  final _Ingredient _self;
  final $Res Function(_Ingredient) _then;

/// Create a copy of Ingredient
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? canonicalName = null,Object? defaultUnit = null,Object? status = null,Object? category = freezed,Object? densityGPerMl = freezed,Object? macros = freezed,Object? macrosBasis = null,Object? measureCount = null,}) {
  return _then(_Ingredient(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,canonicalName: null == canonicalName ? _self.canonicalName : canonicalName // ignore: cast_nullable_to_non_nullable
as String,defaultUnit: null == defaultUnit ? _self.defaultUnit : defaultUnit // ignore: cast_nullable_to_non_nullable
as Unit,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as IngredientStatus,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,densityGPerMl: freezed == densityGPerMl ? _self.densityGPerMl : densityGPerMl // ignore: cast_nullable_to_non_nullable
as double?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as Macros?,macrosBasis: null == macrosBasis ? _self.macrosBasis : macrosBasis // ignore: cast_nullable_to_non_nullable
as MacrosBasis,measureCount: null == measureCount ? _self.measureCount : measureCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
