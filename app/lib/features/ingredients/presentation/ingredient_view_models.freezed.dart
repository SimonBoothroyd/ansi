// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ingredient_view_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MacroDraft {

 String get kcal; String get protein; String get carb; String get fat; String get fiber;
/// Create a copy of MacroDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MacroDraftCopyWith<MacroDraft> get copyWith => _$MacroDraftCopyWithImpl<MacroDraft>(this as MacroDraft, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MacroDraft&&(identical(other.kcal, kcal) || other.kcal == kcal)&&(identical(other.protein, protein) || other.protein == protein)&&(identical(other.carb, carb) || other.carb == carb)&&(identical(other.fat, fat) || other.fat == fat)&&(identical(other.fiber, fiber) || other.fiber == fiber));
}


@override
int get hashCode => Object.hash(runtimeType,kcal,protein,carb,fat,fiber);

@override
String toString() {
  return 'MacroDraft(kcal: $kcal, protein: $protein, carb: $carb, fat: $fat, fiber: $fiber)';
}


}

/// @nodoc
abstract mixin class $MacroDraftCopyWith<$Res>  {
  factory $MacroDraftCopyWith(MacroDraft value, $Res Function(MacroDraft) _then) = _$MacroDraftCopyWithImpl;
@useResult
$Res call({
 String kcal, String protein, String carb, String fat, String fiber
});




}
/// @nodoc
class _$MacroDraftCopyWithImpl<$Res>
    implements $MacroDraftCopyWith<$Res> {
  _$MacroDraftCopyWithImpl(this._self, this._then);

  final MacroDraft _self;
  final $Res Function(MacroDraft) _then;

/// Create a copy of MacroDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kcal = null,Object? protein = null,Object? carb = null,Object? fat = null,Object? fiber = null,}) {
  return _then(_self.copyWith(
kcal: null == kcal ? _self.kcal : kcal // ignore: cast_nullable_to_non_nullable
as String,protein: null == protein ? _self.protein : protein // ignore: cast_nullable_to_non_nullable
as String,carb: null == carb ? _self.carb : carb // ignore: cast_nullable_to_non_nullable
as String,fat: null == fat ? _self.fat : fat // ignore: cast_nullable_to_non_nullable
as String,fiber: null == fiber ? _self.fiber : fiber // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [MacroDraft].
extension MacroDraftPatterns on MacroDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MacroDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MacroDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MacroDraft value)  $default,){
final _that = this;
switch (_that) {
case _MacroDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MacroDraft value)?  $default,){
final _that = this;
switch (_that) {
case _MacroDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String kcal,  String protein,  String carb,  String fat,  String fiber)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MacroDraft() when $default != null:
return $default(_that.kcal,_that.protein,_that.carb,_that.fat,_that.fiber);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String kcal,  String protein,  String carb,  String fat,  String fiber)  $default,) {final _that = this;
switch (_that) {
case _MacroDraft():
return $default(_that.kcal,_that.protein,_that.carb,_that.fat,_that.fiber);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String kcal,  String protein,  String carb,  String fat,  String fiber)?  $default,) {final _that = this;
switch (_that) {
case _MacroDraft() when $default != null:
return $default(_that.kcal,_that.protein,_that.carb,_that.fat,_that.fiber);case _:
  return null;

}
}

}

/// @nodoc


class _MacroDraft extends MacroDraft {
  const _MacroDraft({this.kcal = '', this.protein = '', this.carb = '', this.fat = '', this.fiber = ''}): super._();
  

@override@JsonKey() final  String kcal;
@override@JsonKey() final  String protein;
@override@JsonKey() final  String carb;
@override@JsonKey() final  String fat;
@override@JsonKey() final  String fiber;

/// Create a copy of MacroDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MacroDraftCopyWith<_MacroDraft> get copyWith => __$MacroDraftCopyWithImpl<_MacroDraft>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MacroDraft&&(identical(other.kcal, kcal) || other.kcal == kcal)&&(identical(other.protein, protein) || other.protein == protein)&&(identical(other.carb, carb) || other.carb == carb)&&(identical(other.fat, fat) || other.fat == fat)&&(identical(other.fiber, fiber) || other.fiber == fiber));
}


@override
int get hashCode => Object.hash(runtimeType,kcal,protein,carb,fat,fiber);

@override
String toString() {
  return 'MacroDraft(kcal: $kcal, protein: $protein, carb: $carb, fat: $fat, fiber: $fiber)';
}


}

/// @nodoc
abstract mixin class _$MacroDraftCopyWith<$Res> implements $MacroDraftCopyWith<$Res> {
  factory _$MacroDraftCopyWith(_MacroDraft value, $Res Function(_MacroDraft) _then) = __$MacroDraftCopyWithImpl;
@override @useResult
$Res call({
 String kcal, String protein, String carb, String fat, String fiber
});




}
/// @nodoc
class __$MacroDraftCopyWithImpl<$Res>
    implements _$MacroDraftCopyWith<$Res> {
  __$MacroDraftCopyWithImpl(this._self, this._then);

  final _MacroDraft _self;
  final $Res Function(_MacroDraft) _then;

/// Create a copy of MacroDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kcal = null,Object? protein = null,Object? carb = null,Object? fat = null,Object? fiber = null,}) {
  return _then(_MacroDraft(
kcal: null == kcal ? _self.kcal : kcal // ignore: cast_nullable_to_non_nullable
as String,protein: null == protein ? _self.protein : protein // ignore: cast_nullable_to_non_nullable
as String,carb: null == carb ? _self.carb : carb // ignore: cast_nullable_to_non_nullable
as String,fat: null == fat ? _self.fat : fat // ignore: cast_nullable_to_non_nullable
as String,fiber: null == fiber ? _self.fiber : fiber // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$IngredientFormDraft {

 Ingredient get row; bool get creating; String get name; String get category; Unit get defaultUnit; MacrosBasis get basis; Set<Unit> get allowed; MacroDraft get macros;/// What the row last handed the macro draft. "Untouched" is defined against
/// this rather than against blankness, so a row that arrives with numbers
/// is as re-seedable as an empty one.
 MacroDraft get seededMacros;/// Bumped on every re-seed, and used as the macro fields' key: `initial`
/// seeds a controller once, so new text needs a new field to seed it into.
 int get macroSeed;/// Bumped whenever the name moved by something other than typing — a scan,
/// or a tidy. The name field pushes the new text into the controller it
/// already has rather than being replaced around a fresh one, because
/// replacing a *focused* field is what a Save tapped straight from the
/// keyboard would do.
 int get nameSeed; int get servingSeed;/// The macros section's per-serving mode: the four fields then hold the
/// label's figures AS PRINTED and the serving row says what they describe,
/// and what is stored is still per 100 of the basis.
 bool get perServing;/// The serving the row's label prints — typed in per-serving mode, or
/// carried by a scan whose per-100 panel named one. Independent of
/// [perServing]: a per-100 label that says "80 kcal per 28 g" states a
/// serving without the row ever being entered in it, and Save keeps it as
/// the row's one `serving` measure either way.
 ServingDraft get serving;/// The per-100 figures the fields held before per-serving mode cleared
/// them, so leaving the mode without typing anything puts the row back
/// exactly as it was found. On a scan of a label that printed BOTH
/// columns it is the pack's own per-100 column, which is the same fact
/// said by the same pack.
 MacroDraft? get per100Macros; DensityChange get density;/// The piece weight as the form holds it — the count-side twin of
/// [density], and drafted the same way (ADR-0015).
 PieceWeightChange get pieceWeight; List<Measure> get measuresAdded; Set<String> get measuresRemoved; List<IngredientAlias> get aliasesAdded; Set<String> get aliasesRemoved;/// A provenance the scan or the USDA pick stamped and the next Save writes
/// — held with the macros it explains rather than written on its own, so
/// backing out of the form leaves the row exactly as it was found.
 String? get pendingSource; String? get pendingSourceLabel; double? get pendingSourceScore;/// The last barcode scan: the draft the card shows, what [applyDraft]
/// decided about it, and whether its pack offer was taken.
 IngredientDraft? get scanned; DraftApplication? get scanApplied; bool get packAdded;/// Set when the measures editor refused a volume-named label and handed
/// back the resolved spoon — the density entry pre-picks it.
 Unit? get redirectedSpoon;/// The name as it was typed, when [IngredientForm.tidyName] replaced a
/// WORD in it — what the `was “…”` line under the field prints, and what
/// *keep the old word* puts back. Null when nothing was suggested.
 String? get nameWas;/// The live row this name would land on top of — the household's names and
/// aliases are one namespace, and a second **Sauerkraut** makes every
/// exact match after it a coin toss. Set when the name field is left (and
/// again if the write itself refuses), cleared by the next keystroke.
 NameEntry? get nameCollision;/// Rows whose name or alias this one was very nearly spelled — at most
/// three, offered under the pickers' `DID YOU MEAN` band and never acted
/// on unattended. Empty whenever something WAS spelled right, which is the
/// same band rule the pickers hold.
 List<NameEntry> get nameNearMatches;/// A typed name the person chose to KEEP. While [name] is exactly this,
/// the tidy recases and respaces but suggests nothing: a suggestion once
/// refused must not be offered again on the next leave. Cleared by the
/// next edit, and carried forward when the tidy's own recasing moves it.
 String? get namePinned;/// Whether a person has typed in the name field during this sitting.
///
/// Save tidies only what somebody wrote. A stored name is not rewritten by
/// a Save that was about the macros — the row's own name is a thing a
/// human already chose, and a save of something else is no occasion to
/// take it away.
 bool get nameEdited;/// The form's one feedback line.
 String? get message;/// True while a write is in flight — every door greys rather than
/// accepting a tap it will drop.
 bool get busy;
/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IngredientFormDraftCopyWith<IngredientFormDraft> get copyWith => _$IngredientFormDraftCopyWithImpl<IngredientFormDraft>(this as IngredientFormDraft, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IngredientFormDraft&&(identical(other.row, row) || other.row == row)&&(identical(other.creating, creating) || other.creating == creating)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.defaultUnit, defaultUnit) || other.defaultUnit == defaultUnit)&&(identical(other.basis, basis) || other.basis == basis)&&const DeepCollectionEquality().equals(other.allowed, allowed)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.seededMacros, seededMacros) || other.seededMacros == seededMacros)&&(identical(other.macroSeed, macroSeed) || other.macroSeed == macroSeed)&&(identical(other.nameSeed, nameSeed) || other.nameSeed == nameSeed)&&(identical(other.servingSeed, servingSeed) || other.servingSeed == servingSeed)&&(identical(other.perServing, perServing) || other.perServing == perServing)&&(identical(other.serving, serving) || other.serving == serving)&&(identical(other.per100Macros, per100Macros) || other.per100Macros == per100Macros)&&(identical(other.density, density) || other.density == density)&&(identical(other.pieceWeight, pieceWeight) || other.pieceWeight == pieceWeight)&&const DeepCollectionEquality().equals(other.measuresAdded, measuresAdded)&&const DeepCollectionEquality().equals(other.measuresRemoved, measuresRemoved)&&const DeepCollectionEquality().equals(other.aliasesAdded, aliasesAdded)&&const DeepCollectionEquality().equals(other.aliasesRemoved, aliasesRemoved)&&(identical(other.pendingSource, pendingSource) || other.pendingSource == pendingSource)&&(identical(other.pendingSourceLabel, pendingSourceLabel) || other.pendingSourceLabel == pendingSourceLabel)&&(identical(other.pendingSourceScore, pendingSourceScore) || other.pendingSourceScore == pendingSourceScore)&&(identical(other.scanned, scanned) || other.scanned == scanned)&&(identical(other.scanApplied, scanApplied) || other.scanApplied == scanApplied)&&(identical(other.packAdded, packAdded) || other.packAdded == packAdded)&&(identical(other.redirectedSpoon, redirectedSpoon) || other.redirectedSpoon == redirectedSpoon)&&(identical(other.nameWas, nameWas) || other.nameWas == nameWas)&&(identical(other.nameCollision, nameCollision) || other.nameCollision == nameCollision)&&const DeepCollectionEquality().equals(other.nameNearMatches, nameNearMatches)&&(identical(other.namePinned, namePinned) || other.namePinned == namePinned)&&(identical(other.nameEdited, nameEdited) || other.nameEdited == nameEdited)&&(identical(other.message, message) || other.message == message)&&(identical(other.busy, busy) || other.busy == busy));
}


@override
int get hashCode => Object.hashAll([runtimeType,row,creating,name,category,defaultUnit,basis,const DeepCollectionEquality().hash(allowed),macros,seededMacros,macroSeed,nameSeed,servingSeed,perServing,serving,per100Macros,density,pieceWeight,const DeepCollectionEquality().hash(measuresAdded),const DeepCollectionEquality().hash(measuresRemoved),const DeepCollectionEquality().hash(aliasesAdded),const DeepCollectionEquality().hash(aliasesRemoved),pendingSource,pendingSourceLabel,pendingSourceScore,scanned,scanApplied,packAdded,redirectedSpoon,nameWas,nameCollision,const DeepCollectionEquality().hash(nameNearMatches),namePinned,nameEdited,message,busy]);

@override
String toString() {
  return 'IngredientFormDraft(row: $row, creating: $creating, name: $name, category: $category, defaultUnit: $defaultUnit, basis: $basis, allowed: $allowed, macros: $macros, seededMacros: $seededMacros, macroSeed: $macroSeed, nameSeed: $nameSeed, servingSeed: $servingSeed, perServing: $perServing, serving: $serving, per100Macros: $per100Macros, density: $density, pieceWeight: $pieceWeight, measuresAdded: $measuresAdded, measuresRemoved: $measuresRemoved, aliasesAdded: $aliasesAdded, aliasesRemoved: $aliasesRemoved, pendingSource: $pendingSource, pendingSourceLabel: $pendingSourceLabel, pendingSourceScore: $pendingSourceScore, scanned: $scanned, scanApplied: $scanApplied, packAdded: $packAdded, redirectedSpoon: $redirectedSpoon, nameWas: $nameWas, nameCollision: $nameCollision, nameNearMatches: $nameNearMatches, namePinned: $namePinned, nameEdited: $nameEdited, message: $message, busy: $busy)';
}


}

/// @nodoc
abstract mixin class $IngredientFormDraftCopyWith<$Res>  {
  factory $IngredientFormDraftCopyWith(IngredientFormDraft value, $Res Function(IngredientFormDraft) _then) = _$IngredientFormDraftCopyWithImpl;
@useResult
$Res call({
 Ingredient row, bool creating, String name, String category, Unit defaultUnit, MacrosBasis basis, Set<Unit> allowed, MacroDraft macros, MacroDraft seededMacros, int macroSeed, int nameSeed, int servingSeed, bool perServing, ServingDraft serving, MacroDraft? per100Macros, DensityChange density, PieceWeightChange pieceWeight, List<Measure> measuresAdded, Set<String> measuresRemoved, List<IngredientAlias> aliasesAdded, Set<String> aliasesRemoved, String? pendingSource, String? pendingSourceLabel, double? pendingSourceScore, IngredientDraft? scanned, DraftApplication? scanApplied, bool packAdded, Unit? redirectedSpoon, String? nameWas, NameEntry? nameCollision, List<NameEntry> nameNearMatches, String? namePinned, bool nameEdited, String? message, bool busy
});


$IngredientCopyWith<$Res> get row;$MacroDraftCopyWith<$Res> get macros;$MacroDraftCopyWith<$Res> get seededMacros;$MacroDraftCopyWith<$Res>? get per100Macros;

}
/// @nodoc
class _$IngredientFormDraftCopyWithImpl<$Res>
    implements $IngredientFormDraftCopyWith<$Res> {
  _$IngredientFormDraftCopyWithImpl(this._self, this._then);

  final IngredientFormDraft _self;
  final $Res Function(IngredientFormDraft) _then;

/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? row = null,Object? creating = null,Object? name = null,Object? category = null,Object? defaultUnit = null,Object? basis = null,Object? allowed = null,Object? macros = null,Object? seededMacros = null,Object? macroSeed = null,Object? nameSeed = null,Object? servingSeed = null,Object? perServing = null,Object? serving = null,Object? per100Macros = freezed,Object? density = null,Object? pieceWeight = null,Object? measuresAdded = null,Object? measuresRemoved = null,Object? aliasesAdded = null,Object? aliasesRemoved = null,Object? pendingSource = freezed,Object? pendingSourceLabel = freezed,Object? pendingSourceScore = freezed,Object? scanned = freezed,Object? scanApplied = freezed,Object? packAdded = null,Object? redirectedSpoon = freezed,Object? nameWas = freezed,Object? nameCollision = freezed,Object? nameNearMatches = null,Object? namePinned = freezed,Object? nameEdited = null,Object? message = freezed,Object? busy = null,}) {
  return _then(_self.copyWith(
row: null == row ? _self.row : row // ignore: cast_nullable_to_non_nullable
as Ingredient,creating: null == creating ? _self.creating : creating // ignore: cast_nullable_to_non_nullable
as bool,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,defaultUnit: null == defaultUnit ? _self.defaultUnit : defaultUnit // ignore: cast_nullable_to_non_nullable
as Unit,basis: null == basis ? _self.basis : basis // ignore: cast_nullable_to_non_nullable
as MacrosBasis,allowed: null == allowed ? _self.allowed : allowed // ignore: cast_nullable_to_non_nullable
as Set<Unit>,macros: null == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as MacroDraft,seededMacros: null == seededMacros ? _self.seededMacros : seededMacros // ignore: cast_nullable_to_non_nullable
as MacroDraft,macroSeed: null == macroSeed ? _self.macroSeed : macroSeed // ignore: cast_nullable_to_non_nullable
as int,nameSeed: null == nameSeed ? _self.nameSeed : nameSeed // ignore: cast_nullable_to_non_nullable
as int,servingSeed: null == servingSeed ? _self.servingSeed : servingSeed // ignore: cast_nullable_to_non_nullable
as int,perServing: null == perServing ? _self.perServing : perServing // ignore: cast_nullable_to_non_nullable
as bool,serving: null == serving ? _self.serving : serving // ignore: cast_nullable_to_non_nullable
as ServingDraft,per100Macros: freezed == per100Macros ? _self.per100Macros : per100Macros // ignore: cast_nullable_to_non_nullable
as MacroDraft?,density: null == density ? _self.density : density // ignore: cast_nullable_to_non_nullable
as DensityChange,pieceWeight: null == pieceWeight ? _self.pieceWeight : pieceWeight // ignore: cast_nullable_to_non_nullable
as PieceWeightChange,measuresAdded: null == measuresAdded ? _self.measuresAdded : measuresAdded // ignore: cast_nullable_to_non_nullable
as List<Measure>,measuresRemoved: null == measuresRemoved ? _self.measuresRemoved : measuresRemoved // ignore: cast_nullable_to_non_nullable
as Set<String>,aliasesAdded: null == aliasesAdded ? _self.aliasesAdded : aliasesAdded // ignore: cast_nullable_to_non_nullable
as List<IngredientAlias>,aliasesRemoved: null == aliasesRemoved ? _self.aliasesRemoved : aliasesRemoved // ignore: cast_nullable_to_non_nullable
as Set<String>,pendingSource: freezed == pendingSource ? _self.pendingSource : pendingSource // ignore: cast_nullable_to_non_nullable
as String?,pendingSourceLabel: freezed == pendingSourceLabel ? _self.pendingSourceLabel : pendingSourceLabel // ignore: cast_nullable_to_non_nullable
as String?,pendingSourceScore: freezed == pendingSourceScore ? _self.pendingSourceScore : pendingSourceScore // ignore: cast_nullable_to_non_nullable
as double?,scanned: freezed == scanned ? _self.scanned : scanned // ignore: cast_nullable_to_non_nullable
as IngredientDraft?,scanApplied: freezed == scanApplied ? _self.scanApplied : scanApplied // ignore: cast_nullable_to_non_nullable
as DraftApplication?,packAdded: null == packAdded ? _self.packAdded : packAdded // ignore: cast_nullable_to_non_nullable
as bool,redirectedSpoon: freezed == redirectedSpoon ? _self.redirectedSpoon : redirectedSpoon // ignore: cast_nullable_to_non_nullable
as Unit?,nameWas: freezed == nameWas ? _self.nameWas : nameWas // ignore: cast_nullable_to_non_nullable
as String?,nameCollision: freezed == nameCollision ? _self.nameCollision : nameCollision // ignore: cast_nullable_to_non_nullable
as NameEntry?,nameNearMatches: null == nameNearMatches ? _self.nameNearMatches : nameNearMatches // ignore: cast_nullable_to_non_nullable
as List<NameEntry>,namePinned: freezed == namePinned ? _self.namePinned : namePinned // ignore: cast_nullable_to_non_nullable
as String?,nameEdited: null == nameEdited ? _self.nameEdited : nameEdited // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$IngredientCopyWith<$Res> get row {
  
  return $IngredientCopyWith<$Res>(_self.row, (value) {
    return _then(_self.copyWith(row: value));
  });
}/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MacroDraftCopyWith<$Res> get macros {
  
  return $MacroDraftCopyWith<$Res>(_self.macros, (value) {
    return _then(_self.copyWith(macros: value));
  });
}/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MacroDraftCopyWith<$Res> get seededMacros {
  
  return $MacroDraftCopyWith<$Res>(_self.seededMacros, (value) {
    return _then(_self.copyWith(seededMacros: value));
  });
}/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MacroDraftCopyWith<$Res>? get per100Macros {
    if (_self.per100Macros == null) {
    return null;
  }

  return $MacroDraftCopyWith<$Res>(_self.per100Macros!, (value) {
    return _then(_self.copyWith(per100Macros: value));
  });
}
}


/// Adds pattern-matching-related methods to [IngredientFormDraft].
extension IngredientFormDraftPatterns on IngredientFormDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _IngredientFormDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _IngredientFormDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _IngredientFormDraft value)  $default,){
final _that = this;
switch (_that) {
case _IngredientFormDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _IngredientFormDraft value)?  $default,){
final _that = this;
switch (_that) {
case _IngredientFormDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Ingredient row,  bool creating,  String name,  String category,  Unit defaultUnit,  MacrosBasis basis,  Set<Unit> allowed,  MacroDraft macros,  MacroDraft seededMacros,  int macroSeed,  int nameSeed,  int servingSeed,  bool perServing,  ServingDraft serving,  MacroDraft? per100Macros,  DensityChange density,  PieceWeightChange pieceWeight,  List<Measure> measuresAdded,  Set<String> measuresRemoved,  List<IngredientAlias> aliasesAdded,  Set<String> aliasesRemoved,  String? pendingSource,  String? pendingSourceLabel,  double? pendingSourceScore,  IngredientDraft? scanned,  DraftApplication? scanApplied,  bool packAdded,  Unit? redirectedSpoon,  String? nameWas,  NameEntry? nameCollision,  List<NameEntry> nameNearMatches,  String? namePinned,  bool nameEdited,  String? message,  bool busy)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _IngredientFormDraft() when $default != null:
return $default(_that.row,_that.creating,_that.name,_that.category,_that.defaultUnit,_that.basis,_that.allowed,_that.macros,_that.seededMacros,_that.macroSeed,_that.nameSeed,_that.servingSeed,_that.perServing,_that.serving,_that.per100Macros,_that.density,_that.pieceWeight,_that.measuresAdded,_that.measuresRemoved,_that.aliasesAdded,_that.aliasesRemoved,_that.pendingSource,_that.pendingSourceLabel,_that.pendingSourceScore,_that.scanned,_that.scanApplied,_that.packAdded,_that.redirectedSpoon,_that.nameWas,_that.nameCollision,_that.nameNearMatches,_that.namePinned,_that.nameEdited,_that.message,_that.busy);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Ingredient row,  bool creating,  String name,  String category,  Unit defaultUnit,  MacrosBasis basis,  Set<Unit> allowed,  MacroDraft macros,  MacroDraft seededMacros,  int macroSeed,  int nameSeed,  int servingSeed,  bool perServing,  ServingDraft serving,  MacroDraft? per100Macros,  DensityChange density,  PieceWeightChange pieceWeight,  List<Measure> measuresAdded,  Set<String> measuresRemoved,  List<IngredientAlias> aliasesAdded,  Set<String> aliasesRemoved,  String? pendingSource,  String? pendingSourceLabel,  double? pendingSourceScore,  IngredientDraft? scanned,  DraftApplication? scanApplied,  bool packAdded,  Unit? redirectedSpoon,  String? nameWas,  NameEntry? nameCollision,  List<NameEntry> nameNearMatches,  String? namePinned,  bool nameEdited,  String? message,  bool busy)  $default,) {final _that = this;
switch (_that) {
case _IngredientFormDraft():
return $default(_that.row,_that.creating,_that.name,_that.category,_that.defaultUnit,_that.basis,_that.allowed,_that.macros,_that.seededMacros,_that.macroSeed,_that.nameSeed,_that.servingSeed,_that.perServing,_that.serving,_that.per100Macros,_that.density,_that.pieceWeight,_that.measuresAdded,_that.measuresRemoved,_that.aliasesAdded,_that.aliasesRemoved,_that.pendingSource,_that.pendingSourceLabel,_that.pendingSourceScore,_that.scanned,_that.scanApplied,_that.packAdded,_that.redirectedSpoon,_that.nameWas,_that.nameCollision,_that.nameNearMatches,_that.namePinned,_that.nameEdited,_that.message,_that.busy);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Ingredient row,  bool creating,  String name,  String category,  Unit defaultUnit,  MacrosBasis basis,  Set<Unit> allowed,  MacroDraft macros,  MacroDraft seededMacros,  int macroSeed,  int nameSeed,  int servingSeed,  bool perServing,  ServingDraft serving,  MacroDraft? per100Macros,  DensityChange density,  PieceWeightChange pieceWeight,  List<Measure> measuresAdded,  Set<String> measuresRemoved,  List<IngredientAlias> aliasesAdded,  Set<String> aliasesRemoved,  String? pendingSource,  String? pendingSourceLabel,  double? pendingSourceScore,  IngredientDraft? scanned,  DraftApplication? scanApplied,  bool packAdded,  Unit? redirectedSpoon,  String? nameWas,  NameEntry? nameCollision,  List<NameEntry> nameNearMatches,  String? namePinned,  bool nameEdited,  String? message,  bool busy)?  $default,) {final _that = this;
switch (_that) {
case _IngredientFormDraft() when $default != null:
return $default(_that.row,_that.creating,_that.name,_that.category,_that.defaultUnit,_that.basis,_that.allowed,_that.macros,_that.seededMacros,_that.macroSeed,_that.nameSeed,_that.servingSeed,_that.perServing,_that.serving,_that.per100Macros,_that.density,_that.pieceWeight,_that.measuresAdded,_that.measuresRemoved,_that.aliasesAdded,_that.aliasesRemoved,_that.pendingSource,_that.pendingSourceLabel,_that.pendingSourceScore,_that.scanned,_that.scanApplied,_that.packAdded,_that.redirectedSpoon,_that.nameWas,_that.nameCollision,_that.nameNearMatches,_that.namePinned,_that.nameEdited,_that.message,_that.busy);case _:
  return null;

}
}

}

/// @nodoc


class _IngredientFormDraft extends IngredientFormDraft {
  const _IngredientFormDraft({required this.row, required this.creating, required this.name, required this.category, required this.defaultUnit, required this.basis, required final  Set<Unit> allowed, required this.macros, required this.seededMacros, this.macroSeed = 0, this.nameSeed = 0, this.servingSeed = 0, this.perServing = false, this.serving = const ServingDraft(), this.per100Macros, this.density = const DensityUnchanged(), this.pieceWeight = const PieceWeightUnchanged(), final  List<Measure> measuresAdded = const <Measure>[], final  Set<String> measuresRemoved = const <String>{}, final  List<IngredientAlias> aliasesAdded = const <IngredientAlias>[], final  Set<String> aliasesRemoved = const <String>{}, this.pendingSource, this.pendingSourceLabel, this.pendingSourceScore, this.scanned, this.scanApplied, this.packAdded = false, this.redirectedSpoon, this.nameWas, this.nameCollision, final  List<NameEntry> nameNearMatches = const <NameEntry>[], this.namePinned, this.nameEdited = false, this.message, this.busy = false}): _allowed = allowed,_measuresAdded = measuresAdded,_measuresRemoved = measuresRemoved,_aliasesAdded = aliasesAdded,_aliasesRemoved = aliasesRemoved,_nameNearMatches = nameNearMatches,super._();
  

@override final  Ingredient row;
@override final  bool creating;
@override final  String name;
@override final  String category;
@override final  Unit defaultUnit;
@override final  MacrosBasis basis;
 final  Set<Unit> _allowed;
@override Set<Unit> get allowed {
  if (_allowed is EqualUnmodifiableSetView) return _allowed;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_allowed);
}

@override final  MacroDraft macros;
/// What the row last handed the macro draft. "Untouched" is defined against
/// this rather than against blankness, so a row that arrives with numbers
/// is as re-seedable as an empty one.
@override final  MacroDraft seededMacros;
/// Bumped on every re-seed, and used as the macro fields' key: `initial`
/// seeds a controller once, so new text needs a new field to seed it into.
@override@JsonKey() final  int macroSeed;
/// Bumped whenever the name moved by something other than typing — a scan,
/// or a tidy. The name field pushes the new text into the controller it
/// already has rather than being replaced around a fresh one, because
/// replacing a *focused* field is what a Save tapped straight from the
/// keyboard would do.
@override@JsonKey() final  int nameSeed;
@override@JsonKey() final  int servingSeed;
/// The macros section's per-serving mode: the four fields then hold the
/// label's figures AS PRINTED and the serving row says what they describe,
/// and what is stored is still per 100 of the basis.
@override@JsonKey() final  bool perServing;
/// The serving the row's label prints — typed in per-serving mode, or
/// carried by a scan whose per-100 panel named one. Independent of
/// [perServing]: a per-100 label that says "80 kcal per 28 g" states a
/// serving without the row ever being entered in it, and Save keeps it as
/// the row's one `serving` measure either way.
@override@JsonKey() final  ServingDraft serving;
/// The per-100 figures the fields held before per-serving mode cleared
/// them, so leaving the mode without typing anything puts the row back
/// exactly as it was found. On a scan of a label that printed BOTH
/// columns it is the pack's own per-100 column, which is the same fact
/// said by the same pack.
@override final  MacroDraft? per100Macros;
@override@JsonKey() final  DensityChange density;
/// The piece weight as the form holds it — the count-side twin of
/// [density], and drafted the same way (ADR-0015).
@override@JsonKey() final  PieceWeightChange pieceWeight;
 final  List<Measure> _measuresAdded;
@override@JsonKey() List<Measure> get measuresAdded {
  if (_measuresAdded is EqualUnmodifiableListView) return _measuresAdded;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_measuresAdded);
}

 final  Set<String> _measuresRemoved;
@override@JsonKey() Set<String> get measuresRemoved {
  if (_measuresRemoved is EqualUnmodifiableSetView) return _measuresRemoved;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_measuresRemoved);
}

 final  List<IngredientAlias> _aliasesAdded;
@override@JsonKey() List<IngredientAlias> get aliasesAdded {
  if (_aliasesAdded is EqualUnmodifiableListView) return _aliasesAdded;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_aliasesAdded);
}

 final  Set<String> _aliasesRemoved;
@override@JsonKey() Set<String> get aliasesRemoved {
  if (_aliasesRemoved is EqualUnmodifiableSetView) return _aliasesRemoved;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_aliasesRemoved);
}

/// A provenance the scan or the USDA pick stamped and the next Save writes
/// — held with the macros it explains rather than written on its own, so
/// backing out of the form leaves the row exactly as it was found.
@override final  String? pendingSource;
@override final  String? pendingSourceLabel;
@override final  double? pendingSourceScore;
/// The last barcode scan: the draft the card shows, what [applyDraft]
/// decided about it, and whether its pack offer was taken.
@override final  IngredientDraft? scanned;
@override final  DraftApplication? scanApplied;
@override@JsonKey() final  bool packAdded;
/// Set when the measures editor refused a volume-named label and handed
/// back the resolved spoon — the density entry pre-picks it.
@override final  Unit? redirectedSpoon;
/// The name as it was typed, when [IngredientForm.tidyName] replaced a
/// WORD in it — what the `was “…”` line under the field prints, and what
/// *keep the old word* puts back. Null when nothing was suggested.
@override final  String? nameWas;
/// The live row this name would land on top of — the household's names and
/// aliases are one namespace, and a second **Sauerkraut** makes every
/// exact match after it a coin toss. Set when the name field is left (and
/// again if the write itself refuses), cleared by the next keystroke.
@override final  NameEntry? nameCollision;
/// Rows whose name or alias this one was very nearly spelled — at most
/// three, offered under the pickers' `DID YOU MEAN` band and never acted
/// on unattended. Empty whenever something WAS spelled right, which is the
/// same band rule the pickers hold.
 final  List<NameEntry> _nameNearMatches;
/// Rows whose name or alias this one was very nearly spelled — at most
/// three, offered under the pickers' `DID YOU MEAN` band and never acted
/// on unattended. Empty whenever something WAS spelled right, which is the
/// same band rule the pickers hold.
@override@JsonKey() List<NameEntry> get nameNearMatches {
  if (_nameNearMatches is EqualUnmodifiableListView) return _nameNearMatches;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_nameNearMatches);
}

/// A typed name the person chose to KEEP. While [name] is exactly this,
/// the tidy recases and respaces but suggests nothing: a suggestion once
/// refused must not be offered again on the next leave. Cleared by the
/// next edit, and carried forward when the tidy's own recasing moves it.
@override final  String? namePinned;
/// Whether a person has typed in the name field during this sitting.
///
/// Save tidies only what somebody wrote. A stored name is not rewritten by
/// a Save that was about the macros — the row's own name is a thing a
/// human already chose, and a save of something else is no occasion to
/// take it away.
@override@JsonKey() final  bool nameEdited;
/// The form's one feedback line.
@override final  String? message;
/// True while a write is in flight — every door greys rather than
/// accepting a tap it will drop.
@override@JsonKey() final  bool busy;

/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IngredientFormDraftCopyWith<_IngredientFormDraft> get copyWith => __$IngredientFormDraftCopyWithImpl<_IngredientFormDraft>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _IngredientFormDraft&&(identical(other.row, row) || other.row == row)&&(identical(other.creating, creating) || other.creating == creating)&&(identical(other.name, name) || other.name == name)&&(identical(other.category, category) || other.category == category)&&(identical(other.defaultUnit, defaultUnit) || other.defaultUnit == defaultUnit)&&(identical(other.basis, basis) || other.basis == basis)&&const DeepCollectionEquality().equals(other._allowed, _allowed)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.seededMacros, seededMacros) || other.seededMacros == seededMacros)&&(identical(other.macroSeed, macroSeed) || other.macroSeed == macroSeed)&&(identical(other.nameSeed, nameSeed) || other.nameSeed == nameSeed)&&(identical(other.servingSeed, servingSeed) || other.servingSeed == servingSeed)&&(identical(other.perServing, perServing) || other.perServing == perServing)&&(identical(other.serving, serving) || other.serving == serving)&&(identical(other.per100Macros, per100Macros) || other.per100Macros == per100Macros)&&(identical(other.density, density) || other.density == density)&&(identical(other.pieceWeight, pieceWeight) || other.pieceWeight == pieceWeight)&&const DeepCollectionEquality().equals(other._measuresAdded, _measuresAdded)&&const DeepCollectionEquality().equals(other._measuresRemoved, _measuresRemoved)&&const DeepCollectionEquality().equals(other._aliasesAdded, _aliasesAdded)&&const DeepCollectionEquality().equals(other._aliasesRemoved, _aliasesRemoved)&&(identical(other.pendingSource, pendingSource) || other.pendingSource == pendingSource)&&(identical(other.pendingSourceLabel, pendingSourceLabel) || other.pendingSourceLabel == pendingSourceLabel)&&(identical(other.pendingSourceScore, pendingSourceScore) || other.pendingSourceScore == pendingSourceScore)&&(identical(other.scanned, scanned) || other.scanned == scanned)&&(identical(other.scanApplied, scanApplied) || other.scanApplied == scanApplied)&&(identical(other.packAdded, packAdded) || other.packAdded == packAdded)&&(identical(other.redirectedSpoon, redirectedSpoon) || other.redirectedSpoon == redirectedSpoon)&&(identical(other.nameWas, nameWas) || other.nameWas == nameWas)&&(identical(other.nameCollision, nameCollision) || other.nameCollision == nameCollision)&&const DeepCollectionEquality().equals(other._nameNearMatches, _nameNearMatches)&&(identical(other.namePinned, namePinned) || other.namePinned == namePinned)&&(identical(other.nameEdited, nameEdited) || other.nameEdited == nameEdited)&&(identical(other.message, message) || other.message == message)&&(identical(other.busy, busy) || other.busy == busy));
}


@override
int get hashCode => Object.hashAll([runtimeType,row,creating,name,category,defaultUnit,basis,const DeepCollectionEquality().hash(_allowed),macros,seededMacros,macroSeed,nameSeed,servingSeed,perServing,serving,per100Macros,density,pieceWeight,const DeepCollectionEquality().hash(_measuresAdded),const DeepCollectionEquality().hash(_measuresRemoved),const DeepCollectionEquality().hash(_aliasesAdded),const DeepCollectionEquality().hash(_aliasesRemoved),pendingSource,pendingSourceLabel,pendingSourceScore,scanned,scanApplied,packAdded,redirectedSpoon,nameWas,nameCollision,const DeepCollectionEquality().hash(_nameNearMatches),namePinned,nameEdited,message,busy]);

@override
String toString() {
  return 'IngredientFormDraft(row: $row, creating: $creating, name: $name, category: $category, defaultUnit: $defaultUnit, basis: $basis, allowed: $allowed, macros: $macros, seededMacros: $seededMacros, macroSeed: $macroSeed, nameSeed: $nameSeed, servingSeed: $servingSeed, perServing: $perServing, serving: $serving, per100Macros: $per100Macros, density: $density, pieceWeight: $pieceWeight, measuresAdded: $measuresAdded, measuresRemoved: $measuresRemoved, aliasesAdded: $aliasesAdded, aliasesRemoved: $aliasesRemoved, pendingSource: $pendingSource, pendingSourceLabel: $pendingSourceLabel, pendingSourceScore: $pendingSourceScore, scanned: $scanned, scanApplied: $scanApplied, packAdded: $packAdded, redirectedSpoon: $redirectedSpoon, nameWas: $nameWas, nameCollision: $nameCollision, nameNearMatches: $nameNearMatches, namePinned: $namePinned, nameEdited: $nameEdited, message: $message, busy: $busy)';
}


}

/// @nodoc
abstract mixin class _$IngredientFormDraftCopyWith<$Res> implements $IngredientFormDraftCopyWith<$Res> {
  factory _$IngredientFormDraftCopyWith(_IngredientFormDraft value, $Res Function(_IngredientFormDraft) _then) = __$IngredientFormDraftCopyWithImpl;
@override @useResult
$Res call({
 Ingredient row, bool creating, String name, String category, Unit defaultUnit, MacrosBasis basis, Set<Unit> allowed, MacroDraft macros, MacroDraft seededMacros, int macroSeed, int nameSeed, int servingSeed, bool perServing, ServingDraft serving, MacroDraft? per100Macros, DensityChange density, PieceWeightChange pieceWeight, List<Measure> measuresAdded, Set<String> measuresRemoved, List<IngredientAlias> aliasesAdded, Set<String> aliasesRemoved, String? pendingSource, String? pendingSourceLabel, double? pendingSourceScore, IngredientDraft? scanned, DraftApplication? scanApplied, bool packAdded, Unit? redirectedSpoon, String? nameWas, NameEntry? nameCollision, List<NameEntry> nameNearMatches, String? namePinned, bool nameEdited, String? message, bool busy
});


@override $IngredientCopyWith<$Res> get row;@override $MacroDraftCopyWith<$Res> get macros;@override $MacroDraftCopyWith<$Res> get seededMacros;@override $MacroDraftCopyWith<$Res>? get per100Macros;

}
/// @nodoc
class __$IngredientFormDraftCopyWithImpl<$Res>
    implements _$IngredientFormDraftCopyWith<$Res> {
  __$IngredientFormDraftCopyWithImpl(this._self, this._then);

  final _IngredientFormDraft _self;
  final $Res Function(_IngredientFormDraft) _then;

/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? row = null,Object? creating = null,Object? name = null,Object? category = null,Object? defaultUnit = null,Object? basis = null,Object? allowed = null,Object? macros = null,Object? seededMacros = null,Object? macroSeed = null,Object? nameSeed = null,Object? servingSeed = null,Object? perServing = null,Object? serving = null,Object? per100Macros = freezed,Object? density = null,Object? pieceWeight = null,Object? measuresAdded = null,Object? measuresRemoved = null,Object? aliasesAdded = null,Object? aliasesRemoved = null,Object? pendingSource = freezed,Object? pendingSourceLabel = freezed,Object? pendingSourceScore = freezed,Object? scanned = freezed,Object? scanApplied = freezed,Object? packAdded = null,Object? redirectedSpoon = freezed,Object? nameWas = freezed,Object? nameCollision = freezed,Object? nameNearMatches = null,Object? namePinned = freezed,Object? nameEdited = null,Object? message = freezed,Object? busy = null,}) {
  return _then(_IngredientFormDraft(
row: null == row ? _self.row : row // ignore: cast_nullable_to_non_nullable
as Ingredient,creating: null == creating ? _self.creating : creating // ignore: cast_nullable_to_non_nullable
as bool,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,defaultUnit: null == defaultUnit ? _self.defaultUnit : defaultUnit // ignore: cast_nullable_to_non_nullable
as Unit,basis: null == basis ? _self.basis : basis // ignore: cast_nullable_to_non_nullable
as MacrosBasis,allowed: null == allowed ? _self._allowed : allowed // ignore: cast_nullable_to_non_nullable
as Set<Unit>,macros: null == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as MacroDraft,seededMacros: null == seededMacros ? _self.seededMacros : seededMacros // ignore: cast_nullable_to_non_nullable
as MacroDraft,macroSeed: null == macroSeed ? _self.macroSeed : macroSeed // ignore: cast_nullable_to_non_nullable
as int,nameSeed: null == nameSeed ? _self.nameSeed : nameSeed // ignore: cast_nullable_to_non_nullable
as int,servingSeed: null == servingSeed ? _self.servingSeed : servingSeed // ignore: cast_nullable_to_non_nullable
as int,perServing: null == perServing ? _self.perServing : perServing // ignore: cast_nullable_to_non_nullable
as bool,serving: null == serving ? _self.serving : serving // ignore: cast_nullable_to_non_nullable
as ServingDraft,per100Macros: freezed == per100Macros ? _self.per100Macros : per100Macros // ignore: cast_nullable_to_non_nullable
as MacroDraft?,density: null == density ? _self.density : density // ignore: cast_nullable_to_non_nullable
as DensityChange,pieceWeight: null == pieceWeight ? _self.pieceWeight : pieceWeight // ignore: cast_nullable_to_non_nullable
as PieceWeightChange,measuresAdded: null == measuresAdded ? _self._measuresAdded : measuresAdded // ignore: cast_nullable_to_non_nullable
as List<Measure>,measuresRemoved: null == measuresRemoved ? _self._measuresRemoved : measuresRemoved // ignore: cast_nullable_to_non_nullable
as Set<String>,aliasesAdded: null == aliasesAdded ? _self._aliasesAdded : aliasesAdded // ignore: cast_nullable_to_non_nullable
as List<IngredientAlias>,aliasesRemoved: null == aliasesRemoved ? _self._aliasesRemoved : aliasesRemoved // ignore: cast_nullable_to_non_nullable
as Set<String>,pendingSource: freezed == pendingSource ? _self.pendingSource : pendingSource // ignore: cast_nullable_to_non_nullable
as String?,pendingSourceLabel: freezed == pendingSourceLabel ? _self.pendingSourceLabel : pendingSourceLabel // ignore: cast_nullable_to_non_nullable
as String?,pendingSourceScore: freezed == pendingSourceScore ? _self.pendingSourceScore : pendingSourceScore // ignore: cast_nullable_to_non_nullable
as double?,scanned: freezed == scanned ? _self.scanned : scanned // ignore: cast_nullable_to_non_nullable
as IngredientDraft?,scanApplied: freezed == scanApplied ? _self.scanApplied : scanApplied // ignore: cast_nullable_to_non_nullable
as DraftApplication?,packAdded: null == packAdded ? _self.packAdded : packAdded // ignore: cast_nullable_to_non_nullable
as bool,redirectedSpoon: freezed == redirectedSpoon ? _self.redirectedSpoon : redirectedSpoon // ignore: cast_nullable_to_non_nullable
as Unit?,nameWas: freezed == nameWas ? _self.nameWas : nameWas // ignore: cast_nullable_to_non_nullable
as String?,nameCollision: freezed == nameCollision ? _self.nameCollision : nameCollision // ignore: cast_nullable_to_non_nullable
as NameEntry?,nameNearMatches: null == nameNearMatches ? _self._nameNearMatches : nameNearMatches // ignore: cast_nullable_to_non_nullable
as List<NameEntry>,namePinned: freezed == namePinned ? _self.namePinned : namePinned // ignore: cast_nullable_to_non_nullable
as String?,nameEdited: null == nameEdited ? _self.nameEdited : nameEdited // ignore: cast_nullable_to_non_nullable
as bool,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,busy: null == busy ? _self.busy : busy // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$IngredientCopyWith<$Res> get row {
  
  return $IngredientCopyWith<$Res>(_self.row, (value) {
    return _then(_self.copyWith(row: value));
  });
}/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MacroDraftCopyWith<$Res> get macros {
  
  return $MacroDraftCopyWith<$Res>(_self.macros, (value) {
    return _then(_self.copyWith(macros: value));
  });
}/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MacroDraftCopyWith<$Res> get seededMacros {
  
  return $MacroDraftCopyWith<$Res>(_self.seededMacros, (value) {
    return _then(_self.copyWith(seededMacros: value));
  });
}/// Create a copy of IngredientFormDraft
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MacroDraftCopyWith<$Res>? get per100Macros {
    if (_self.per100Macros == null) {
    return null;
  }

  return $MacroDraftCopyWith<$Res>(_self.per100Macros!, (value) {
    return _then(_self.copyWith(per100Macros: value));
  });
}
}

// dart format on
