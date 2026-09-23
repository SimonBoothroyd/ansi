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

 String get id; String get canonicalName; Unit get defaultUnit; IngredientStatus get status; String? get category; double? get densityGPerMl;/// The sentence [densityGPerMl] was said as ("⅓ cup weighs 40 g"), as
/// stored. Read it through [densitySaidOf], which drops one that no longer
/// states the stored number. Null when the density came from a door that
/// said no sentence.
 DensitySaid? get densitySaid; Macros? get macros; MacrosBasis get macrosBasis;/// The explicit allowed-unit list (ADR-0008), parsed from the row's
/// `allowed_units` jsonb with unknown ids dropped. Null for a legacy or
/// unsynced row; pickers then derive `defaultAllowedUnitSet`.
 List<Unit>? get allowedUnits;/// What one of this ingredient weighs, in the row's basis unit (ADR-0015).
/// It unlocks `piece` as density unlocks the volume units. Null means
/// `piece` is not sayable; a piece-default row with a null is named on the
/// form and refused at Save.
 double? get pieceBasisAmount;/// Where [pieceBasisAmount] came from: `manual`, `borrowed from <label>`
/// for a seeded copy of a curated size, or `seed:typical`. Shown, never
/// interpreted. Null when there is no weight.
 String? get pieceSource;/// Distinct live measure labels, for the picker row's "N measures" hint.
/// Populated by list reads; 0 otherwise.
 int get measureCount;/// The row's provenance stamp: `seed`, `manual`, `import_stub`,
/// `usda_fdc:<fdc_id>`, `off:<barcode>`, [labelPhotoSource], or
/// [usdaDeclinedSource]. Shown, never treated as truth; a
/// machine-supplied one still waits for a human confirm. Null when the
/// caller did not select it.
 String? get source;/// The food the row was filled from, named: `usda_food.description` for a
/// pick, the pack's brand and product for a scan. Lets every surface say
/// which food filled the row, offline. Survives a decline. Null when
/// nothing filled the row, and null on a photographed label, which names
/// no food — the person had already named the row.
 String? get sourceLabel;/// How much of the query the matched USDA description covered, 0..1 (the
/// idf-weighted coverage `probe_usda` returns). Stored so `UsdaMatchFit`
/// reads the same offline. Shown, never acted on. Null on a barcode row;
/// cleared by a decline.
 double? get sourceScore;/// Whether a human has overridden the macros, macros basis or density a
/// lookup filled in, on a row whose [source] is a lookup stamp. Renames,
/// unit toggles, measures and aliases never set it. A fresh pick clears it.
 bool get sourceEdited;
/// Create a copy of Ingredient
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IngredientCopyWith<Ingredient> get copyWith => _$IngredientCopyWithImpl<Ingredient>(this as Ingredient, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Ingredient&&(identical(other.id, id) || other.id == id)&&(identical(other.canonicalName, canonicalName) || other.canonicalName == canonicalName)&&(identical(other.defaultUnit, defaultUnit) || other.defaultUnit == defaultUnit)&&(identical(other.status, status) || other.status == status)&&(identical(other.category, category) || other.category == category)&&(identical(other.densityGPerMl, densityGPerMl) || other.densityGPerMl == densityGPerMl)&&(identical(other.densitySaid, densitySaid) || other.densitySaid == densitySaid)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.macrosBasis, macrosBasis) || other.macrosBasis == macrosBasis)&&const DeepCollectionEquality().equals(other.allowedUnits, allowedUnits)&&(identical(other.pieceBasisAmount, pieceBasisAmount) || other.pieceBasisAmount == pieceBasisAmount)&&(identical(other.pieceSource, pieceSource) || other.pieceSource == pieceSource)&&(identical(other.measureCount, measureCount) || other.measureCount == measureCount)&&(identical(other.source, source) || other.source == source)&&(identical(other.sourceLabel, sourceLabel) || other.sourceLabel == sourceLabel)&&(identical(other.sourceScore, sourceScore) || other.sourceScore == sourceScore)&&(identical(other.sourceEdited, sourceEdited) || other.sourceEdited == sourceEdited));
}


@override
int get hashCode => Object.hash(runtimeType,id,canonicalName,defaultUnit,status,category,densityGPerMl,densitySaid,macros,macrosBasis,const DeepCollectionEquality().hash(allowedUnits),pieceBasisAmount,pieceSource,measureCount,source,sourceLabel,sourceScore,sourceEdited);

@override
String toString() {
  return 'Ingredient(id: $id, canonicalName: $canonicalName, defaultUnit: $defaultUnit, status: $status, category: $category, densityGPerMl: $densityGPerMl, densitySaid: $densitySaid, macros: $macros, macrosBasis: $macrosBasis, allowedUnits: $allowedUnits, pieceBasisAmount: $pieceBasisAmount, pieceSource: $pieceSource, measureCount: $measureCount, source: $source, sourceLabel: $sourceLabel, sourceScore: $sourceScore, sourceEdited: $sourceEdited)';
}


}

/// @nodoc
abstract mixin class $IngredientCopyWith<$Res>  {
  factory $IngredientCopyWith(Ingredient value, $Res Function(Ingredient) _then) = _$IngredientCopyWithImpl;
@useResult
$Res call({
 String id, String canonicalName, Unit defaultUnit, IngredientStatus status, String? category, double? densityGPerMl, DensitySaid? densitySaid, Macros? macros, MacrosBasis macrosBasis, List<Unit>? allowedUnits, double? pieceBasisAmount, String? pieceSource, int measureCount, String? source, String? sourceLabel, double? sourceScore, bool sourceEdited
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? canonicalName = null,Object? defaultUnit = null,Object? status = null,Object? category = freezed,Object? densityGPerMl = freezed,Object? densitySaid = freezed,Object? macros = freezed,Object? macrosBasis = null,Object? allowedUnits = freezed,Object? pieceBasisAmount = freezed,Object? pieceSource = freezed,Object? measureCount = null,Object? source = freezed,Object? sourceLabel = freezed,Object? sourceScore = freezed,Object? sourceEdited = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,canonicalName: null == canonicalName ? _self.canonicalName : canonicalName // ignore: cast_nullable_to_non_nullable
as String,defaultUnit: null == defaultUnit ? _self.defaultUnit : defaultUnit // ignore: cast_nullable_to_non_nullable
as Unit,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as IngredientStatus,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,densityGPerMl: freezed == densityGPerMl ? _self.densityGPerMl : densityGPerMl // ignore: cast_nullable_to_non_nullable
as double?,densitySaid: freezed == densitySaid ? _self.densitySaid : densitySaid // ignore: cast_nullable_to_non_nullable
as DensitySaid?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as Macros?,macrosBasis: null == macrosBasis ? _self.macrosBasis : macrosBasis // ignore: cast_nullable_to_non_nullable
as MacrosBasis,allowedUnits: freezed == allowedUnits ? _self.allowedUnits : allowedUnits // ignore: cast_nullable_to_non_nullable
as List<Unit>?,pieceBasisAmount: freezed == pieceBasisAmount ? _self.pieceBasisAmount : pieceBasisAmount // ignore: cast_nullable_to_non_nullable
as double?,pieceSource: freezed == pieceSource ? _self.pieceSource : pieceSource // ignore: cast_nullable_to_non_nullable
as String?,measureCount: null == measureCount ? _self.measureCount : measureCount // ignore: cast_nullable_to_non_nullable
as int,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,sourceLabel: freezed == sourceLabel ? _self.sourceLabel : sourceLabel // ignore: cast_nullable_to_non_nullable
as String?,sourceScore: freezed == sourceScore ? _self.sourceScore : sourceScore // ignore: cast_nullable_to_non_nullable
as double?,sourceEdited: null == sourceEdited ? _self.sourceEdited : sourceEdited // ignore: cast_nullable_to_non_nullable
as bool,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String canonicalName,  Unit defaultUnit,  IngredientStatus status,  String? category,  double? densityGPerMl,  DensitySaid? densitySaid,  Macros? macros,  MacrosBasis macrosBasis,  List<Unit>? allowedUnits,  double? pieceBasisAmount,  String? pieceSource,  int measureCount,  String? source,  String? sourceLabel,  double? sourceScore,  bool sourceEdited)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Ingredient() when $default != null:
return $default(_that.id,_that.canonicalName,_that.defaultUnit,_that.status,_that.category,_that.densityGPerMl,_that.densitySaid,_that.macros,_that.macrosBasis,_that.allowedUnits,_that.pieceBasisAmount,_that.pieceSource,_that.measureCount,_that.source,_that.sourceLabel,_that.sourceScore,_that.sourceEdited);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String canonicalName,  Unit defaultUnit,  IngredientStatus status,  String? category,  double? densityGPerMl,  DensitySaid? densitySaid,  Macros? macros,  MacrosBasis macrosBasis,  List<Unit>? allowedUnits,  double? pieceBasisAmount,  String? pieceSource,  int measureCount,  String? source,  String? sourceLabel,  double? sourceScore,  bool sourceEdited)  $default,) {final _that = this;
switch (_that) {
case _Ingredient():
return $default(_that.id,_that.canonicalName,_that.defaultUnit,_that.status,_that.category,_that.densityGPerMl,_that.densitySaid,_that.macros,_that.macrosBasis,_that.allowedUnits,_that.pieceBasisAmount,_that.pieceSource,_that.measureCount,_that.source,_that.sourceLabel,_that.sourceScore,_that.sourceEdited);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String canonicalName,  Unit defaultUnit,  IngredientStatus status,  String? category,  double? densityGPerMl,  DensitySaid? densitySaid,  Macros? macros,  MacrosBasis macrosBasis,  List<Unit>? allowedUnits,  double? pieceBasisAmount,  String? pieceSource,  int measureCount,  String? source,  String? sourceLabel,  double? sourceScore,  bool sourceEdited)?  $default,) {final _that = this;
switch (_that) {
case _Ingredient() when $default != null:
return $default(_that.id,_that.canonicalName,_that.defaultUnit,_that.status,_that.category,_that.densityGPerMl,_that.densitySaid,_that.macros,_that.macrosBasis,_that.allowedUnits,_that.pieceBasisAmount,_that.pieceSource,_that.measureCount,_that.source,_that.sourceLabel,_that.sourceScore,_that.sourceEdited);case _:
  return null;

}
}

}

/// @nodoc


class _Ingredient implements Ingredient {
  const _Ingredient({required this.id, required this.canonicalName, required this.defaultUnit, required this.status, this.category, this.densityGPerMl, this.densitySaid, this.macros, this.macrosBasis = MacrosBasis.perG, final  List<Unit>? allowedUnits, this.pieceBasisAmount, this.pieceSource, this.measureCount = 0, this.source, this.sourceLabel, this.sourceScore, this.sourceEdited = false}): _allowedUnits = allowedUnits;
  

@override final  String id;
@override final  String canonicalName;
@override final  Unit defaultUnit;
@override final  IngredientStatus status;
@override final  String? category;
@override final  double? densityGPerMl;
/// The sentence [densityGPerMl] was said as ("⅓ cup weighs 40 g"), as
/// stored. Read it through [densitySaidOf], which drops one that no longer
/// states the stored number. Null when the density came from a door that
/// said no sentence.
@override final  DensitySaid? densitySaid;
@override final  Macros? macros;
@override@JsonKey() final  MacrosBasis macrosBasis;
/// The explicit allowed-unit list (ADR-0008), parsed from the row's
/// `allowed_units` jsonb with unknown ids dropped. Null for a legacy or
/// unsynced row; pickers then derive `defaultAllowedUnitSet`.
 final  List<Unit>? _allowedUnits;
/// The explicit allowed-unit list (ADR-0008), parsed from the row's
/// `allowed_units` jsonb with unknown ids dropped. Null for a legacy or
/// unsynced row; pickers then derive `defaultAllowedUnitSet`.
@override List<Unit>? get allowedUnits {
  final value = _allowedUnits;
  if (value == null) return null;
  if (_allowedUnits is EqualUnmodifiableListView) return _allowedUnits;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

/// What one of this ingredient weighs, in the row's basis unit (ADR-0015).
/// It unlocks `piece` as density unlocks the volume units. Null means
/// `piece` is not sayable; a piece-default row with a null is named on the
/// form and refused at Save.
@override final  double? pieceBasisAmount;
/// Where [pieceBasisAmount] came from: `manual`, `borrowed from <label>`
/// for a seeded copy of a curated size, or `seed:typical`. Shown, never
/// interpreted. Null when there is no weight.
@override final  String? pieceSource;
/// Distinct live measure labels, for the picker row's "N measures" hint.
/// Populated by list reads; 0 otherwise.
@override@JsonKey() final  int measureCount;
/// The row's provenance stamp: `seed`, `manual`, `import_stub`,
/// `usda_fdc:<fdc_id>`, `off:<barcode>`, [labelPhotoSource], or
/// [usdaDeclinedSource]. Shown, never treated as truth; a
/// machine-supplied one still waits for a human confirm. Null when the
/// caller did not select it.
@override final  String? source;
/// The food the row was filled from, named: `usda_food.description` for a
/// pick, the pack's brand and product for a scan. Lets every surface say
/// which food filled the row, offline. Survives a decline. Null when
/// nothing filled the row, and null on a photographed label, which names
/// no food — the person had already named the row.
@override final  String? sourceLabel;
/// How much of the query the matched USDA description covered, 0..1 (the
/// idf-weighted coverage `probe_usda` returns). Stored so `UsdaMatchFit`
/// reads the same offline. Shown, never acted on. Null on a barcode row;
/// cleared by a decline.
@override final  double? sourceScore;
/// Whether a human has overridden the macros, macros basis or density a
/// lookup filled in, on a row whose [source] is a lookup stamp. Renames,
/// unit toggles, measures and aliases never set it. A fresh pick clears it.
@override@JsonKey() final  bool sourceEdited;

/// Create a copy of Ingredient
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IngredientCopyWith<_Ingredient> get copyWith => __$IngredientCopyWithImpl<_Ingredient>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Ingredient&&(identical(other.id, id) || other.id == id)&&(identical(other.canonicalName, canonicalName) || other.canonicalName == canonicalName)&&(identical(other.defaultUnit, defaultUnit) || other.defaultUnit == defaultUnit)&&(identical(other.status, status) || other.status == status)&&(identical(other.category, category) || other.category == category)&&(identical(other.densityGPerMl, densityGPerMl) || other.densityGPerMl == densityGPerMl)&&(identical(other.densitySaid, densitySaid) || other.densitySaid == densitySaid)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.macrosBasis, macrosBasis) || other.macrosBasis == macrosBasis)&&const DeepCollectionEquality().equals(other._allowedUnits, _allowedUnits)&&(identical(other.pieceBasisAmount, pieceBasisAmount) || other.pieceBasisAmount == pieceBasisAmount)&&(identical(other.pieceSource, pieceSource) || other.pieceSource == pieceSource)&&(identical(other.measureCount, measureCount) || other.measureCount == measureCount)&&(identical(other.source, source) || other.source == source)&&(identical(other.sourceLabel, sourceLabel) || other.sourceLabel == sourceLabel)&&(identical(other.sourceScore, sourceScore) || other.sourceScore == sourceScore)&&(identical(other.sourceEdited, sourceEdited) || other.sourceEdited == sourceEdited));
}


@override
int get hashCode => Object.hash(runtimeType,id,canonicalName,defaultUnit,status,category,densityGPerMl,densitySaid,macros,macrosBasis,const DeepCollectionEquality().hash(_allowedUnits),pieceBasisAmount,pieceSource,measureCount,source,sourceLabel,sourceScore,sourceEdited);

@override
String toString() {
  return 'Ingredient(id: $id, canonicalName: $canonicalName, defaultUnit: $defaultUnit, status: $status, category: $category, densityGPerMl: $densityGPerMl, densitySaid: $densitySaid, macros: $macros, macrosBasis: $macrosBasis, allowedUnits: $allowedUnits, pieceBasisAmount: $pieceBasisAmount, pieceSource: $pieceSource, measureCount: $measureCount, source: $source, sourceLabel: $sourceLabel, sourceScore: $sourceScore, sourceEdited: $sourceEdited)';
}


}

/// @nodoc
abstract mixin class _$IngredientCopyWith<$Res> implements $IngredientCopyWith<$Res> {
  factory _$IngredientCopyWith(_Ingredient value, $Res Function(_Ingredient) _then) = __$IngredientCopyWithImpl;
@override @useResult
$Res call({
 String id, String canonicalName, Unit defaultUnit, IngredientStatus status, String? category, double? densityGPerMl, DensitySaid? densitySaid, Macros? macros, MacrosBasis macrosBasis, List<Unit>? allowedUnits, double? pieceBasisAmount, String? pieceSource, int measureCount, String? source, String? sourceLabel, double? sourceScore, bool sourceEdited
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? canonicalName = null,Object? defaultUnit = null,Object? status = null,Object? category = freezed,Object? densityGPerMl = freezed,Object? densitySaid = freezed,Object? macros = freezed,Object? macrosBasis = null,Object? allowedUnits = freezed,Object? pieceBasisAmount = freezed,Object? pieceSource = freezed,Object? measureCount = null,Object? source = freezed,Object? sourceLabel = freezed,Object? sourceScore = freezed,Object? sourceEdited = null,}) {
  return _then(_Ingredient(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,canonicalName: null == canonicalName ? _self.canonicalName : canonicalName // ignore: cast_nullable_to_non_nullable
as String,defaultUnit: null == defaultUnit ? _self.defaultUnit : defaultUnit // ignore: cast_nullable_to_non_nullable
as Unit,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as IngredientStatus,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,densityGPerMl: freezed == densityGPerMl ? _self.densityGPerMl : densityGPerMl // ignore: cast_nullable_to_non_nullable
as double?,densitySaid: freezed == densitySaid ? _self.densitySaid : densitySaid // ignore: cast_nullable_to_non_nullable
as DensitySaid?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as Macros?,macrosBasis: null == macrosBasis ? _self.macrosBasis : macrosBasis // ignore: cast_nullable_to_non_nullable
as MacrosBasis,allowedUnits: freezed == allowedUnits ? _self._allowedUnits : allowedUnits // ignore: cast_nullable_to_non_nullable
as List<Unit>?,pieceBasisAmount: freezed == pieceBasisAmount ? _self.pieceBasisAmount : pieceBasisAmount // ignore: cast_nullable_to_non_nullable
as double?,pieceSource: freezed == pieceSource ? _self.pieceSource : pieceSource // ignore: cast_nullable_to_non_nullable
as String?,measureCount: null == measureCount ? _self.measureCount : measureCount // ignore: cast_nullable_to_non_nullable
as int,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,sourceLabel: freezed == sourceLabel ? _self.sourceLabel : sourceLabel // ignore: cast_nullable_to_non_nullable
as String?,sourceScore: freezed == sourceScore ? _self.sourceScore : sourceScore // ignore: cast_nullable_to_non_nullable
as double?,sourceEdited: null == sourceEdited ? _self.sourceEdited : sourceEdited // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
