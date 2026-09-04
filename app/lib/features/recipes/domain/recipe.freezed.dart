// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recipe.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Recipe {

 String get id; String get title;/// The serving count the written quantities are for. Scaling multiplies
/// against this (see `scaling.dart`); it is never zero (DB check enforces).
 double get servingsBase; List<IngredientGroup> get groups;/// Ordered method steps, one line each — the plain-text form the editor
/// writes and reads.
 List<String> get steps;/// Tokenized method (step 8 import): text/ref/timer chips rendered by the
/// fold ([foldMethod]). Non-null only for an imported recipe; the editor's
/// plain-text [steps] and this are the two shapes the `steps` jsonb holds,
/// and one row carries one of them — never both.
 List<MethodStep>? get methodSteps;/// Fridge shelf life; drives the cook-plan clustering (step 5), set from
/// the recipe editor's shelf-life inputs.
 int? get keepsForDays; bool get freezable; int? get freezerDays;/// The book/section this recipe is filed under (step 3). [bookId] is set for
/// any recipe surfaced through the Library; [sectionId] is null when
/// Unsectioned. [bookName]/[sectionName] are denormalised for the recipe
/// page's "Book · Section" hero line (display-only; assembled on read).
 String? get bookId; String? get sectionId; String? get bookName; String? get sectionName;/// Honest **per-serving** macros for the recipe as written, or an
/// incomplete marker (step 9's recipe-page panel; the same summary the
/// picker rows render). Derived on read from the line items and the
/// vocab — never persisted, and ignored by `saveRecipe`.
///
/// Per-serving means the servings scaler does NOT move these numbers:
/// scaling multiplies the whole recipe *and* the servings it yields, so
/// each serving is unchanged. Null only where a caller builds a [Recipe]
/// without line nutrition (tests, the editor's in-flight draft).
 RecipeMacroSummary? get macros;/// What one batch MAKES — "makes 1 cup", "makes 8 piece" (step 8.6 / D2).
/// Independent of [servingsBase]: portions and yield are two different
/// facts, and neither derives from the other. Both halves are set or
/// neither is (a DB check pins it).
///
/// This is the number that turns a component line's `¼ cup` into `¼ of a
/// batch`. Null ⇒ every derived number about this recipe-as-a-component
/// honestly says it cannot be computed; nothing assumes `1×`.
 double? get yieldQty; Unit? get yieldUnit;/// The optional SECOND denomination of the same batch — "makes 250 g ·
/// 16 tbsp". Pinned by the database to a DIFFERENT unit family than the
/// first, so the pair bridges mass↔volume *for this recipe only*, the way
/// an `ingredient_measure` bridges count↔mass — two stated facts, no
/// density.
 double? get yieldQty2; Unit? get yieldUnit2;/// The printed cook and total times, in seconds. Two typed facts with no
/// rule between them — a total below the cook time is what somebody wrote,
/// not an error to refuse. Null is unset: the page never said, and nothing
/// invents one.
 int? get cookTimeSeconds; int? get totalTimeSeconds;
/// Create a copy of Recipe
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecipeCopyWith<Recipe> get copyWith => _$RecipeCopyWithImpl<Recipe>(this as Recipe, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Recipe&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&const DeepCollectionEquality().equals(other.groups, groups)&&const DeepCollectionEquality().equals(other.steps, steps)&&const DeepCollectionEquality().equals(other.methodSteps, methodSteps)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.sectionId, sectionId) || other.sectionId == sectionId)&&(identical(other.bookName, bookName) || other.bookName == bookName)&&(identical(other.sectionName, sectionName) || other.sectionName == sectionName)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.yieldQty, yieldQty) || other.yieldQty == yieldQty)&&(identical(other.yieldUnit, yieldUnit) || other.yieldUnit == yieldUnit)&&(identical(other.yieldQty2, yieldQty2) || other.yieldQty2 == yieldQty2)&&(identical(other.yieldUnit2, yieldUnit2) || other.yieldUnit2 == yieldUnit2)&&(identical(other.cookTimeSeconds, cookTimeSeconds) || other.cookTimeSeconds == cookTimeSeconds)&&(identical(other.totalTimeSeconds, totalTimeSeconds) || other.totalTimeSeconds == totalTimeSeconds));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,title,servingsBase,const DeepCollectionEquality().hash(groups),const DeepCollectionEquality().hash(steps),const DeepCollectionEquality().hash(methodSteps),keepsForDays,freezable,freezerDays,bookId,sectionId,bookName,sectionName,macros,yieldQty,yieldUnit,yieldQty2,yieldUnit2,cookTimeSeconds,totalTimeSeconds]);

@override
String toString() {
  return 'Recipe(id: $id, title: $title, servingsBase: $servingsBase, groups: $groups, steps: $steps, methodSteps: $methodSteps, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, bookId: $bookId, sectionId: $sectionId, bookName: $bookName, sectionName: $sectionName, macros: $macros, yieldQty: $yieldQty, yieldUnit: $yieldUnit, yieldQty2: $yieldQty2, yieldUnit2: $yieldUnit2, cookTimeSeconds: $cookTimeSeconds, totalTimeSeconds: $totalTimeSeconds)';
}


}

/// @nodoc
abstract mixin class $RecipeCopyWith<$Res>  {
  factory $RecipeCopyWith(Recipe value, $Res Function(Recipe) _then) = _$RecipeCopyWithImpl;
@useResult
$Res call({
 String id, String title, double servingsBase, List<IngredientGroup> groups, List<String> steps, List<MethodStep>? methodSteps, int? keepsForDays, bool freezable, int? freezerDays, String? bookId, String? sectionId, String? bookName, String? sectionName, RecipeMacroSummary? macros, double? yieldQty, Unit? yieldUnit, double? yieldQty2, Unit? yieldUnit2, int? cookTimeSeconds, int? totalTimeSeconds
});




}
/// @nodoc
class _$RecipeCopyWithImpl<$Res>
    implements $RecipeCopyWith<$Res> {
  _$RecipeCopyWithImpl(this._self, this._then);

  final Recipe _self;
  final $Res Function(Recipe) _then;

/// Create a copy of Recipe
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? servingsBase = null,Object? groups = null,Object? steps = null,Object? methodSteps = freezed,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? bookId = freezed,Object? sectionId = freezed,Object? bookName = freezed,Object? sectionName = freezed,Object? macros = freezed,Object? yieldQty = freezed,Object? yieldUnit = freezed,Object? yieldQty2 = freezed,Object? yieldUnit2 = freezed,Object? cookTimeSeconds = freezed,Object? totalTimeSeconds = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,groups: null == groups ? _self.groups : groups // ignore: cast_nullable_to_non_nullable
as List<IngredientGroup>,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<String>,methodSteps: freezed == methodSteps ? _self.methodSteps : methodSteps // ignore: cast_nullable_to_non_nullable
as List<MethodStep>?,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,bookId: freezed == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as String?,sectionId: freezed == sectionId ? _self.sectionId : sectionId // ignore: cast_nullable_to_non_nullable
as String?,bookName: freezed == bookName ? _self.bookName : bookName // ignore: cast_nullable_to_non_nullable
as String?,sectionName: freezed == sectionName ? _self.sectionName : sectionName // ignore: cast_nullable_to_non_nullable
as String?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as RecipeMacroSummary?,yieldQty: freezed == yieldQty ? _self.yieldQty : yieldQty // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit: freezed == yieldUnit ? _self.yieldUnit : yieldUnit // ignore: cast_nullable_to_non_nullable
as Unit?,yieldQty2: freezed == yieldQty2 ? _self.yieldQty2 : yieldQty2 // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit2: freezed == yieldUnit2 ? _self.yieldUnit2 : yieldUnit2 // ignore: cast_nullable_to_non_nullable
as Unit?,cookTimeSeconds: freezed == cookTimeSeconds ? _self.cookTimeSeconds : cookTimeSeconds // ignore: cast_nullable_to_non_nullable
as int?,totalTimeSeconds: freezed == totalTimeSeconds ? _self.totalTimeSeconds : totalTimeSeconds // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [Recipe].
extension RecipePatterns on Recipe {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Recipe value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Recipe() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Recipe value)  $default,){
final _that = this;
switch (_that) {
case _Recipe():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Recipe value)?  $default,){
final _that = this;
switch (_that) {
case _Recipe() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  double servingsBase,  List<IngredientGroup> groups,  List<String> steps,  List<MethodStep>? methodSteps,  int? keepsForDays,  bool freezable,  int? freezerDays,  String? bookId,  String? sectionId,  String? bookName,  String? sectionName,  RecipeMacroSummary? macros,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2,  int? cookTimeSeconds,  int? totalTimeSeconds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Recipe() when $default != null:
return $default(_that.id,_that.title,_that.servingsBase,_that.groups,_that.steps,_that.methodSteps,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.bookId,_that.sectionId,_that.bookName,_that.sectionName,_that.macros,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2,_that.cookTimeSeconds,_that.totalTimeSeconds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  double servingsBase,  List<IngredientGroup> groups,  List<String> steps,  List<MethodStep>? methodSteps,  int? keepsForDays,  bool freezable,  int? freezerDays,  String? bookId,  String? sectionId,  String? bookName,  String? sectionName,  RecipeMacroSummary? macros,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2,  int? cookTimeSeconds,  int? totalTimeSeconds)  $default,) {final _that = this;
switch (_that) {
case _Recipe():
return $default(_that.id,_that.title,_that.servingsBase,_that.groups,_that.steps,_that.methodSteps,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.bookId,_that.sectionId,_that.bookName,_that.sectionName,_that.macros,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2,_that.cookTimeSeconds,_that.totalTimeSeconds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  double servingsBase,  List<IngredientGroup> groups,  List<String> steps,  List<MethodStep>? methodSteps,  int? keepsForDays,  bool freezable,  int? freezerDays,  String? bookId,  String? sectionId,  String? bookName,  String? sectionName,  RecipeMacroSummary? macros,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2,  int? cookTimeSeconds,  int? totalTimeSeconds)?  $default,) {final _that = this;
switch (_that) {
case _Recipe() when $default != null:
return $default(_that.id,_that.title,_that.servingsBase,_that.groups,_that.steps,_that.methodSteps,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.bookId,_that.sectionId,_that.bookName,_that.sectionName,_that.macros,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2,_that.cookTimeSeconds,_that.totalTimeSeconds);case _:
  return null;

}
}

}

/// @nodoc


class _Recipe extends Recipe {
  const _Recipe({required this.id, required this.title, required this.servingsBase, final  List<IngredientGroup> groups = const <IngredientGroup>[], final  List<String> steps = const <String>[], final  List<MethodStep>? methodSteps, this.keepsForDays, this.freezable = false, this.freezerDays, this.bookId, this.sectionId, this.bookName, this.sectionName, this.macros, this.yieldQty, this.yieldUnit, this.yieldQty2, this.yieldUnit2, this.cookTimeSeconds, this.totalTimeSeconds}): _groups = groups,_steps = steps,_methodSteps = methodSteps,super._();
  

@override final  String id;
@override final  String title;
/// The serving count the written quantities are for. Scaling multiplies
/// against this (see `scaling.dart`); it is never zero (DB check enforces).
@override final  double servingsBase;
 final  List<IngredientGroup> _groups;
@override@JsonKey() List<IngredientGroup> get groups {
  if (_groups is EqualUnmodifiableListView) return _groups;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_groups);
}

/// Ordered method steps, one line each — the plain-text form the editor
/// writes and reads.
 final  List<String> _steps;
/// Ordered method steps, one line each — the plain-text form the editor
/// writes and reads.
@override@JsonKey() List<String> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}

/// Tokenized method (step 8 import): text/ref/timer chips rendered by the
/// fold ([foldMethod]). Non-null only for an imported recipe; the editor's
/// plain-text [steps] and this are the two shapes the `steps` jsonb holds,
/// and one row carries one of them — never both.
 final  List<MethodStep>? _methodSteps;
/// Tokenized method (step 8 import): text/ref/timer chips rendered by the
/// fold ([foldMethod]). Non-null only for an imported recipe; the editor's
/// plain-text [steps] and this are the two shapes the `steps` jsonb holds,
/// and one row carries one of them — never both.
@override List<MethodStep>? get methodSteps {
  final value = _methodSteps;
  if (value == null) return null;
  if (_methodSteps is EqualUnmodifiableListView) return _methodSteps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

/// Fridge shelf life; drives the cook-plan clustering (step 5), set from
/// the recipe editor's shelf-life inputs.
@override final  int? keepsForDays;
@override@JsonKey() final  bool freezable;
@override final  int? freezerDays;
/// The book/section this recipe is filed under (step 3). [bookId] is set for
/// any recipe surfaced through the Library; [sectionId] is null when
/// Unsectioned. [bookName]/[sectionName] are denormalised for the recipe
/// page's "Book · Section" hero line (display-only; assembled on read).
@override final  String? bookId;
@override final  String? sectionId;
@override final  String? bookName;
@override final  String? sectionName;
/// Honest **per-serving** macros for the recipe as written, or an
/// incomplete marker (step 9's recipe-page panel; the same summary the
/// picker rows render). Derived on read from the line items and the
/// vocab — never persisted, and ignored by `saveRecipe`.
///
/// Per-serving means the servings scaler does NOT move these numbers:
/// scaling multiplies the whole recipe *and* the servings it yields, so
/// each serving is unchanged. Null only where a caller builds a [Recipe]
/// without line nutrition (tests, the editor's in-flight draft).
@override final  RecipeMacroSummary? macros;
/// What one batch MAKES — "makes 1 cup", "makes 8 piece" (step 8.6 / D2).
/// Independent of [servingsBase]: portions and yield are two different
/// facts, and neither derives from the other. Both halves are set or
/// neither is (a DB check pins it).
///
/// This is the number that turns a component line's `¼ cup` into `¼ of a
/// batch`. Null ⇒ every derived number about this recipe-as-a-component
/// honestly says it cannot be computed; nothing assumes `1×`.
@override final  double? yieldQty;
@override final  Unit? yieldUnit;
/// The optional SECOND denomination of the same batch — "makes 250 g ·
/// 16 tbsp". Pinned by the database to a DIFFERENT unit family than the
/// first, so the pair bridges mass↔volume *for this recipe only*, the way
/// an `ingredient_measure` bridges count↔mass — two stated facts, no
/// density.
@override final  double? yieldQty2;
@override final  Unit? yieldUnit2;
/// The printed cook and total times, in seconds. Two typed facts with no
/// rule between them — a total below the cook time is what somebody wrote,
/// not an error to refuse. Null is unset: the page never said, and nothing
/// invents one.
@override final  int? cookTimeSeconds;
@override final  int? totalTimeSeconds;

/// Create a copy of Recipe
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecipeCopyWith<_Recipe> get copyWith => __$RecipeCopyWithImpl<_Recipe>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Recipe&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&const DeepCollectionEquality().equals(other._groups, _groups)&&const DeepCollectionEquality().equals(other._steps, _steps)&&const DeepCollectionEquality().equals(other._methodSteps, _methodSteps)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.sectionId, sectionId) || other.sectionId == sectionId)&&(identical(other.bookName, bookName) || other.bookName == bookName)&&(identical(other.sectionName, sectionName) || other.sectionName == sectionName)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.yieldQty, yieldQty) || other.yieldQty == yieldQty)&&(identical(other.yieldUnit, yieldUnit) || other.yieldUnit == yieldUnit)&&(identical(other.yieldQty2, yieldQty2) || other.yieldQty2 == yieldQty2)&&(identical(other.yieldUnit2, yieldUnit2) || other.yieldUnit2 == yieldUnit2)&&(identical(other.cookTimeSeconds, cookTimeSeconds) || other.cookTimeSeconds == cookTimeSeconds)&&(identical(other.totalTimeSeconds, totalTimeSeconds) || other.totalTimeSeconds == totalTimeSeconds));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,title,servingsBase,const DeepCollectionEquality().hash(_groups),const DeepCollectionEquality().hash(_steps),const DeepCollectionEquality().hash(_methodSteps),keepsForDays,freezable,freezerDays,bookId,sectionId,bookName,sectionName,macros,yieldQty,yieldUnit,yieldQty2,yieldUnit2,cookTimeSeconds,totalTimeSeconds]);

@override
String toString() {
  return 'Recipe(id: $id, title: $title, servingsBase: $servingsBase, groups: $groups, steps: $steps, methodSteps: $methodSteps, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, bookId: $bookId, sectionId: $sectionId, bookName: $bookName, sectionName: $sectionName, macros: $macros, yieldQty: $yieldQty, yieldUnit: $yieldUnit, yieldQty2: $yieldQty2, yieldUnit2: $yieldUnit2, cookTimeSeconds: $cookTimeSeconds, totalTimeSeconds: $totalTimeSeconds)';
}


}

/// @nodoc
abstract mixin class _$RecipeCopyWith<$Res> implements $RecipeCopyWith<$Res> {
  factory _$RecipeCopyWith(_Recipe value, $Res Function(_Recipe) _then) = __$RecipeCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, double servingsBase, List<IngredientGroup> groups, List<String> steps, List<MethodStep>? methodSteps, int? keepsForDays, bool freezable, int? freezerDays, String? bookId, String? sectionId, String? bookName, String? sectionName, RecipeMacroSummary? macros, double? yieldQty, Unit? yieldUnit, double? yieldQty2, Unit? yieldUnit2, int? cookTimeSeconds, int? totalTimeSeconds
});




}
/// @nodoc
class __$RecipeCopyWithImpl<$Res>
    implements _$RecipeCopyWith<$Res> {
  __$RecipeCopyWithImpl(this._self, this._then);

  final _Recipe _self;
  final $Res Function(_Recipe) _then;

/// Create a copy of Recipe
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? servingsBase = null,Object? groups = null,Object? steps = null,Object? methodSteps = freezed,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? bookId = freezed,Object? sectionId = freezed,Object? bookName = freezed,Object? sectionName = freezed,Object? macros = freezed,Object? yieldQty = freezed,Object? yieldUnit = freezed,Object? yieldQty2 = freezed,Object? yieldUnit2 = freezed,Object? cookTimeSeconds = freezed,Object? totalTimeSeconds = freezed,}) {
  return _then(_Recipe(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,groups: null == groups ? _self._groups : groups // ignore: cast_nullable_to_non_nullable
as List<IngredientGroup>,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<String>,methodSteps: freezed == methodSteps ? _self._methodSteps : methodSteps // ignore: cast_nullable_to_non_nullable
as List<MethodStep>?,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,bookId: freezed == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as String?,sectionId: freezed == sectionId ? _self.sectionId : sectionId // ignore: cast_nullable_to_non_nullable
as String?,bookName: freezed == bookName ? _self.bookName : bookName // ignore: cast_nullable_to_non_nullable
as String?,sectionName: freezed == sectionName ? _self.sectionName : sectionName // ignore: cast_nullable_to_non_nullable
as String?,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as RecipeMacroSummary?,yieldQty: freezed == yieldQty ? _self.yieldQty : yieldQty // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit: freezed == yieldUnit ? _self.yieldUnit : yieldUnit // ignore: cast_nullable_to_non_nullable
as Unit?,yieldQty2: freezed == yieldQty2 ? _self.yieldQty2 : yieldQty2 // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit2: freezed == yieldUnit2 ? _self.yieldUnit2 : yieldUnit2 // ignore: cast_nullable_to_non_nullable
as Unit?,cookTimeSeconds: freezed == cookTimeSeconds ? _self.cookTimeSeconds : cookTimeSeconds // ignore: cast_nullable_to_non_nullable
as int?,totalTimeSeconds: freezed == totalTimeSeconds ? _self.totalTimeSeconds : totalTimeSeconds // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$RecipeSummary {

 String get id; String get title; double get servingsBase;/// Shelf-life carried on the summary so the planner can show batch-aware
/// chips and the "same batch" hint without the full recipe (step 5).
 int? get keepsForDays; bool get freezable; int? get freezerDays;/// The household's curated shortlist flag (the picker's Favorites tab).
 bool get favorite;/// Honest per-serving macros, or an incomplete marker (step 7.7).
 RecipeMacroSummary? get macros;/// What one batch makes (step 8.6 / D2) — carried on the summary so a
/// picker row can say "makes 1 cup" (or "no yield yet") without loading
/// the whole recipe. See [Recipe.yieldQty].
 double? get yieldQty; Unit? get yieldUnit; double? get yieldQty2; Unit? get yieldUnit2;
/// Create a copy of RecipeSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecipeSummaryCopyWith<RecipeSummary> get copyWith => _$RecipeSummaryCopyWithImpl<RecipeSummary>(this as RecipeSummary, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecipeSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&(identical(other.favorite, favorite) || other.favorite == favorite)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.yieldQty, yieldQty) || other.yieldQty == yieldQty)&&(identical(other.yieldUnit, yieldUnit) || other.yieldUnit == yieldUnit)&&(identical(other.yieldQty2, yieldQty2) || other.yieldQty2 == yieldQty2)&&(identical(other.yieldUnit2, yieldUnit2) || other.yieldUnit2 == yieldUnit2));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,servingsBase,keepsForDays,freezable,freezerDays,favorite,macros,yieldQty,yieldUnit,yieldQty2,yieldUnit2);

@override
String toString() {
  return 'RecipeSummary(id: $id, title: $title, servingsBase: $servingsBase, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, favorite: $favorite, macros: $macros, yieldQty: $yieldQty, yieldUnit: $yieldUnit, yieldQty2: $yieldQty2, yieldUnit2: $yieldUnit2)';
}


}

/// @nodoc
abstract mixin class $RecipeSummaryCopyWith<$Res>  {
  factory $RecipeSummaryCopyWith(RecipeSummary value, $Res Function(RecipeSummary) _then) = _$RecipeSummaryCopyWithImpl;
@useResult
$Res call({
 String id, String title, double servingsBase, int? keepsForDays, bool freezable, int? freezerDays, bool favorite, RecipeMacroSummary? macros, double? yieldQty, Unit? yieldUnit, double? yieldQty2, Unit? yieldUnit2
});




}
/// @nodoc
class _$RecipeSummaryCopyWithImpl<$Res>
    implements $RecipeSummaryCopyWith<$Res> {
  _$RecipeSummaryCopyWithImpl(this._self, this._then);

  final RecipeSummary _self;
  final $Res Function(RecipeSummary) _then;

/// Create a copy of RecipeSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? servingsBase = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? favorite = null,Object? macros = freezed,Object? yieldQty = freezed,Object? yieldUnit = freezed,Object? yieldQty2 = freezed,Object? yieldUnit2 = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,favorite: null == favorite ? _self.favorite : favorite // ignore: cast_nullable_to_non_nullable
as bool,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as RecipeMacroSummary?,yieldQty: freezed == yieldQty ? _self.yieldQty : yieldQty // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit: freezed == yieldUnit ? _self.yieldUnit : yieldUnit // ignore: cast_nullable_to_non_nullable
as Unit?,yieldQty2: freezed == yieldQty2 ? _self.yieldQty2 : yieldQty2 // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit2: freezed == yieldUnit2 ? _self.yieldUnit2 : yieldUnit2 // ignore: cast_nullable_to_non_nullable
as Unit?,
  ));
}

}


/// Adds pattern-matching-related methods to [RecipeSummary].
extension RecipeSummaryPatterns on RecipeSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecipeSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecipeSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecipeSummary value)  $default,){
final _that = this;
switch (_that) {
case _RecipeSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecipeSummary value)?  $default,){
final _that = this;
switch (_that) {
case _RecipeSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  double servingsBase,  int? keepsForDays,  bool freezable,  int? freezerDays,  bool favorite,  RecipeMacroSummary? macros,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecipeSummary() when $default != null:
return $default(_that.id,_that.title,_that.servingsBase,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.favorite,_that.macros,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  double servingsBase,  int? keepsForDays,  bool freezable,  int? freezerDays,  bool favorite,  RecipeMacroSummary? macros,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2)  $default,) {final _that = this;
switch (_that) {
case _RecipeSummary():
return $default(_that.id,_that.title,_that.servingsBase,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.favorite,_that.macros,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  double servingsBase,  int? keepsForDays,  bool freezable,  int? freezerDays,  bool favorite,  RecipeMacroSummary? macros,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2)?  $default,) {final _that = this;
switch (_that) {
case _RecipeSummary() when $default != null:
return $default(_that.id,_that.title,_that.servingsBase,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.favorite,_that.macros,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2);case _:
  return null;

}
}

}

/// @nodoc


class _RecipeSummary extends RecipeSummary {
  const _RecipeSummary({required this.id, required this.title, required this.servingsBase, this.keepsForDays, this.freezable = false, this.freezerDays, this.favorite = false, this.macros, this.yieldQty, this.yieldUnit, this.yieldQty2, this.yieldUnit2}): super._();
  

@override final  String id;
@override final  String title;
@override final  double servingsBase;
/// Shelf-life carried on the summary so the planner can show batch-aware
/// chips and the "same batch" hint without the full recipe (step 5).
@override final  int? keepsForDays;
@override@JsonKey() final  bool freezable;
@override final  int? freezerDays;
/// The household's curated shortlist flag (the picker's Favorites tab).
@override@JsonKey() final  bool favorite;
/// Honest per-serving macros, or an incomplete marker (step 7.7).
@override final  RecipeMacroSummary? macros;
/// What one batch makes (step 8.6 / D2) — carried on the summary so a
/// picker row can say "makes 1 cup" (or "no yield yet") without loading
/// the whole recipe. See [Recipe.yieldQty].
@override final  double? yieldQty;
@override final  Unit? yieldUnit;
@override final  double? yieldQty2;
@override final  Unit? yieldUnit2;

/// Create a copy of RecipeSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecipeSummaryCopyWith<_RecipeSummary> get copyWith => __$RecipeSummaryCopyWithImpl<_RecipeSummary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecipeSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&(identical(other.favorite, favorite) || other.favorite == favorite)&&(identical(other.macros, macros) || other.macros == macros)&&(identical(other.yieldQty, yieldQty) || other.yieldQty == yieldQty)&&(identical(other.yieldUnit, yieldUnit) || other.yieldUnit == yieldUnit)&&(identical(other.yieldQty2, yieldQty2) || other.yieldQty2 == yieldQty2)&&(identical(other.yieldUnit2, yieldUnit2) || other.yieldUnit2 == yieldUnit2));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,servingsBase,keepsForDays,freezable,freezerDays,favorite,macros,yieldQty,yieldUnit,yieldQty2,yieldUnit2);

@override
String toString() {
  return 'RecipeSummary(id: $id, title: $title, servingsBase: $servingsBase, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, favorite: $favorite, macros: $macros, yieldQty: $yieldQty, yieldUnit: $yieldUnit, yieldQty2: $yieldQty2, yieldUnit2: $yieldUnit2)';
}


}

/// @nodoc
abstract mixin class _$RecipeSummaryCopyWith<$Res> implements $RecipeSummaryCopyWith<$Res> {
  factory _$RecipeSummaryCopyWith(_RecipeSummary value, $Res Function(_RecipeSummary) _then) = __$RecipeSummaryCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, double servingsBase, int? keepsForDays, bool freezable, int? freezerDays, bool favorite, RecipeMacroSummary? macros, double? yieldQty, Unit? yieldUnit, double? yieldQty2, Unit? yieldUnit2
});




}
/// @nodoc
class __$RecipeSummaryCopyWithImpl<$Res>
    implements _$RecipeSummaryCopyWith<$Res> {
  __$RecipeSummaryCopyWithImpl(this._self, this._then);

  final _RecipeSummary _self;
  final $Res Function(_RecipeSummary) _then;

/// Create a copy of RecipeSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? servingsBase = null,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? favorite = null,Object? macros = freezed,Object? yieldQty = freezed,Object? yieldUnit = freezed,Object? yieldQty2 = freezed,Object? yieldUnit2 = freezed,}) {
  return _then(_RecipeSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,favorite: null == favorite ? _self.favorite : favorite // ignore: cast_nullable_to_non_nullable
as bool,macros: freezed == macros ? _self.macros : macros // ignore: cast_nullable_to_non_nullable
as RecipeMacroSummary?,yieldQty: freezed == yieldQty ? _self.yieldQty : yieldQty // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit: freezed == yieldUnit ? _self.yieldUnit : yieldUnit // ignore: cast_nullable_to_non_nullable
as Unit?,yieldQty2: freezed == yieldQty2 ? _self.yieldQty2 : yieldQty2 // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit2: freezed == yieldUnit2 ? _self.yieldUnit2 : yieldUnit2 // ignore: cast_nullable_to_non_nullable
as Unit?,
  ));
}


}

/// @nodoc
mixin _$IngredientGroup {

 String get id; String? get name; List<LineItem> get items;
/// Create a copy of IngredientGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IngredientGroupCopyWith<IngredientGroup> get copyWith => _$IngredientGroupCopyWithImpl<IngredientGroup>(this as IngredientGroup, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IngredientGroup&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.items, items));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,const DeepCollectionEquality().hash(items));

@override
String toString() {
  return 'IngredientGroup(id: $id, name: $name, items: $items)';
}


}

/// @nodoc
abstract mixin class $IngredientGroupCopyWith<$Res>  {
  factory $IngredientGroupCopyWith(IngredientGroup value, $Res Function(IngredientGroup) _then) = _$IngredientGroupCopyWithImpl;
@useResult
$Res call({
 String id, String? name, List<LineItem> items
});




}
/// @nodoc
class _$IngredientGroupCopyWithImpl<$Res>
    implements $IngredientGroupCopyWith<$Res> {
  _$IngredientGroupCopyWithImpl(this._self, this._then);

  final IngredientGroup _self;
  final $Res Function(IngredientGroup) _then;

/// Create a copy of IngredientGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = freezed,Object? items = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<LineItem>,
  ));
}

}


/// Adds pattern-matching-related methods to [IngredientGroup].
extension IngredientGroupPatterns on IngredientGroup {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _IngredientGroup value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _IngredientGroup() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _IngredientGroup value)  $default,){
final _that = this;
switch (_that) {
case _IngredientGroup():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _IngredientGroup value)?  $default,){
final _that = this;
switch (_that) {
case _IngredientGroup() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? name,  List<LineItem> items)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _IngredientGroup() when $default != null:
return $default(_that.id,_that.name,_that.items);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? name,  List<LineItem> items)  $default,) {final _that = this;
switch (_that) {
case _IngredientGroup():
return $default(_that.id,_that.name,_that.items);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? name,  List<LineItem> items)?  $default,) {final _that = this;
switch (_that) {
case _IngredientGroup() when $default != null:
return $default(_that.id,_that.name,_that.items);case _:
  return null;

}
}

}

/// @nodoc


class _IngredientGroup implements IngredientGroup {
  const _IngredientGroup({required this.id, this.name, final  List<LineItem> items = const <LineItem>[]}): _items = items;
  

@override final  String id;
@override final  String? name;
 final  List<LineItem> _items;
@override@JsonKey() List<LineItem> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}


/// Create a copy of IngredientGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IngredientGroupCopyWith<_IngredientGroup> get copyWith => __$IngredientGroupCopyWithImpl<_IngredientGroup>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _IngredientGroup&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._items, _items));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,const DeepCollectionEquality().hash(_items));

@override
String toString() {
  return 'IngredientGroup(id: $id, name: $name, items: $items)';
}


}

/// @nodoc
abstract mixin class _$IngredientGroupCopyWith<$Res> implements $IngredientGroupCopyWith<$Res> {
  factory _$IngredientGroupCopyWith(_IngredientGroup value, $Res Function(_IngredientGroup) _then) = __$IngredientGroupCopyWithImpl;
@override @useResult
$Res call({
 String id, String? name, List<LineItem> items
});




}
/// @nodoc
class __$IngredientGroupCopyWithImpl<$Res>
    implements _$IngredientGroupCopyWith<$Res> {
  __$IngredientGroupCopyWithImpl(this._self, this._then);

  final _IngredientGroup _self;
  final $Res Function(_IngredientGroup) _then;

/// Create a copy of IngredientGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = freezed,Object? items = null,}) {
  return _then(_IngredientGroup(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<LineItem>,
  ));
}


}

/// @nodoc
mixin _$LineItem {

 String get id; String get ingredientName; Unit get unit; String? get ingredientId; String? get subRecipeId; SubRecipeTarget? get subRecipe; double? get quantity; String? get measureId; Measure? get measure; String? get note; bool get optional;
/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LineItemCopyWith<LineItem> get copyWith => _$LineItemCopyWithImpl<LineItem>(this as LineItem, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LineItem&&(identical(other.id, id) || other.id == id)&&(identical(other.ingredientName, ingredientName) || other.ingredientName == ingredientName)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.subRecipeId, subRecipeId) || other.subRecipeId == subRecipeId)&&(identical(other.subRecipe, subRecipe) || other.subRecipe == subRecipe)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.measureId, measureId) || other.measureId == measureId)&&(identical(other.measure, measure) || other.measure == measure)&&(identical(other.note, note) || other.note == note)&&(identical(other.optional, optional) || other.optional == optional));
}


@override
int get hashCode => Object.hash(runtimeType,id,ingredientName,unit,ingredientId,subRecipeId,subRecipe,quantity,measureId,measure,note,optional);

@override
String toString() {
  return 'LineItem(id: $id, ingredientName: $ingredientName, unit: $unit, ingredientId: $ingredientId, subRecipeId: $subRecipeId, subRecipe: $subRecipe, quantity: $quantity, measureId: $measureId, measure: $measure, note: $note, optional: $optional)';
}


}

/// @nodoc
abstract mixin class $LineItemCopyWith<$Res>  {
  factory $LineItemCopyWith(LineItem value, $Res Function(LineItem) _then) = _$LineItemCopyWithImpl;
@useResult
$Res call({
 String id, String ingredientName, Unit unit, String? ingredientId, String? subRecipeId, SubRecipeTarget? subRecipe, double? quantity, String? measureId, Measure? measure, String? note, bool optional
});


$SubRecipeTargetCopyWith<$Res>? get subRecipe;

}
/// @nodoc
class _$LineItemCopyWithImpl<$Res>
    implements $LineItemCopyWith<$Res> {
  _$LineItemCopyWithImpl(this._self, this._then);

  final LineItem _self;
  final $Res Function(LineItem) _then;

/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? ingredientName = null,Object? unit = null,Object? ingredientId = freezed,Object? subRecipeId = freezed,Object? subRecipe = freezed,Object? quantity = freezed,Object? measureId = freezed,Object? measure = freezed,Object? note = freezed,Object? optional = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ingredientName: null == ingredientName ? _self.ingredientName : ingredientName // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,subRecipeId: freezed == subRecipeId ? _self.subRecipeId : subRecipeId // ignore: cast_nullable_to_non_nullable
as String?,subRecipe: freezed == subRecipe ? _self.subRecipe : subRecipe // ignore: cast_nullable_to_non_nullable
as SubRecipeTarget?,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,measureId: freezed == measureId ? _self.measureId : measureId // ignore: cast_nullable_to_non_nullable
as String?,measure: freezed == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as Measure?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,optional: null == optional ? _self.optional : optional // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SubRecipeTargetCopyWith<$Res>? get subRecipe {
    if (_self.subRecipe == null) {
    return null;
  }

  return $SubRecipeTargetCopyWith<$Res>(_self.subRecipe!, (value) {
    return _then(_self.copyWith(subRecipe: value));
  });
}
}


/// Adds pattern-matching-related methods to [LineItem].
extension LineItemPatterns on LineItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LineItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LineItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LineItem value)  $default,){
final _that = this;
switch (_that) {
case _LineItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LineItem value)?  $default,){
final _that = this;
switch (_that) {
case _LineItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String ingredientName,  Unit unit,  String? ingredientId,  String? subRecipeId,  SubRecipeTarget? subRecipe,  double? quantity,  String? measureId,  Measure? measure,  String? note,  bool optional)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LineItem() when $default != null:
return $default(_that.id,_that.ingredientName,_that.unit,_that.ingredientId,_that.subRecipeId,_that.subRecipe,_that.quantity,_that.measureId,_that.measure,_that.note,_that.optional);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String ingredientName,  Unit unit,  String? ingredientId,  String? subRecipeId,  SubRecipeTarget? subRecipe,  double? quantity,  String? measureId,  Measure? measure,  String? note,  bool optional)  $default,) {final _that = this;
switch (_that) {
case _LineItem():
return $default(_that.id,_that.ingredientName,_that.unit,_that.ingredientId,_that.subRecipeId,_that.subRecipe,_that.quantity,_that.measureId,_that.measure,_that.note,_that.optional);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String ingredientName,  Unit unit,  String? ingredientId,  String? subRecipeId,  SubRecipeTarget? subRecipe,  double? quantity,  String? measureId,  Measure? measure,  String? note,  bool optional)?  $default,) {final _that = this;
switch (_that) {
case _LineItem() when $default != null:
return $default(_that.id,_that.ingredientName,_that.unit,_that.ingredientId,_that.subRecipeId,_that.subRecipe,_that.quantity,_that.measureId,_that.measure,_that.note,_that.optional);case _:
  return null;

}
}

}

/// @nodoc


class _LineItem extends LineItem {
  const _LineItem({required this.id, required this.ingredientName, required this.unit, this.ingredientId, this.subRecipeId, this.subRecipe, this.quantity, this.measureId, this.measure, this.note, this.optional = false}): super._();
  

@override final  String id;
@override final  String ingredientName;
@override final  Unit unit;
@override final  String? ingredientId;
@override final  String? subRecipeId;
@override final  SubRecipeTarget? subRecipe;
@override final  double? quantity;
@override final  String? measureId;
@override final  Measure? measure;
@override final  String? note;
@override@JsonKey() final  bool optional;

/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LineItemCopyWith<_LineItem> get copyWith => __$LineItemCopyWithImpl<_LineItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LineItem&&(identical(other.id, id) || other.id == id)&&(identical(other.ingredientName, ingredientName) || other.ingredientName == ingredientName)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.subRecipeId, subRecipeId) || other.subRecipeId == subRecipeId)&&(identical(other.subRecipe, subRecipe) || other.subRecipe == subRecipe)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.measureId, measureId) || other.measureId == measureId)&&(identical(other.measure, measure) || other.measure == measure)&&(identical(other.note, note) || other.note == note)&&(identical(other.optional, optional) || other.optional == optional));
}


@override
int get hashCode => Object.hash(runtimeType,id,ingredientName,unit,ingredientId,subRecipeId,subRecipe,quantity,measureId,measure,note,optional);

@override
String toString() {
  return 'LineItem(id: $id, ingredientName: $ingredientName, unit: $unit, ingredientId: $ingredientId, subRecipeId: $subRecipeId, subRecipe: $subRecipe, quantity: $quantity, measureId: $measureId, measure: $measure, note: $note, optional: $optional)';
}


}

/// @nodoc
abstract mixin class _$LineItemCopyWith<$Res> implements $LineItemCopyWith<$Res> {
  factory _$LineItemCopyWith(_LineItem value, $Res Function(_LineItem) _then) = __$LineItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String ingredientName, Unit unit, String? ingredientId, String? subRecipeId, SubRecipeTarget? subRecipe, double? quantity, String? measureId, Measure? measure, String? note, bool optional
});


@override $SubRecipeTargetCopyWith<$Res>? get subRecipe;

}
/// @nodoc
class __$LineItemCopyWithImpl<$Res>
    implements _$LineItemCopyWith<$Res> {
  __$LineItemCopyWithImpl(this._self, this._then);

  final _LineItem _self;
  final $Res Function(_LineItem) _then;

/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? ingredientName = null,Object? unit = null,Object? ingredientId = freezed,Object? subRecipeId = freezed,Object? subRecipe = freezed,Object? quantity = freezed,Object? measureId = freezed,Object? measure = freezed,Object? note = freezed,Object? optional = null,}) {
  return _then(_LineItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,ingredientName: null == ingredientName ? _self.ingredientName : ingredientName // ignore: cast_nullable_to_non_nullable
as String,unit: null == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as Unit,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,subRecipeId: freezed == subRecipeId ? _self.subRecipeId : subRecipeId // ignore: cast_nullable_to_non_nullable
as String?,subRecipe: freezed == subRecipe ? _self.subRecipe : subRecipe // ignore: cast_nullable_to_non_nullable
as SubRecipeTarget?,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,measureId: freezed == measureId ? _self.measureId : measureId // ignore: cast_nullable_to_non_nullable
as String?,measure: freezed == measure ? _self.measure : measure // ignore: cast_nullable_to_non_nullable
as Measure?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,optional: null == optional ? _self.optional : optional // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of LineItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SubRecipeTargetCopyWith<$Res>? get subRecipe {
    if (_self.subRecipe == null) {
    return null;
  }

  return $SubRecipeTargetCopyWith<$Res>(_self.subRecipe!, (value) {
    return _then(_self.copyWith(subRecipe: value));
  });
}
}

/// @nodoc
mixin _$SubRecipeTarget {

 String get id; String get title; double? get yieldQty; Unit? get yieldUnit; double? get yieldQty2; Unit? get yieldUnit2;
/// Create a copy of SubRecipeTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubRecipeTargetCopyWith<SubRecipeTarget> get copyWith => _$SubRecipeTargetCopyWithImpl<SubRecipeTarget>(this as SubRecipeTarget, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubRecipeTarget&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.yieldQty, yieldQty) || other.yieldQty == yieldQty)&&(identical(other.yieldUnit, yieldUnit) || other.yieldUnit == yieldUnit)&&(identical(other.yieldQty2, yieldQty2) || other.yieldQty2 == yieldQty2)&&(identical(other.yieldUnit2, yieldUnit2) || other.yieldUnit2 == yieldUnit2));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,yieldQty,yieldUnit,yieldQty2,yieldUnit2);

@override
String toString() {
  return 'SubRecipeTarget(id: $id, title: $title, yieldQty: $yieldQty, yieldUnit: $yieldUnit, yieldQty2: $yieldQty2, yieldUnit2: $yieldUnit2)';
}


}

/// @nodoc
abstract mixin class $SubRecipeTargetCopyWith<$Res>  {
  factory $SubRecipeTargetCopyWith(SubRecipeTarget value, $Res Function(SubRecipeTarget) _then) = _$SubRecipeTargetCopyWithImpl;
@useResult
$Res call({
 String id, String title, double? yieldQty, Unit? yieldUnit, double? yieldQty2, Unit? yieldUnit2
});




}
/// @nodoc
class _$SubRecipeTargetCopyWithImpl<$Res>
    implements $SubRecipeTargetCopyWith<$Res> {
  _$SubRecipeTargetCopyWithImpl(this._self, this._then);

  final SubRecipeTarget _self;
  final $Res Function(SubRecipeTarget) _then;

/// Create a copy of SubRecipeTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? yieldQty = freezed,Object? yieldUnit = freezed,Object? yieldQty2 = freezed,Object? yieldUnit2 = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,yieldQty: freezed == yieldQty ? _self.yieldQty : yieldQty // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit: freezed == yieldUnit ? _self.yieldUnit : yieldUnit // ignore: cast_nullable_to_non_nullable
as Unit?,yieldQty2: freezed == yieldQty2 ? _self.yieldQty2 : yieldQty2 // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit2: freezed == yieldUnit2 ? _self.yieldUnit2 : yieldUnit2 // ignore: cast_nullable_to_non_nullable
as Unit?,
  ));
}

}


/// Adds pattern-matching-related methods to [SubRecipeTarget].
extension SubRecipeTargetPatterns on SubRecipeTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubRecipeTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubRecipeTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubRecipeTarget value)  $default,){
final _that = this;
switch (_that) {
case _SubRecipeTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubRecipeTarget value)?  $default,){
final _that = this;
switch (_that) {
case _SubRecipeTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubRecipeTarget() when $default != null:
return $default(_that.id,_that.title,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2)  $default,) {final _that = this;
switch (_that) {
case _SubRecipeTarget():
return $default(_that.id,_that.title,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2)?  $default,) {final _that = this;
switch (_that) {
case _SubRecipeTarget() when $default != null:
return $default(_that.id,_that.title,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2);case _:
  return null;

}
}

}

/// @nodoc


class _SubRecipeTarget extends SubRecipeTarget {
  const _SubRecipeTarget({required this.id, required this.title, this.yieldQty, this.yieldUnit, this.yieldQty2, this.yieldUnit2}): super._();
  

@override final  String id;
@override final  String title;
@override final  double? yieldQty;
@override final  Unit? yieldUnit;
@override final  double? yieldQty2;
@override final  Unit? yieldUnit2;

/// Create a copy of SubRecipeTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubRecipeTargetCopyWith<_SubRecipeTarget> get copyWith => __$SubRecipeTargetCopyWithImpl<_SubRecipeTarget>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubRecipeTarget&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.yieldQty, yieldQty) || other.yieldQty == yieldQty)&&(identical(other.yieldUnit, yieldUnit) || other.yieldUnit == yieldUnit)&&(identical(other.yieldQty2, yieldQty2) || other.yieldQty2 == yieldQty2)&&(identical(other.yieldUnit2, yieldUnit2) || other.yieldUnit2 == yieldUnit2));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,yieldQty,yieldUnit,yieldQty2,yieldUnit2);

@override
String toString() {
  return 'SubRecipeTarget(id: $id, title: $title, yieldQty: $yieldQty, yieldUnit: $yieldUnit, yieldQty2: $yieldQty2, yieldUnit2: $yieldUnit2)';
}


}

/// @nodoc
abstract mixin class _$SubRecipeTargetCopyWith<$Res> implements $SubRecipeTargetCopyWith<$Res> {
  factory _$SubRecipeTargetCopyWith(_SubRecipeTarget value, $Res Function(_SubRecipeTarget) _then) = __$SubRecipeTargetCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, double? yieldQty, Unit? yieldUnit, double? yieldQty2, Unit? yieldUnit2
});




}
/// @nodoc
class __$SubRecipeTargetCopyWithImpl<$Res>
    implements _$SubRecipeTargetCopyWith<$Res> {
  __$SubRecipeTargetCopyWithImpl(this._self, this._then);

  final _SubRecipeTarget _self;
  final $Res Function(_SubRecipeTarget) _then;

/// Create a copy of SubRecipeTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? yieldQty = freezed,Object? yieldUnit = freezed,Object? yieldQty2 = freezed,Object? yieldUnit2 = freezed,}) {
  return _then(_SubRecipeTarget(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,yieldQty: freezed == yieldQty ? _self.yieldQty : yieldQty // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit: freezed == yieldUnit ? _self.yieldUnit : yieldUnit // ignore: cast_nullable_to_non_nullable
as Unit?,yieldQty2: freezed == yieldQty2 ? _self.yieldQty2 : yieldQty2 // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit2: freezed == yieldUnit2 ? _self.yieldUnit2 : yieldUnit2 // ignore: cast_nullable_to_non_nullable
as Unit?,
  ));
}


}

// dart format on
