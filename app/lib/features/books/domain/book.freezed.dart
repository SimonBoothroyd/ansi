// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'book.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Book {

 String get id; String get name;/// Ordered, user-named sections. Empty sections are kept.
 List<BookSection> get sections;/// Recipes in this book with no `section_id` (or a deleted section). Not
/// a database row.
 List<RecipeSummary> get unsectioned;
/// Create a copy of Book
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookCopyWith<Book> get copyWith => _$BookCopyWithImpl<Book>(this as Book, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Book&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.sections, sections)&&const DeepCollectionEquality().equals(other.unsectioned, unsectioned));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,const DeepCollectionEquality().hash(sections),const DeepCollectionEquality().hash(unsectioned));

@override
String toString() {
  return 'Book(id: $id, name: $name, sections: $sections, unsectioned: $unsectioned)';
}


}

/// @nodoc
abstract mixin class $BookCopyWith<$Res>  {
  factory $BookCopyWith(Book value, $Res Function(Book) _then) = _$BookCopyWithImpl;
@useResult
$Res call({
 String id, String name, List<BookSection> sections, List<RecipeSummary> unsectioned
});




}
/// @nodoc
class _$BookCopyWithImpl<$Res>
    implements $BookCopyWith<$Res> {
  _$BookCopyWithImpl(this._self, this._then);

  final Book _self;
  final $Res Function(Book) _then;

/// Create a copy of Book
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? sections = null,Object? unsectioned = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sections: null == sections ? _self.sections : sections // ignore: cast_nullable_to_non_nullable
as List<BookSection>,unsectioned: null == unsectioned ? _self.unsectioned : unsectioned // ignore: cast_nullable_to_non_nullable
as List<RecipeSummary>,
  ));
}

}


/// Adds pattern-matching-related methods to [Book].
extension BookPatterns on Book {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Book value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Book() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Book value)  $default,){
final _that = this;
switch (_that) {
case _Book():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Book value)?  $default,){
final _that = this;
switch (_that) {
case _Book() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  List<BookSection> sections,  List<RecipeSummary> unsectioned)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Book() when $default != null:
return $default(_that.id,_that.name,_that.sections,_that.unsectioned);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  List<BookSection> sections,  List<RecipeSummary> unsectioned)  $default,) {final _that = this;
switch (_that) {
case _Book():
return $default(_that.id,_that.name,_that.sections,_that.unsectioned);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  List<BookSection> sections,  List<RecipeSummary> unsectioned)?  $default,) {final _that = this;
switch (_that) {
case _Book() when $default != null:
return $default(_that.id,_that.name,_that.sections,_that.unsectioned);case _:
  return null;

}
}

}

/// @nodoc


class _Book implements Book {
  const _Book({required this.id, required this.name, final  List<BookSection> sections = const <BookSection>[], final  List<RecipeSummary> unsectioned = const <RecipeSummary>[]}): _sections = sections,_unsectioned = unsectioned;
  

@override final  String id;
@override final  String name;
/// Ordered, user-named sections. Empty sections are kept.
 final  List<BookSection> _sections;
/// Ordered, user-named sections. Empty sections are kept.
@override@JsonKey() List<BookSection> get sections {
  if (_sections is EqualUnmodifiableListView) return _sections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_sections);
}

/// Recipes in this book with no `section_id` (or a deleted section). Not
/// a database row.
 final  List<RecipeSummary> _unsectioned;
/// Recipes in this book with no `section_id` (or a deleted section). Not
/// a database row.
@override@JsonKey() List<RecipeSummary> get unsectioned {
  if (_unsectioned is EqualUnmodifiableListView) return _unsectioned;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_unsectioned);
}


/// Create a copy of Book
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookCopyWith<_Book> get copyWith => __$BookCopyWithImpl<_Book>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Book&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._sections, _sections)&&const DeepCollectionEquality().equals(other._unsectioned, _unsectioned));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,const DeepCollectionEquality().hash(_sections),const DeepCollectionEquality().hash(_unsectioned));

@override
String toString() {
  return 'Book(id: $id, name: $name, sections: $sections, unsectioned: $unsectioned)';
}


}

/// @nodoc
abstract mixin class _$BookCopyWith<$Res> implements $BookCopyWith<$Res> {
  factory _$BookCopyWith(_Book value, $Res Function(_Book) _then) = __$BookCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, List<BookSection> sections, List<RecipeSummary> unsectioned
});




}
/// @nodoc
class __$BookCopyWithImpl<$Res>
    implements _$BookCopyWith<$Res> {
  __$BookCopyWithImpl(this._self, this._then);

  final _Book _self;
  final $Res Function(_Book) _then;

/// Create a copy of Book
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? sections = null,Object? unsectioned = null,}) {
  return _then(_Book(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sections: null == sections ? _self._sections : sections // ignore: cast_nullable_to_non_nullable
as List<BookSection>,unsectioned: null == unsectioned ? _self._unsectioned : unsectioned // ignore: cast_nullable_to_non_nullable
as List<RecipeSummary>,
  ));
}


}

/// @nodoc
mixin _$BookSection {

 String get id; String get name; List<RecipeSummary> get recipes;
/// Create a copy of BookSection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookSectionCopyWith<BookSection> get copyWith => _$BookSectionCopyWithImpl<BookSection>(this as BookSection, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BookSection&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.recipes, recipes));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,const DeepCollectionEquality().hash(recipes));

@override
String toString() {
  return 'BookSection(id: $id, name: $name, recipes: $recipes)';
}


}

/// @nodoc
abstract mixin class $BookSectionCopyWith<$Res>  {
  factory $BookSectionCopyWith(BookSection value, $Res Function(BookSection) _then) = _$BookSectionCopyWithImpl;
@useResult
$Res call({
 String id, String name, List<RecipeSummary> recipes
});




}
/// @nodoc
class _$BookSectionCopyWithImpl<$Res>
    implements $BookSectionCopyWith<$Res> {
  _$BookSectionCopyWithImpl(this._self, this._then);

  final BookSection _self;
  final $Res Function(BookSection) _then;

/// Create a copy of BookSection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? recipes = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,recipes: null == recipes ? _self.recipes : recipes // ignore: cast_nullable_to_non_nullable
as List<RecipeSummary>,
  ));
}

}


/// Adds pattern-matching-related methods to [BookSection].
extension BookSectionPatterns on BookSection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BookSection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BookSection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BookSection value)  $default,){
final _that = this;
switch (_that) {
case _BookSection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BookSection value)?  $default,){
final _that = this;
switch (_that) {
case _BookSection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  List<RecipeSummary> recipes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BookSection() when $default != null:
return $default(_that.id,_that.name,_that.recipes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  List<RecipeSummary> recipes)  $default,) {final _that = this;
switch (_that) {
case _BookSection():
return $default(_that.id,_that.name,_that.recipes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  List<RecipeSummary> recipes)?  $default,) {final _that = this;
switch (_that) {
case _BookSection() when $default != null:
return $default(_that.id,_that.name,_that.recipes);case _:
  return null;

}
}

}

/// @nodoc


class _BookSection implements BookSection {
  const _BookSection({required this.id, required this.name, final  List<RecipeSummary> recipes = const <RecipeSummary>[]}): _recipes = recipes;
  

@override final  String id;
@override final  String name;
 final  List<RecipeSummary> _recipes;
@override@JsonKey() List<RecipeSummary> get recipes {
  if (_recipes is EqualUnmodifiableListView) return _recipes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recipes);
}


/// Create a copy of BookSection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookSectionCopyWith<_BookSection> get copyWith => __$BookSectionCopyWithImpl<_BookSection>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BookSection&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._recipes, _recipes));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,const DeepCollectionEquality().hash(_recipes));

@override
String toString() {
  return 'BookSection(id: $id, name: $name, recipes: $recipes)';
}


}

/// @nodoc
abstract mixin class _$BookSectionCopyWith<$Res> implements $BookSectionCopyWith<$Res> {
  factory _$BookSectionCopyWith(_BookSection value, $Res Function(_BookSection) _then) = __$BookSectionCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, List<RecipeSummary> recipes
});




}
/// @nodoc
class __$BookSectionCopyWithImpl<$Res>
    implements _$BookSectionCopyWith<$Res> {
  __$BookSectionCopyWithImpl(this._self, this._then);

  final _BookSection _self;
  final $Res Function(_BookSection) _then;

/// Create a copy of BookSection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? recipes = null,}) {
  return _then(_BookSection(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,recipes: null == recipes ? _self._recipes : recipes // ignore: cast_nullable_to_non_nullable
as List<RecipeSummary>,
  ));
}


}

// dart format on
