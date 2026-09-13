// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'shopping.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ShoppingContribution {

 ContributionSource get source;/// The provenance label, e.g. "Curry · cook Mon", "Oat Cookies", or
/// "manual top-up".
 String get label;/// Null for a bare non-food item (renders as a dash).
 double? get quantity; Unit? get unit;/// The measure the quantity is counted in ("2 × potato, large"), when the
/// contribution was quantified in one; [unit] is null then.
 Measure? get measure;/// The persisted `measure_id` of a manual contribution, verbatim — kept
/// even while [measure] is unresolved (row not yet synced / soft-deleted)
/// so the edit sheet's re-save never wipes the FK for every device
/// (mirrors the recipe line's [measureId]). Null for cook lines (derived,
/// never re-saved here).
 String? get measureId;/// The day (0=Mon..6=Sun) a DERIVED contribution belongs to — a session's
/// cook day, or a planned snack's own day — which orders the breakdown.
/// Null for a manual top-up, which belongs to no day.
 int? get cookDay;/// The persisted `shopping_list_contribution` id — set only for a `manual`
/// contribution (a cook one is derived, so it has none). Lets the UI edit
/// or remove this specific top-up.
 String? get contributionId;
/// Create a copy of ShoppingContribution
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingContributionCopyWith<ShoppingContribution> get copyWith => _$ShoppingContributionCopyWithImpl<ShoppingContribution>(this as ShoppingContribution, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingContribution&&(identical(other.source, source) || other.source == source)&&(identical(other.label, label) || other.label == label)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.measure, measure) || other.measure == measure)&&(identical(other.measureId, measureId) || other.measureId == measureId)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.contributionId, contributionId) || other.contributionId == contributionId));
}


@override
int get hashCode => Object.hash(runtimeType,source,label,quantity,unit,measure,measureId,cookDay,contributionId);

@override
String toString() {
  return 'ShoppingContribution(source: $source, label: $label, quantity: $quantity, unit: $unit, measure: $measure, measureId: $measureId, cookDay: $cookDay, contributionId: $contributionId)';
}


}

/// @nodoc
abstract mixin class $ShoppingContributionCopyWith<$Res>  {
  factory $ShoppingContributionCopyWith(ShoppingContribution value, $Res Function(ShoppingContribution) _then) = _$ShoppingContributionCopyWithImpl;
@useResult
$Res call({
 ContributionSource source, String label, double? quantity, Unit? unit, Measure? measure, String? measureId, int? cookDay, String? contributionId
});




}
/// @nodoc
class _$ShoppingContributionCopyWithImpl<$Res>
    implements $ShoppingContributionCopyWith<$Res> {
  _$ShoppingContributionCopyWithImpl(this._self, this._then);

  final ShoppingContribution _self;
  final $Res Function(ShoppingContribution) _then;

/// Create a copy of ShoppingContribution
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? label = null,Object? quantity = freezed,Object? unit = freezed,Object? measure = freezed,Object? measureId = freezed,Object? cookDay = freezed,Object? contributionId = freezed,}) {
  return _then(_self.copyWith(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ContributionSource,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit?,measure: freezed == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as Measure?,measureId: freezed == measureId ? _self.measureId : measureId // ignore: cast_nullable_to_non_nullable
as String?,cookDay: freezed == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int?,contributionId: freezed == contributionId ? _self.contributionId : contributionId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShoppingContribution].
extension ShoppingContributionPatterns on ShoppingContribution {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShoppingContribution value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShoppingContribution() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShoppingContribution value)  $default,){
final _that = this;
switch (_that) {
case _ShoppingContribution():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShoppingContribution value)?  $default,){
final _that = this;
switch (_that) {
case _ShoppingContribution() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ContributionSource source,  String label,  double? quantity,  Unit? unit,  Measure? measure,  String? measureId,  int? cookDay,  String? contributionId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShoppingContribution() when $default != null:
return $default(_that.source,_that.label,_that.quantity,_that.unit,_that.measure,_that.measureId,_that.cookDay,_that.contributionId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ContributionSource source,  String label,  double? quantity,  Unit? unit,  Measure? measure,  String? measureId,  int? cookDay,  String? contributionId)  $default,) {final _that = this;
switch (_that) {
case _ShoppingContribution():
return $default(_that.source,_that.label,_that.quantity,_that.unit,_that.measure,_that.measureId,_that.cookDay,_that.contributionId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ContributionSource source,  String label,  double? quantity,  Unit? unit,  Measure? measure,  String? measureId,  int? cookDay,  String? contributionId)?  $default,) {final _that = this;
switch (_that) {
case _ShoppingContribution() when $default != null:
return $default(_that.source,_that.label,_that.quantity,_that.unit,_that.measure,_that.measureId,_that.cookDay,_that.contributionId);case _:
  return null;

}
}

}

/// @nodoc


class _ShoppingContribution implements ShoppingContribution {
  const _ShoppingContribution({required this.source, required this.label, this.quantity, this.unit, this.measure, this.measureId, this.cookDay, this.contributionId});
  

@override final  ContributionSource source;
/// The provenance label, e.g. "Curry · cook Mon", "Oat Cookies", or
/// "manual top-up".
@override final  String label;
/// Null for a bare non-food item (renders as a dash).
@override final  double? quantity;
@override final  Unit? unit;
/// The measure the quantity is counted in ("2 × potato, large"), when the
/// contribution was quantified in one; [unit] is null then.
@override final  Measure? measure;
/// The persisted `measure_id` of a manual contribution, verbatim — kept
/// even while [measure] is unresolved (row not yet synced / soft-deleted)
/// so the edit sheet's re-save never wipes the FK for every device
/// (mirrors the recipe line's [measureId]). Null for cook lines (derived,
/// never re-saved here).
@override final  String? measureId;
/// The day (0=Mon..6=Sun) a DERIVED contribution belongs to — a session's
/// cook day, or a planned snack's own day — which orders the breakdown.
/// Null for a manual top-up, which belongs to no day.
@override final  int? cookDay;
/// The persisted `shopping_list_contribution` id — set only for a `manual`
/// contribution (a cook one is derived, so it has none). Lets the UI edit
/// or remove this specific top-up.
@override final  String? contributionId;

/// Create a copy of ShoppingContribution
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShoppingContributionCopyWith<_ShoppingContribution> get copyWith => __$ShoppingContributionCopyWithImpl<_ShoppingContribution>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShoppingContribution&&(identical(other.source, source) || other.source == source)&&(identical(other.label, label) || other.label == label)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.measure, measure) || other.measure == measure)&&(identical(other.measureId, measureId) || other.measureId == measureId)&&(identical(other.cookDay, cookDay) || other.cookDay == cookDay)&&(identical(other.contributionId, contributionId) || other.contributionId == contributionId));
}


@override
int get hashCode => Object.hash(runtimeType,source,label,quantity,unit,measure,measureId,cookDay,contributionId);

@override
String toString() {
  return 'ShoppingContribution(source: $source, label: $label, quantity: $quantity, unit: $unit, measure: $measure, measureId: $measureId, cookDay: $cookDay, contributionId: $contributionId)';
}


}

/// @nodoc
abstract mixin class _$ShoppingContributionCopyWith<$Res> implements $ShoppingContributionCopyWith<$Res> {
  factory _$ShoppingContributionCopyWith(_ShoppingContribution value, $Res Function(_ShoppingContribution) _then) = __$ShoppingContributionCopyWithImpl;
@override @useResult
$Res call({
 ContributionSource source, String label, double? quantity, Unit? unit, Measure? measure, String? measureId, int? cookDay, String? contributionId
});




}
/// @nodoc
class __$ShoppingContributionCopyWithImpl<$Res>
    implements _$ShoppingContributionCopyWith<$Res> {
  __$ShoppingContributionCopyWithImpl(this._self, this._then);

  final _ShoppingContribution _self;
  final $Res Function(_ShoppingContribution) _then;

/// Create a copy of ShoppingContribution
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? label = null,Object? quantity = freezed,Object? unit = freezed,Object? measure = freezed,Object? measureId = freezed,Object? cookDay = freezed,Object? contributionId = freezed,}) {
  return _then(_ShoppingContribution(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ContributionSource,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit?,measure: freezed == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as Measure?,measureId: freezed == measureId ? _self.measureId : measureId // ignore: cast_nullable_to_non_nullable
as String?,cookDay: freezed == cookDay ? _self.cookDay : cookDay // ignore: cast_nullable_to_non_nullable
as int?,contributionId: freezed == contributionId ? _self.contributionId : contributionId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$ShoppingItem {

 String get name;/// The persisted entry id, if this line has one (a checked or topped-up
/// ingredient, or a free-text item). Null for a purely-derived ingredient
/// the user hasn't touched yet — check-off lazily creates the entry.
 String? get entryId;/// Null for a free-text (non-food) item.
 String? get ingredientId; bool get checked; List<Quantity> get totals; List<ShoppingContribution> get contributions;/// The item's total counted in ONE measure — "1 can (400 g), drained" —
/// set only when every quantified contribution asked for that same
/// measure. You buy the can, so the row says cans; [totals] still carries
/// the canonical mass/volume the cans weigh, which the row shows beside
/// it. Null the moment a plain mass/volume line or a second measure joins
/// the sum — neither has a single countable answer, so the family sum is
/// the only honest total.
 MeasureAmount? get measureTotal;/// The item's total as a count of PIECES — "2½ piece" — on a row whose
/// default unit is `piece` and that states what one weighs (ADR-0015),
/// once everything asked for has folded into ONE basis-family total: the
/// `piece` lines through the piece weight, the measures through theirs,
/// the plain mass/volume lines as they are. A lime asked for as `1 lime,
/// whole` here and `1½ piece` there is 2½ limes, not `67 g + 1½ piece`.
/// `approx` is false when every contribution was a `piece` line or a
/// measure that is a whole number of pieces (`lime, whole` = 67 g on a 67
/// g piece), true when a plain mass/volume line joined or a measure did
/// not divide evenly (`onion, small` = 70 g on a 110 g piece). [totals]
/// still carries the mass the count weighs. Null on every other row, and
/// null when [measureTotal] is set — a row asked for in one named measure
/// is counted in that measure, which is the more specific thing to buy.
 PieceTotal? get pieceTotal;/// An honest round-up hint ("2.25 → buy 3") for a measure-bearing count
/// ingredient — a HINT beside the total, never a replaced total
/// (invariant 3). Null when the item doesn't qualify (see
/// [wholeUnitHintFor]), and null whenever [measureTotal] or [pieceTotal]
/// is set: a row already counted in its measure or its pieces needs no
/// second way to say the same thing (each count carries its own
/// round-up under it).
 WholeUnitHint? get wholeUnitHint;
/// Create a copy of ShoppingItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingItemCopyWith<ShoppingItem> get copyWith => _$ShoppingItemCopyWithImpl<ShoppingItem>(this as ShoppingItem, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingItem&&(identical(other.name, name) || other.name == name)&&(identical(other.entryId, entryId) || other.entryId == entryId)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.checked, checked) || other.checked == checked)&&const DeepCollectionEquality().equals(other.totals, totals)&&const DeepCollectionEquality().equals(other.contributions, contributions)&&(identical(other.measureTotal, measureTotal) || other.measureTotal == measureTotal)&&(identical(other.pieceTotal, pieceTotal) || other.pieceTotal == pieceTotal)&&(identical(other.wholeUnitHint, wholeUnitHint) || other.wholeUnitHint == wholeUnitHint));
}


@override
int get hashCode => Object.hash(runtimeType,name,entryId,ingredientId,checked,const DeepCollectionEquality().hash(totals),const DeepCollectionEquality().hash(contributions),measureTotal,pieceTotal,wholeUnitHint);

@override
String toString() {
  return 'ShoppingItem(name: $name, entryId: $entryId, ingredientId: $ingredientId, checked: $checked, totals: $totals, contributions: $contributions, measureTotal: $measureTotal, pieceTotal: $pieceTotal, wholeUnitHint: $wholeUnitHint)';
}


}

/// @nodoc
abstract mixin class $ShoppingItemCopyWith<$Res>  {
  factory $ShoppingItemCopyWith(ShoppingItem value, $Res Function(ShoppingItem) _then) = _$ShoppingItemCopyWithImpl;
@useResult
$Res call({
 String name, String? entryId, String? ingredientId, bool checked, List<Quantity> totals, List<ShoppingContribution> contributions, MeasureAmount? measureTotal, PieceTotal? pieceTotal, WholeUnitHint? wholeUnitHint
});




}
/// @nodoc
class _$ShoppingItemCopyWithImpl<$Res>
    implements $ShoppingItemCopyWith<$Res> {
  _$ShoppingItemCopyWithImpl(this._self, this._then);

  final ShoppingItem _self;
  final $Res Function(ShoppingItem) _then;

/// Create a copy of ShoppingItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? entryId = freezed,Object? ingredientId = freezed,Object? checked = null,Object? totals = null,Object? contributions = null,Object? measureTotal = freezed,Object? pieceTotal = freezed,Object? wholeUnitHint = freezed,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,entryId: freezed == entryId ? _self.entryId : entryId // ignore: cast_nullable_to_non_nullable
as String?,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,checked: null == checked ? _self.checked : checked // ignore: cast_nullable_to_non_nullable
as bool,totals: null == totals ? _self.totals : totals // ignore: cast_nullable_to_non_nullable
as List<Quantity>,contributions: null == contributions ? _self.contributions : contributions // ignore: cast_nullable_to_non_nullable
as List<ShoppingContribution>,measureTotal: freezed == measureTotal ? _self.measureTotal : measureTotal // ignore: cast_nullable_to_non_nullable
as MeasureAmount?,pieceTotal: freezed == pieceTotal ? _self.pieceTotal : pieceTotal // ignore: cast_nullable_to_non_nullable
as PieceTotal?,wholeUnitHint: freezed == wholeUnitHint ? _self.wholeUnitHint : wholeUnitHint // ignore: cast_nullable_to_non_nullable
as WholeUnitHint?,
  ));
}

}


/// Adds pattern-matching-related methods to [ShoppingItem].
extension ShoppingItemPatterns on ShoppingItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShoppingItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShoppingItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShoppingItem value)  $default,){
final _that = this;
switch (_that) {
case _ShoppingItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShoppingItem value)?  $default,){
final _that = this;
switch (_that) {
case _ShoppingItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String? entryId,  String? ingredientId,  bool checked,  List<Quantity> totals,  List<ShoppingContribution> contributions,  MeasureAmount? measureTotal,  PieceTotal? pieceTotal,  WholeUnitHint? wholeUnitHint)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShoppingItem() when $default != null:
return $default(_that.name,_that.entryId,_that.ingredientId,_that.checked,_that.totals,_that.contributions,_that.measureTotal,_that.pieceTotal,_that.wholeUnitHint);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String? entryId,  String? ingredientId,  bool checked,  List<Quantity> totals,  List<ShoppingContribution> contributions,  MeasureAmount? measureTotal,  PieceTotal? pieceTotal,  WholeUnitHint? wholeUnitHint)  $default,) {final _that = this;
switch (_that) {
case _ShoppingItem():
return $default(_that.name,_that.entryId,_that.ingredientId,_that.checked,_that.totals,_that.contributions,_that.measureTotal,_that.pieceTotal,_that.wholeUnitHint);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String? entryId,  String? ingredientId,  bool checked,  List<Quantity> totals,  List<ShoppingContribution> contributions,  MeasureAmount? measureTotal,  PieceTotal? pieceTotal,  WholeUnitHint? wholeUnitHint)?  $default,) {final _that = this;
switch (_that) {
case _ShoppingItem() when $default != null:
return $default(_that.name,_that.entryId,_that.ingredientId,_that.checked,_that.totals,_that.contributions,_that.measureTotal,_that.pieceTotal,_that.wholeUnitHint);case _:
  return null;

}
}

}

/// @nodoc


class _ShoppingItem extends ShoppingItem {
  const _ShoppingItem({required this.name, this.entryId, this.ingredientId, this.checked = false, final  List<Quantity> totals = const <Quantity>[], final  List<ShoppingContribution> contributions = const <ShoppingContribution>[], this.measureTotal, this.pieceTotal, this.wholeUnitHint}): _totals = totals,_contributions = contributions,super._();
  

@override final  String name;
/// The persisted entry id, if this line has one (a checked or topped-up
/// ingredient, or a free-text item). Null for a purely-derived ingredient
/// the user hasn't touched yet — check-off lazily creates the entry.
@override final  String? entryId;
/// Null for a free-text (non-food) item.
@override final  String? ingredientId;
@override@JsonKey() final  bool checked;
 final  List<Quantity> _totals;
@override@JsonKey() List<Quantity> get totals {
  if (_totals is EqualUnmodifiableListView) return _totals;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_totals);
}

 final  List<ShoppingContribution> _contributions;
@override@JsonKey() List<ShoppingContribution> get contributions {
  if (_contributions is EqualUnmodifiableListView) return _contributions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_contributions);
}

/// The item's total counted in ONE measure — "1 can (400 g), drained" —
/// set only when every quantified contribution asked for that same
/// measure. You buy the can, so the row says cans; [totals] still carries
/// the canonical mass/volume the cans weigh, which the row shows beside
/// it. Null the moment a plain mass/volume line or a second measure joins
/// the sum — neither has a single countable answer, so the family sum is
/// the only honest total.
@override final  MeasureAmount? measureTotal;
/// The item's total as a count of PIECES — "2½ piece" — on a row whose
/// default unit is `piece` and that states what one weighs (ADR-0015),
/// once everything asked for has folded into ONE basis-family total: the
/// `piece` lines through the piece weight, the measures through theirs,
/// the plain mass/volume lines as they are. A lime asked for as `1 lime,
/// whole` here and `1½ piece` there is 2½ limes, not `67 g + 1½ piece`.
/// `approx` is false when every contribution was a `piece` line or a
/// measure that is a whole number of pieces (`lime, whole` = 67 g on a 67
/// g piece), true when a plain mass/volume line joined or a measure did
/// not divide evenly (`onion, small` = 70 g on a 110 g piece). [totals]
/// still carries the mass the count weighs. Null on every other row, and
/// null when [measureTotal] is set — a row asked for in one named measure
/// is counted in that measure, which is the more specific thing to buy.
@override final  PieceTotal? pieceTotal;
/// An honest round-up hint ("2.25 → buy 3") for a measure-bearing count
/// ingredient — a HINT beside the total, never a replaced total
/// (invariant 3). Null when the item doesn't qualify (see
/// [wholeUnitHintFor]), and null whenever [measureTotal] or [pieceTotal]
/// is set: a row already counted in its measure or its pieces needs no
/// second way to say the same thing (each count carries its own
/// round-up under it).
@override final  WholeUnitHint? wholeUnitHint;

/// Create a copy of ShoppingItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShoppingItemCopyWith<_ShoppingItem> get copyWith => __$ShoppingItemCopyWithImpl<_ShoppingItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShoppingItem&&(identical(other.name, name) || other.name == name)&&(identical(other.entryId, entryId) || other.entryId == entryId)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.checked, checked) || other.checked == checked)&&const DeepCollectionEquality().equals(other._totals, _totals)&&const DeepCollectionEquality().equals(other._contributions, _contributions)&&(identical(other.measureTotal, measureTotal) || other.measureTotal == measureTotal)&&(identical(other.pieceTotal, pieceTotal) || other.pieceTotal == pieceTotal)&&(identical(other.wholeUnitHint, wholeUnitHint) || other.wholeUnitHint == wholeUnitHint));
}


@override
int get hashCode => Object.hash(runtimeType,name,entryId,ingredientId,checked,const DeepCollectionEquality().hash(_totals),const DeepCollectionEquality().hash(_contributions),measureTotal,pieceTotal,wholeUnitHint);

@override
String toString() {
  return 'ShoppingItem(name: $name, entryId: $entryId, ingredientId: $ingredientId, checked: $checked, totals: $totals, contributions: $contributions, measureTotal: $measureTotal, pieceTotal: $pieceTotal, wholeUnitHint: $wholeUnitHint)';
}


}

/// @nodoc
abstract mixin class _$ShoppingItemCopyWith<$Res> implements $ShoppingItemCopyWith<$Res> {
  factory _$ShoppingItemCopyWith(_ShoppingItem value, $Res Function(_ShoppingItem) _then) = __$ShoppingItemCopyWithImpl;
@override @useResult
$Res call({
 String name, String? entryId, String? ingredientId, bool checked, List<Quantity> totals, List<ShoppingContribution> contributions, MeasureAmount? measureTotal, PieceTotal? pieceTotal, WholeUnitHint? wholeUnitHint
});




}
/// @nodoc
class __$ShoppingItemCopyWithImpl<$Res>
    implements _$ShoppingItemCopyWith<$Res> {
  __$ShoppingItemCopyWithImpl(this._self, this._then);

  final _ShoppingItem _self;
  final $Res Function(_ShoppingItem) _then;

/// Create a copy of ShoppingItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? entryId = freezed,Object? ingredientId = freezed,Object? checked = null,Object? totals = null,Object? contributions = null,Object? measureTotal = freezed,Object? pieceTotal = freezed,Object? wholeUnitHint = freezed,}) {
  return _then(_ShoppingItem(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,entryId: freezed == entryId ? _self.entryId : entryId // ignore: cast_nullable_to_non_nullable
as String?,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,checked: null == checked ? _self.checked : checked // ignore: cast_nullable_to_non_nullable
as bool,totals: null == totals ? _self._totals : totals // ignore: cast_nullable_to_non_nullable
as List<Quantity>,contributions: null == contributions ? _self._contributions : contributions // ignore: cast_nullable_to_non_nullable
as List<ShoppingContribution>,measureTotal: freezed == measureTotal ? _self.measureTotal : measureTotal // ignore: cast_nullable_to_non_nullable
as MeasureAmount?,pieceTotal: freezed == pieceTotal ? _self.pieceTotal : pieceTotal // ignore: cast_nullable_to_non_nullable
as PieceTotal?,wholeUnitHint: freezed == wholeUnitHint ? _self.wholeUnitHint : wholeUnitHint // ignore: cast_nullable_to_non_nullable
as WholeUnitHint?,
  ));
}


}

/// @nodoc
mixin _$ShoppingGroup {

 String get label; List<ShoppingItem> get items;
/// Create a copy of ShoppingGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingGroupCopyWith<ShoppingGroup> get copyWith => _$ShoppingGroupCopyWithImpl<ShoppingGroup>(this as ShoppingGroup, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingGroup&&(identical(other.label, label) || other.label == label)&&const DeepCollectionEquality().equals(other.items, items));
}


@override
int get hashCode => Object.hash(runtimeType,label,const DeepCollectionEquality().hash(items));

@override
String toString() {
  return 'ShoppingGroup(label: $label, items: $items)';
}


}

/// @nodoc
abstract mixin class $ShoppingGroupCopyWith<$Res>  {
  factory $ShoppingGroupCopyWith(ShoppingGroup value, $Res Function(ShoppingGroup) _then) = _$ShoppingGroupCopyWithImpl;
@useResult
$Res call({
 String label, List<ShoppingItem> items
});




}
/// @nodoc
class _$ShoppingGroupCopyWithImpl<$Res>
    implements $ShoppingGroupCopyWith<$Res> {
  _$ShoppingGroupCopyWithImpl(this._self, this._then);

  final ShoppingGroup _self;
  final $Res Function(ShoppingGroup) _then;

/// Create a copy of ShoppingGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? items = null,}) {
  return _then(_self.copyWith(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ShoppingItem>,
  ));
}

}


/// Adds pattern-matching-related methods to [ShoppingGroup].
extension ShoppingGroupPatterns on ShoppingGroup {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShoppingGroup value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShoppingGroup() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShoppingGroup value)  $default,){
final _that = this;
switch (_that) {
case _ShoppingGroup():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShoppingGroup value)?  $default,){
final _that = this;
switch (_that) {
case _ShoppingGroup() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  List<ShoppingItem> items)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShoppingGroup() when $default != null:
return $default(_that.label,_that.items);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  List<ShoppingItem> items)  $default,) {final _that = this;
switch (_that) {
case _ShoppingGroup():
return $default(_that.label,_that.items);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  List<ShoppingItem> items)?  $default,) {final _that = this;
switch (_that) {
case _ShoppingGroup() when $default != null:
return $default(_that.label,_that.items);case _:
  return null;

}
}

}

/// @nodoc


class _ShoppingGroup implements ShoppingGroup {
  const _ShoppingGroup({required this.label, final  List<ShoppingItem> items = const <ShoppingItem>[]}): _items = items;
  

@override final  String label;
 final  List<ShoppingItem> _items;
@override@JsonKey() List<ShoppingItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}


/// Create a copy of ShoppingGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShoppingGroupCopyWith<_ShoppingGroup> get copyWith => __$ShoppingGroupCopyWithImpl<_ShoppingGroup>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShoppingGroup&&(identical(other.label, label) || other.label == label)&&const DeepCollectionEquality().equals(other._items, _items));
}


@override
int get hashCode => Object.hash(runtimeType,label,const DeepCollectionEquality().hash(_items));

@override
String toString() {
  return 'ShoppingGroup(label: $label, items: $items)';
}


}

/// @nodoc
abstract mixin class _$ShoppingGroupCopyWith<$Res> implements $ShoppingGroupCopyWith<$Res> {
  factory _$ShoppingGroupCopyWith(_ShoppingGroup value, $Res Function(_ShoppingGroup) _then) = __$ShoppingGroupCopyWithImpl;
@override @useResult
$Res call({
 String label, List<ShoppingItem> items
});




}
/// @nodoc
class __$ShoppingGroupCopyWithImpl<$Res>
    implements _$ShoppingGroupCopyWith<$Res> {
  __$ShoppingGroupCopyWithImpl(this._self, this._then);

  final _ShoppingGroup _self;
  final $Res Function(_ShoppingGroup) _then;

/// Create a copy of ShoppingGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? items = null,}) {
  return _then(_ShoppingGroup(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ShoppingItem>,
  ));
}


}

/// @nodoc
mixin _$ShoppingList {

 List<ShoppingGroup> get groups; List<UnresolvedComponentNote> get unresolvedComponents; List<OptionalLinesNote> get optionalLines; List<RetiredIngredientNote> get retiredIngredients;
/// Create a copy of ShoppingList
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShoppingListCopyWith<ShoppingList> get copyWith => _$ShoppingListCopyWithImpl<ShoppingList>(this as ShoppingList, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShoppingList&&const DeepCollectionEquality().equals(other.groups, groups)&&const DeepCollectionEquality().equals(other.unresolvedComponents, unresolvedComponents)&&const DeepCollectionEquality().equals(other.optionalLines, optionalLines)&&const DeepCollectionEquality().equals(other.retiredIngredients, retiredIngredients));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(groups),const DeepCollectionEquality().hash(unresolvedComponents),const DeepCollectionEquality().hash(optionalLines),const DeepCollectionEquality().hash(retiredIngredients));

@override
String toString() {
  return 'ShoppingList(groups: $groups, unresolvedComponents: $unresolvedComponents, optionalLines: $optionalLines, retiredIngredients: $retiredIngredients)';
}


}

/// @nodoc
abstract mixin class $ShoppingListCopyWith<$Res>  {
  factory $ShoppingListCopyWith(ShoppingList value, $Res Function(ShoppingList) _then) = _$ShoppingListCopyWithImpl;
@useResult
$Res call({
 List<ShoppingGroup> groups, List<UnresolvedComponentNote> unresolvedComponents, List<OptionalLinesNote> optionalLines, List<RetiredIngredientNote> retiredIngredients
});




}
/// @nodoc
class _$ShoppingListCopyWithImpl<$Res>
    implements $ShoppingListCopyWith<$Res> {
  _$ShoppingListCopyWithImpl(this._self, this._then);

  final ShoppingList _self;
  final $Res Function(ShoppingList) _then;

/// Create a copy of ShoppingList
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? groups = null,Object? unresolvedComponents = null,Object? optionalLines = null,Object? retiredIngredients = null,}) {
  return _then(_self.copyWith(
groups: null == groups ? _self.groups : groups // ignore: cast_nullable_to_non_nullable
as List<ShoppingGroup>,unresolvedComponents: null == unresolvedComponents ? _self.unresolvedComponents : unresolvedComponents // ignore: cast_nullable_to_non_nullable
as List<UnresolvedComponentNote>,optionalLines: null == optionalLines ? _self.optionalLines : optionalLines // ignore: cast_nullable_to_non_nullable
as List<OptionalLinesNote>,retiredIngredients: null == retiredIngredients ? _self.retiredIngredients : retiredIngredients // ignore: cast_nullable_to_non_nullable
as List<RetiredIngredientNote>,
  ));
}

}


/// Adds pattern-matching-related methods to [ShoppingList].
extension ShoppingListPatterns on ShoppingList {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShoppingList value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShoppingList() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShoppingList value)  $default,){
final _that = this;
switch (_that) {
case _ShoppingList():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShoppingList value)?  $default,){
final _that = this;
switch (_that) {
case _ShoppingList() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ShoppingGroup> groups,  List<UnresolvedComponentNote> unresolvedComponents,  List<OptionalLinesNote> optionalLines,  List<RetiredIngredientNote> retiredIngredients)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShoppingList() when $default != null:
return $default(_that.groups,_that.unresolvedComponents,_that.optionalLines,_that.retiredIngredients);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ShoppingGroup> groups,  List<UnresolvedComponentNote> unresolvedComponents,  List<OptionalLinesNote> optionalLines,  List<RetiredIngredientNote> retiredIngredients)  $default,) {final _that = this;
switch (_that) {
case _ShoppingList():
return $default(_that.groups,_that.unresolvedComponents,_that.optionalLines,_that.retiredIngredients);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ShoppingGroup> groups,  List<UnresolvedComponentNote> unresolvedComponents,  List<OptionalLinesNote> optionalLines,  List<RetiredIngredientNote> retiredIngredients)?  $default,) {final _that = this;
switch (_that) {
case _ShoppingList() when $default != null:
return $default(_that.groups,_that.unresolvedComponents,_that.optionalLines,_that.retiredIngredients);case _:
  return null;

}
}

}

/// @nodoc


class _ShoppingList extends ShoppingList {
  const _ShoppingList({final  List<ShoppingGroup> groups = const <ShoppingGroup>[], final  List<UnresolvedComponentNote> unresolvedComponents = const <UnresolvedComponentNote>[], final  List<OptionalLinesNote> optionalLines = const <OptionalLinesNote>[], final  List<RetiredIngredientNote> retiredIngredients = const <RetiredIngredientNote>[]}): _groups = groups,_unresolvedComponents = unresolvedComponents,_optionalLines = optionalLines,_retiredIngredients = retiredIngredients,super._();
  

 final  List<ShoppingGroup> _groups;
@override@JsonKey() List<ShoppingGroup> get groups {
  if (_groups is EqualUnmodifiableListView) return _groups;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_groups);
}

 final  List<UnresolvedComponentNote> _unresolvedComponents;
@override@JsonKey() List<UnresolvedComponentNote> get unresolvedComponents {
  if (_unresolvedComponents is EqualUnmodifiableListView) return _unresolvedComponents;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_unresolvedComponents);
}

 final  List<OptionalLinesNote> _optionalLines;
@override@JsonKey() List<OptionalLinesNote> get optionalLines {
  if (_optionalLines is EqualUnmodifiableListView) return _optionalLines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_optionalLines);
}

 final  List<RetiredIngredientNote> _retiredIngredients;
@override@JsonKey() List<RetiredIngredientNote> get retiredIngredients {
  if (_retiredIngredients is EqualUnmodifiableListView) return _retiredIngredients;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_retiredIngredients);
}


/// Create a copy of ShoppingList
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShoppingListCopyWith<_ShoppingList> get copyWith => __$ShoppingListCopyWithImpl<_ShoppingList>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShoppingList&&const DeepCollectionEquality().equals(other._groups, _groups)&&const DeepCollectionEquality().equals(other._unresolvedComponents, _unresolvedComponents)&&const DeepCollectionEquality().equals(other._optionalLines, _optionalLines)&&const DeepCollectionEquality().equals(other._retiredIngredients, _retiredIngredients));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_groups),const DeepCollectionEquality().hash(_unresolvedComponents),const DeepCollectionEquality().hash(_optionalLines),const DeepCollectionEquality().hash(_retiredIngredients));

@override
String toString() {
  return 'ShoppingList(groups: $groups, unresolvedComponents: $unresolvedComponents, optionalLines: $optionalLines, retiredIngredients: $retiredIngredients)';
}


}

/// @nodoc
abstract mixin class _$ShoppingListCopyWith<$Res> implements $ShoppingListCopyWith<$Res> {
  factory _$ShoppingListCopyWith(_ShoppingList value, $Res Function(_ShoppingList) _then) = __$ShoppingListCopyWithImpl;
@override @useResult
$Res call({
 List<ShoppingGroup> groups, List<UnresolvedComponentNote> unresolvedComponents, List<OptionalLinesNote> optionalLines, List<RetiredIngredientNote> retiredIngredients
});




}
/// @nodoc
class __$ShoppingListCopyWithImpl<$Res>
    implements _$ShoppingListCopyWith<$Res> {
  __$ShoppingListCopyWithImpl(this._self, this._then);

  final _ShoppingList _self;
  final $Res Function(_ShoppingList) _then;

/// Create a copy of ShoppingList
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? groups = null,Object? unresolvedComponents = null,Object? optionalLines = null,Object? retiredIngredients = null,}) {
  return _then(_ShoppingList(
groups: null == groups ? _self._groups : groups // ignore: cast_nullable_to_non_nullable
as List<ShoppingGroup>,unresolvedComponents: null == unresolvedComponents ? _self._unresolvedComponents : unresolvedComponents // ignore: cast_nullable_to_non_nullable
as List<UnresolvedComponentNote>,optionalLines: null == optionalLines ? _self._optionalLines : optionalLines // ignore: cast_nullable_to_non_nullable
as List<OptionalLinesNote>,retiredIngredients: null == retiredIngredients ? _self._retiredIngredients : retiredIngredients // ignore: cast_nullable_to_non_nullable
as List<RetiredIngredientNote>,
  ));
}


}

// dart format on
