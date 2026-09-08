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

 String get id; String get canonicalName; Unit get defaultUnit; IngredientStatus get status; String? get category; double? get densityGPerMl; Macros? get macros; MacrosBasis get macrosBasis;/// The explicit per-ingredient allowed-unit list (ADR-0008, migration
/// 0012) — parsed from the row's `allowed_units` jsonb, unknown ids
/// dropped. Null for a legacy/unsynced row: the pickers then fall back
/// to deriving the same ADR defaults (`defaultAllowedUnitSet`).
 List<Unit>? get allowedUnits;/// What ONE of this ingredient weighs, in the row's basis unit — the
/// **piece weight** (ADR-0015, migration 0039). A row fact exactly as the
/// density is: density says what a volume of this weighs and unlocks the
/// volume units; this says what a piece weighs and unlocks `piece`.
///
/// Null means the row has no such fact, and `piece` is then not sayable
/// on it. A piece-default row with a null here is a stranded default (the
/// D4c shape), named on the form and refused at Save — a count nobody
/// weighed is the one honest state this replaces ("needs a weight").
 double? get pieceBasisAmount;/// Where [pieceBasisAmount] came from: `manual` for a typed one,
/// `borrowed from <label>` where the seed copied a curated size ("onion,
/// medium" → 110 g), `seed:typical` for a hand-curated number. Shown, never
/// interpreted. Null when there is no weight, or the row predates it.
 String? get pieceSource;/// Distinct live measure labels this ingredient carries — the picker
/// row's "N measures" capability hint (7.7). Populated by list reads;
/// 0 where a caller didn't ask for it.
 int get measureCount;/// The row's provenance stamp (`seed`, `manual`, `import_stub`,
/// `usda_fdc:<fdc_id>` for a USDA pick, `off:<barcode>` for a scan, or
/// [usdaDeclinedSource] for a person's "not this food"). Shown, never
/// interpreted as truth: it says where the numbers came from, and a
/// machine-supplied one still waits for a human confirm. Null on a row read
/// by a caller that didn't select it.
 String? get source;/// The food the row was filled from, **named** — `usda_food.description`
/// for a pick, the pack's brand and product name for a scan — written
/// beside [source] so every surface can say WHICH food filled the row,
/// offline. It is what the ids in [source] are for a reader: the stamp is a
/// key, this is the answer. Survives a decline, so the form can name the
/// food that was refused. Null on rows filled before the column existed and
/// on rows nothing filled, and null is a real answer — a surface then says
/// nothing rather than inventing a name.
 String? get sourceLabel;/// How much of the query the matched food's description covered, 0..1 —
/// the idf-weighted coverage `probe_usda` returns, not a graded confidence.
/// Stored so `UsdaMatchFit` reads the same offline as it did online. Shown,
/// never acted on. A USDA fact only: a scan matches nothing, so a barcode
/// row carries a [sourceLabel] and no score. Cleared by a decline.
 double? get sourceScore;/// Whether a human has overridden the numbers the lookup filled in
/// (migration 0034) — **macros, macros basis or density**,
/// on a row whose [source] is a lookup stamp.
///
/// It exists because [source] is patch-shaped and survives a form save, so
/// without it a row goes on naming a USDA food whose figures are no longer
/// on it. The fence is what keeps it honest: it means *the numbers are no
/// longer the source's*, so a rename, a unit toggle, a measure or an alias
/// must never set it — none of those contradicts the source. A fresh pick
/// clears it, because the numbers are the new food's.
 bool get sourceEdited;
/// Create a copy of Ingredient
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IngredientCopyWith<Ingredient> get copyWith => _$IngredientCopyWithImpl<Ingredient>(this as Ingredient, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Ingredient&&(identical(other.id, id) || other.id == id)&&(identical(other.canonicalName, canonicalName) || other.canonicalName == canonicalName)&&(identical(other.defaultUnit, defaultUnit) || other.defaultUnit == defaultUnit)&&(identical(other.status, status) || other.status == status)&&(identical(other.category, category) || other.category == category)&&(identical(other.densityGPerMl, densityGPerMl) || other.densityGPerMl == densityGPerMl)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.macrosBasis, macrosBasis) || other.macrosBasis == macrosBasis)&&const DeepCollectionEquality().equals(other.allowedUnits, allowedUnits)&&(identical(other.pieceBasisAmount, pieceBasisAmount) || other.pieceBasisAmount == pieceBasisAmount)&&(identical(other.pieceSource, pieceSource) || other.pieceSource == pieceSource)&&(identical(other.measureCount, measureCount) || other.measureCount == measureCount)&&(identical(other.source, source) || other.source == source)&&(identical(other.sourceLabel, sourceLabel) || other.sourceLabel == sourceLabel)&&(identical(other.sourceScore, sourceScore) || other.sourceScore == sourceScore)&&(identical(other.sourceEdited, sourceEdited) || other.sourceEdited == sourceEdited));
}


@override
int get hashCode => Object.hash(runtimeType,id,canonicalName,defaultUnit,status,category,densityGPerMl,macros,macrosBasis,const DeepCollectionEquality().hash(allowedUnits),pieceBasisAmount,pieceSource,measureCount,source,sourceLabel,sourceScore,sourceEdited);

@override
String toString() {
  return 'Ingredient(id: $id, canonicalName: $canonicalName, defaultUnit: $defaultUnit, status: $status, category: $category, densityGPerMl: $densityGPerMl, macros: $macros, macrosBasis: $macrosBasis, allowedUnits: $allowedUnits, pieceBasisAmount: $pieceBasisAmount, pieceSource: $pieceSource, measureCount: $measureCount, source: $source, sourceLabel: $sourceLabel, sourceScore: $sourceScore, sourceEdited: $sourceEdited)';
}


}

/// @nodoc
abstract mixin class $IngredientCopyWith<$Res>  {
  factory $IngredientCopyWith(Ingredient value, $Res Function(Ingredient) _then) = _$IngredientCopyWithImpl;
@useResult
$Res call({
 String id, String canonicalName, Unit defaultUnit, IngredientStatus status, String? category, double? densityGPerMl, Macros? macros, MacrosBasis macrosBasis, List<Unit>? allowedUnits, double? pieceBasisAmount, String? pieceSource, int measureCount, String? source, String? sourceLabel, double? sourceScore, bool sourceEdited
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? canonicalName = null,Object? defaultUnit = null,Object? status = null,Object? category = freezed,Object? densityGPerMl = freezed,Object? macros = freezed,Object? macrosBasis = null,Object? allowedUnits = freezed,Object? pieceBasisAmount = freezed,Object? pieceSource = freezed,Object? measureCount = null,Object? source = freezed,Object? sourceLabel = freezed,Object? sourceScore = freezed,Object? sourceEdited = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,canonicalName: null == canonicalName ? _self.canonicalName : canonicalName // ignore: cast_nullable_to_non_nullable
as String,defaultUnit: null == defaultUnit ? _self.defaultUnit : defaultUnit // ignore: cast_nullable_to_non_nullable
as Unit,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as IngredientStatus,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,densityGPerMl: freezed == densityGPerMl ? _self.densityGPerMl : densityGPerMl // ignore: cast_nullable_to_non_nullable
as double?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String canonicalName,  Unit defaultUnit,  IngredientStatus status,  String? category,  double? densityGPerMl,  Macros? macros,  MacrosBasis macrosBasis,  List<Unit>? allowedUnits,  double? pieceBasisAmount,  String? pieceSource,  int measureCount,  String? source,  String? sourceLabel,  double? sourceScore,  bool sourceEdited)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Ingredient() when $default != null:
return $default(_that.id,_that.canonicalName,_that.defaultUnit,_that.status,_that.category,_that.densityGPerMl,_that.macros,_that.macrosBasis,_that.allowedUnits,_that.pieceBasisAmount,_that.pieceSource,_that.measureCount,_that.source,_that.sourceLabel,_that.sourceScore,_that.sourceEdited);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String canonicalName,  Unit defaultUnit,  IngredientStatus status,  String? category,  double? densityGPerMl,  Macros? macros,  MacrosBasis macrosBasis,  List<Unit>? allowedUnits,  double? pieceBasisAmount,  String? pieceSource,  int measureCount,  String? source,  String? sourceLabel,  double? sourceScore,  bool sourceEdited)  $default,) {final _that = this;
switch (_that) {
case _Ingredient():
return $default(_that.id,_that.canonicalName,_that.defaultUnit,_that.status,_that.category,_that.densityGPerMl,_that.macros,_that.macrosBasis,_that.allowedUnits,_that.pieceBasisAmount,_that.pieceSource,_that.measureCount,_that.source,_that.sourceLabel,_that.sourceScore,_that.sourceEdited);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String canonicalName,  Unit defaultUnit,  IngredientStatus status,  String? category,  double? densityGPerMl,  Macros? macros,  MacrosBasis macrosBasis,  List<Unit>? allowedUnits,  double? pieceBasisAmount,  String? pieceSource,  int measureCount,  String? source,  String? sourceLabel,  double? sourceScore,  bool sourceEdited)?  $default,) {final _that = this;
switch (_that) {
case _Ingredient() when $default != null:
return $default(_that.id,_that.canonicalName,_that.defaultUnit,_that.status,_that.category,_that.densityGPerMl,_that.macros,_that.macrosBasis,_that.allowedUnits,_that.pieceBasisAmount,_that.pieceSource,_that.measureCount,_that.source,_that.sourceLabel,_that.sourceScore,_that.sourceEdited);case _:
  return null;

}
}

}

/// @nodoc


class _Ingredient implements Ingredient {
  const _Ingredient({required this.id, required this.canonicalName, required this.defaultUnit, required this.status, this.category, this.densityGPerMl, this.macros, this.macrosBasis = MacrosBasis.perG, final  List<Unit>? allowedUnits, this.pieceBasisAmount, this.pieceSource, this.measureCount = 0, this.source, this.sourceLabel, this.sourceScore, this.sourceEdited = false}): _allowedUnits = allowedUnits;
  

@override final  String id;
@override final  String canonicalName;
@override final  Unit defaultUnit;
@override final  IngredientStatus status;
@override final  String? category;
@override final  double? densityGPerMl;
@override final  Macros? macros;
@override@JsonKey() final  MacrosBasis macrosBasis;
/// The explicit per-ingredient allowed-unit list (ADR-0008, migration
/// 0012) — parsed from the row's `allowed_units` jsonb, unknown ids
/// dropped. Null for a legacy/unsynced row: the pickers then fall back
/// to deriving the same ADR defaults (`defaultAllowedUnitSet`).
 final  List<Unit>? _allowedUnits;
/// The explicit per-ingredient allowed-unit list (ADR-0008, migration
/// 0012) — parsed from the row's `allowed_units` jsonb, unknown ids
/// dropped. Null for a legacy/unsynced row: the pickers then fall back
/// to deriving the same ADR defaults (`defaultAllowedUnitSet`).
@override List<Unit>? get allowedUnits {
  final value = _allowedUnits;
  if (value == null) return null;
  if (_allowedUnits is EqualUnmodifiableListView) return _allowedUnits;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

/// What ONE of this ingredient weighs, in the row's basis unit — the
/// **piece weight** (ADR-0015, migration 0039). A row fact exactly as the
/// density is: density says what a volume of this weighs and unlocks the
/// volume units; this says what a piece weighs and unlocks `piece`.
///
/// Null means the row has no such fact, and `piece` is then not sayable
/// on it. A piece-default row with a null here is a stranded default (the
/// D4c shape), named on the form and refused at Save — a count nobody
/// weighed is the one honest state this replaces ("needs a weight").
@override final  double? pieceBasisAmount;
/// Where [pieceBasisAmount] came from: `manual` for a typed one,
/// `borrowed from <label>` where the seed copied a curated size ("onion,
/// medium" → 110 g), `seed:typical` for a hand-curated number. Shown, never
/// interpreted. Null when there is no weight, or the row predates it.
@override final  String? pieceSource;
/// Distinct live measure labels this ingredient carries — the picker
/// row's "N measures" capability hint (7.7). Populated by list reads;
/// 0 where a caller didn't ask for it.
@override@JsonKey() final  int measureCount;
/// The row's provenance stamp (`seed`, `manual`, `import_stub`,
/// `usda_fdc:<fdc_id>` for a USDA pick, `off:<barcode>` for a scan, or
/// [usdaDeclinedSource] for a person's "not this food"). Shown, never
/// interpreted as truth: it says where the numbers came from, and a
/// machine-supplied one still waits for a human confirm. Null on a row read
/// by a caller that didn't select it.
@override final  String? source;
/// The food the row was filled from, **named** — `usda_food.description`
/// for a pick, the pack's brand and product name for a scan — written
/// beside [source] so every surface can say WHICH food filled the row,
/// offline. It is what the ids in [source] are for a reader: the stamp is a
/// key, this is the answer. Survives a decline, so the form can name the
/// food that was refused. Null on rows filled before the column existed and
/// on rows nothing filled, and null is a real answer — a surface then says
/// nothing rather than inventing a name.
@override final  String? sourceLabel;
/// How much of the query the matched food's description covered, 0..1 —
/// the idf-weighted coverage `probe_usda` returns, not a graded confidence.
/// Stored so `UsdaMatchFit` reads the same offline as it did online. Shown,
/// never acted on. A USDA fact only: a scan matches nothing, so a barcode
/// row carries a [sourceLabel] and no score. Cleared by a decline.
@override final  double? sourceScore;
/// Whether a human has overridden the numbers the lookup filled in
/// (migration 0034) — **macros, macros basis or density**,
/// on a row whose [source] is a lookup stamp.
///
/// It exists because [source] is patch-shaped and survives a form save, so
/// without it a row goes on naming a USDA food whose figures are no longer
/// on it. The fence is what keeps it honest: it means *the numbers are no
/// longer the source's*, so a rename, a unit toggle, a measure or an alias
/// must never set it — none of those contradicts the source. A fresh pick
/// clears it, because the numbers are the new food's.
@override@JsonKey() final  bool sourceEdited;

/// Create a copy of Ingredient
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IngredientCopyWith<_Ingredient> get copyWith => __$IngredientCopyWithImpl<_Ingredient>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Ingredient&&(identical(other.id, id) || other.id == id)&&(identical(other.canonicalName, canonicalName) || other.canonicalName == canonicalName)&&(identical(other.defaultUnit, defaultUnit) || other.defaultUnit == defaultUnit)&&(identical(other.status, status) || other.status == status)&&(identical(other.category, category) || other.category == category)&&(identical(other.densityGPerMl, densityGPerMl) || other.densityGPerMl == densityGPerMl)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.macrosBasis, macrosBasis) || other.macrosBasis == macrosBasis)&&const DeepCollectionEquality().equals(other._allowedUnits, _allowedUnits)&&(identical(other.pieceBasisAmount, pieceBasisAmount) || other.pieceBasisAmount == pieceBasisAmount)&&(identical(other.pieceSource, pieceSource) || other.pieceSource == pieceSource)&&(identical(other.measureCount, measureCount) || other.measureCount == measureCount)&&(identical(other.source, source) || other.source == source)&&(identical(other.sourceLabel, sourceLabel) || other.sourceLabel == sourceLabel)&&(identical(other.sourceScore, sourceScore) || other.sourceScore == sourceScore)&&(identical(other.sourceEdited, sourceEdited) || other.sourceEdited == sourceEdited));
}


@override
int get hashCode => Object.hash(runtimeType,id,canonicalName,defaultUnit,status,category,densityGPerMl,macros,macrosBasis,const DeepCollectionEquality().hash(_allowedUnits),pieceBasisAmount,pieceSource,measureCount,source,sourceLabel,sourceScore,sourceEdited);

@override
String toString() {
  return 'Ingredient(id: $id, canonicalName: $canonicalName, defaultUnit: $defaultUnit, status: $status, category: $category, densityGPerMl: $densityGPerMl, macros: $macros, macrosBasis: $macrosBasis, allowedUnits: $allowedUnits, pieceBasisAmount: $pieceBasisAmount, pieceSource: $pieceSource, measureCount: $measureCount, source: $source, sourceLabel: $sourceLabel, sourceScore: $sourceScore, sourceEdited: $sourceEdited)';
}


}

/// @nodoc
abstract mixin class _$IngredientCopyWith<$Res> implements $IngredientCopyWith<$Res> {
  factory _$IngredientCopyWith(_Ingredient value, $Res Function(_Ingredient) _then) = __$IngredientCopyWithImpl;
@override @useResult
$Res call({
 String id, String canonicalName, Unit defaultUnit, IngredientStatus status, String? category, double? densityGPerMl, Macros? macros, MacrosBasis macrosBasis, List<Unit>? allowedUnits, double? pieceBasisAmount, String? pieceSource, int measureCount, String? source, String? sourceLabel, double? sourceScore, bool sourceEdited
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? canonicalName = null,Object? defaultUnit = null,Object? status = null,Object? category = freezed,Object? densityGPerMl = freezed,Object? macros = freezed,Object? macrosBasis = null,Object? allowedUnits = freezed,Object? pieceBasisAmount = freezed,Object? pieceSource = freezed,Object? measureCount = null,Object? source = freezed,Object? sourceLabel = freezed,Object? sourceScore = freezed,Object? sourceEdited = null,}) {
  return _then(_Ingredient(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,canonicalName: null == canonicalName ? _self.canonicalName : canonicalName // ignore: cast_nullable_to_non_nullable
as String,defaultUnit: null == defaultUnit ? _self.defaultUnit : defaultUnit // ignore: cast_nullable_to_non_nullable
as Unit,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as IngredientStatus,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,densityGPerMl: freezed == densityGPerMl ? _self.densityGPerMl : densityGPerMl // ignore: cast_nullable_to_non_nullable
as double?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
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
