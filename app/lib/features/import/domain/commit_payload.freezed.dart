// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'commit_payload.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CommitStub {

 String get key; String get name;
/// Create a copy of CommitStub
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommitStubCopyWith<CommitStub> get copyWith => _$CommitStubCopyWithImpl<CommitStub>(this as CommitStub, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommitStub&&(identical(other.key, key) || other.key == key)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,key,name);

@override
String toString() {
  return 'CommitStub(key: $key, name: $name)';
}


}

/// @nodoc
abstract mixin class $CommitStubCopyWith<$Res>  {
  factory $CommitStubCopyWith(CommitStub value, $Res Function(CommitStub) _then) = _$CommitStubCopyWithImpl;
@useResult
$Res call({
 String key, String name
});




}
/// @nodoc
class _$CommitStubCopyWithImpl<$Res>
    implements $CommitStubCopyWith<$Res> {
  _$CommitStubCopyWithImpl(this._self, this._then);

  final CommitStub _self;
  final $Res Function(CommitStub) _then;

/// Create a copy of CommitStub
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? name = null,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CommitStub].
extension CommitStubPatterns on CommitStub {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CommitStub value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CommitStub() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CommitStub value)  $default,){
final _that = this;
switch (_that) {
case _CommitStub():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CommitStub value)?  $default,){
final _that = this;
switch (_that) {
case _CommitStub() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  String name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CommitStub() when $default != null:
return $default(_that.key,_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  String name)  $default,) {final _that = this;
switch (_that) {
case _CommitStub():
return $default(_that.key,_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  String name)?  $default,) {final _that = this;
switch (_that) {
case _CommitStub() when $default != null:
return $default(_that.key,_that.name);case _:
  return null;

}
}

}

/// @nodoc


class _CommitStub implements CommitStub {
  const _CommitStub({required this.key, required this.name});
  

@override final  String key;
@override final  String name;

/// Create a copy of CommitStub
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CommitStubCopyWith<_CommitStub> get copyWith => __$CommitStubCopyWithImpl<_CommitStub>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CommitStub&&(identical(other.key, key) || other.key == key)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,key,name);

@override
String toString() {
  return 'CommitStub(key: $key, name: $name)';
}


}

/// @nodoc
abstract mixin class _$CommitStubCopyWith<$Res> implements $CommitStubCopyWith<$Res> {
  factory _$CommitStubCopyWith(_CommitStub value, $Res Function(_CommitStub) _then) = __$CommitStubCopyWithImpl;
@override @useResult
$Res call({
 String key, String name
});




}
/// @nodoc
class __$CommitStubCopyWithImpl<$Res>
    implements _$CommitStubCopyWith<$Res> {
  __$CommitStubCopyWithImpl(this._self, this._then);

  final _CommitStub _self;
  final $Res Function(_CommitStub) _then;

/// Create a copy of CommitStub
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? name = null,}) {
  return _then(_CommitStub(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$CommitLine {

/// The flattened line index — its position in the commit's line order and
/// the value step tokens ref before the remap.
 int get lineIndex; String? get ingredientId; String? get stubKey;/// The household recipe this line was LINKED to at review (8.6 / D6). When
/// it is set the line is a COMPONENT line and the other two identities are
/// null; the repository writes no `measure_id` for it either (measures are
/// an ingredient concept, and migration 0017 pins both rules).
 String? get subRecipeId; double? get quantity; String? get unit; String? get note;
/// Create a copy of CommitLine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommitLineCopyWith<CommitLine> get copyWith => _$CommitLineCopyWithImpl<CommitLine>(this as CommitLine, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommitLine&&(identical(other.lineIndex, lineIndex) || other.lineIndex == lineIndex)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.stubKey, stubKey) || other.stubKey == stubKey)&&(identical(other.subRecipeId, subRecipeId) || other.subRecipeId == subRecipeId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.note, note) || other.note == note));
}


@override
int get hashCode => Object.hash(runtimeType,lineIndex,ingredientId,stubKey,subRecipeId,quantity,unit,note);

@override
String toString() {
  return 'CommitLine(lineIndex: $lineIndex, ingredientId: $ingredientId, stubKey: $stubKey, subRecipeId: $subRecipeId, quantity: $quantity, unit: $unit, note: $note)';
}


}

/// @nodoc
abstract mixin class $CommitLineCopyWith<$Res>  {
  factory $CommitLineCopyWith(CommitLine value, $Res Function(CommitLine) _then) = _$CommitLineCopyWithImpl;
@useResult
$Res call({
 int lineIndex, String? ingredientId, String? stubKey, String? subRecipeId, double? quantity, String? unit, String? note
});




}
/// @nodoc
class _$CommitLineCopyWithImpl<$Res>
    implements $CommitLineCopyWith<$Res> {
  _$CommitLineCopyWithImpl(this._self, this._then);

  final CommitLine _self;
  final $Res Function(CommitLine) _then;

/// Create a copy of CommitLine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lineIndex = null,Object? ingredientId = freezed,Object? stubKey = freezed,Object? subRecipeId = freezed,Object? quantity = freezed,Object? unit = freezed,Object? note = freezed,}) {
  return _then(_self.copyWith(
lineIndex: null == lineIndex ? _self.lineIndex : lineIndex // ignore: cast_nullable_to_non_nullable
as int,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,stubKey: freezed == stubKey ? _self.stubKey : stubKey // ignore: cast_nullable_to_non_nullable
as String?,subRecipeId: freezed == subRecipeId ? _self.subRecipeId : subRecipeId // ignore: cast_nullable_to_non_nullable
as String?,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [CommitLine].
extension CommitLinePatterns on CommitLine {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CommitLine value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CommitLine() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CommitLine value)  $default,){
final _that = this;
switch (_that) {
case _CommitLine():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CommitLine value)?  $default,){
final _that = this;
switch (_that) {
case _CommitLine() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int lineIndex,  String? ingredientId,  String? stubKey,  String? subRecipeId,  double? quantity,  String? unit,  String? note)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CommitLine() when $default != null:
return $default(_that.lineIndex,_that.ingredientId,_that.stubKey,_that.subRecipeId,_that.quantity,_that.unit,_that.note);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int lineIndex,  String? ingredientId,  String? stubKey,  String? subRecipeId,  double? quantity,  String? unit,  String? note)  $default,) {final _that = this;
switch (_that) {
case _CommitLine():
return $default(_that.lineIndex,_that.ingredientId,_that.stubKey,_that.subRecipeId,_that.quantity,_that.unit,_that.note);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int lineIndex,  String? ingredientId,  String? stubKey,  String? subRecipeId,  double? quantity,  String? unit,  String? note)?  $default,) {final _that = this;
switch (_that) {
case _CommitLine() when $default != null:
return $default(_that.lineIndex,_that.ingredientId,_that.stubKey,_that.subRecipeId,_that.quantity,_that.unit,_that.note);case _:
  return null;

}
}

}

/// @nodoc


class _CommitLine implements CommitLine {
  const _CommitLine({required this.lineIndex, this.ingredientId, this.stubKey, this.subRecipeId, this.quantity, this.unit, this.note});
  

/// The flattened line index — its position in the commit's line order and
/// the value step tokens ref before the remap.
@override final  int lineIndex;
@override final  String? ingredientId;
@override final  String? stubKey;
/// The household recipe this line was LINKED to at review (8.6 / D6). When
/// it is set the line is a COMPONENT line and the other two identities are
/// null; the repository writes no `measure_id` for it either (measures are
/// an ingredient concept, and migration 0017 pins both rules).
@override final  String? subRecipeId;
@override final  double? quantity;
@override final  String? unit;
@override final  String? note;

/// Create a copy of CommitLine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CommitLineCopyWith<_CommitLine> get copyWith => __$CommitLineCopyWithImpl<_CommitLine>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CommitLine&&(identical(other.lineIndex, lineIndex) || other.lineIndex == lineIndex)&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.stubKey, stubKey) || other.stubKey == stubKey)&&(identical(other.subRecipeId, subRecipeId) || other.subRecipeId == subRecipeId)&&(identical(other.quantity, quantity) || other.quantity == quantity)&&(identical(other.unit, unit) || other.unit == unit)&&(identical(other.note, note) || other.note == note));
}


@override
int get hashCode => Object.hash(runtimeType,lineIndex,ingredientId,stubKey,subRecipeId,quantity,unit,note);

@override
String toString() {
  return 'CommitLine(lineIndex: $lineIndex, ingredientId: $ingredientId, stubKey: $stubKey, subRecipeId: $subRecipeId, quantity: $quantity, unit: $unit, note: $note)';
}


}

/// @nodoc
abstract mixin class _$CommitLineCopyWith<$Res> implements $CommitLineCopyWith<$Res> {
  factory _$CommitLineCopyWith(_CommitLine value, $Res Function(_CommitLine) _then) = __$CommitLineCopyWithImpl;
@override @useResult
$Res call({
 int lineIndex, String? ingredientId, String? stubKey, String? subRecipeId, double? quantity, String? unit, String? note
});




}
/// @nodoc
class __$CommitLineCopyWithImpl<$Res>
    implements _$CommitLineCopyWith<$Res> {
  __$CommitLineCopyWithImpl(this._self, this._then);

  final _CommitLine _self;
  final $Res Function(_CommitLine) _then;

/// Create a copy of CommitLine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? lineIndex = null,Object? ingredientId = freezed,Object? stubKey = freezed,Object? subRecipeId = freezed,Object? quantity = freezed,Object? unit = freezed,Object? note = freezed,}) {
  return _then(_CommitLine(
lineIndex: null == lineIndex ? _self.lineIndex : lineIndex // ignore: cast_nullable_to_non_nullable
as int,ingredientId: freezed == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String?,stubKey: freezed == stubKey ? _self.stubKey : stubKey // ignore: cast_nullable_to_non_nullable
as String?,subRecipeId: freezed == subRecipeId ? _self.subRecipeId : subRecipeId // ignore: cast_nullable_to_non_nullable
as String?,quantity: freezed == quantity ? _self.quantity : quantity // ignore: cast_nullable_to_non_nullable
as double?,unit: freezed == unit ? _self.unit : unit // ignore: cast_nullable_to_non_nullable
as String?,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$CommitGroup {

 String? get name; List<CommitLine> get lines;
/// Create a copy of CommitGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommitGroupCopyWith<CommitGroup> get copyWith => _$CommitGroupCopyWithImpl<CommitGroup>(this as CommitGroup, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommitGroup&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.lines, lines));
}


@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(lines));

@override
String toString() {
  return 'CommitGroup(name: $name, lines: $lines)';
}


}

/// @nodoc
abstract mixin class $CommitGroupCopyWith<$Res>  {
  factory $CommitGroupCopyWith(CommitGroup value, $Res Function(CommitGroup) _then) = _$CommitGroupCopyWithImpl;
@useResult
$Res call({
 String? name, List<CommitLine> lines
});




}
/// @nodoc
class _$CommitGroupCopyWithImpl<$Res>
    implements $CommitGroupCopyWith<$Res> {
  _$CommitGroupCopyWithImpl(this._self, this._then);

  final CommitGroup _self;
  final $Res Function(CommitGroup) _then;

/// Create a copy of CommitGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = freezed,Object? lines = null,}) {
  return _then(_self.copyWith(
name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,lines: null == lines ? _self.lines : lines // ignore: cast_nullable_to_non_nullable
as List<CommitLine>,
  ));
}

}


/// Adds pattern-matching-related methods to [CommitGroup].
extension CommitGroupPatterns on CommitGroup {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CommitGroup value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CommitGroup() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CommitGroup value)  $default,){
final _that = this;
switch (_that) {
case _CommitGroup():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CommitGroup value)?  $default,){
final _that = this;
switch (_that) {
case _CommitGroup() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? name,  List<CommitLine> lines)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CommitGroup() when $default != null:
return $default(_that.name,_that.lines);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? name,  List<CommitLine> lines)  $default,) {final _that = this;
switch (_that) {
case _CommitGroup():
return $default(_that.name,_that.lines);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? name,  List<CommitLine> lines)?  $default,) {final _that = this;
switch (_that) {
case _CommitGroup() when $default != null:
return $default(_that.name,_that.lines);case _:
  return null;

}
}

}

/// @nodoc


class _CommitGroup implements CommitGroup {
  const _CommitGroup({this.name, final  List<CommitLine> lines = const <CommitLine>[]}): _lines = lines;
  

@override final  String? name;
 final  List<CommitLine> _lines;
@override@JsonKey() List<CommitLine> get lines {
  if (_lines is EqualUnmodifiableListView) return _lines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_lines);
}


/// Create a copy of CommitGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CommitGroupCopyWith<_CommitGroup> get copyWith => __$CommitGroupCopyWithImpl<_CommitGroup>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CommitGroup&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._lines, _lines));
}


@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(_lines));

@override
String toString() {
  return 'CommitGroup(name: $name, lines: $lines)';
}


}

/// @nodoc
abstract mixin class _$CommitGroupCopyWith<$Res> implements $CommitGroupCopyWith<$Res> {
  factory _$CommitGroupCopyWith(_CommitGroup value, $Res Function(_CommitGroup) _then) = __$CommitGroupCopyWithImpl;
@override @useResult
$Res call({
 String? name, List<CommitLine> lines
});




}
/// @nodoc
class __$CommitGroupCopyWithImpl<$Res>
    implements _$CommitGroupCopyWith<$Res> {
  __$CommitGroupCopyWithImpl(this._self, this._then);

  final _CommitGroup _self;
  final $Res Function(_CommitGroup) _then;

/// Create a copy of CommitGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = freezed,Object? lines = null,}) {
  return _then(_CommitGroup(
name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,lines: null == lines ? _self._lines : lines // ignore: cast_nullable_to_non_nullable
as List<CommitLine>,
  ));
}


}

/// @nodoc
mixin _$CommitCorrection {

 String get ingredientId; String get aliasText;
/// Create a copy of CommitCorrection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommitCorrectionCopyWith<CommitCorrection> get copyWith => _$CommitCorrectionCopyWithImpl<CommitCorrection>(this as CommitCorrection, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommitCorrection&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.aliasText, aliasText) || other.aliasText == aliasText));
}


@override
int get hashCode => Object.hash(runtimeType,ingredientId,aliasText);

@override
String toString() {
  return 'CommitCorrection(ingredientId: $ingredientId, aliasText: $aliasText)';
}


}

/// @nodoc
abstract mixin class $CommitCorrectionCopyWith<$Res>  {
  factory $CommitCorrectionCopyWith(CommitCorrection value, $Res Function(CommitCorrection) _then) = _$CommitCorrectionCopyWithImpl;
@useResult
$Res call({
 String ingredientId, String aliasText
});




}
/// @nodoc
class _$CommitCorrectionCopyWithImpl<$Res>
    implements $CommitCorrectionCopyWith<$Res> {
  _$CommitCorrectionCopyWithImpl(this._self, this._then);

  final CommitCorrection _self;
  final $Res Function(CommitCorrection) _then;

/// Create a copy of CommitCorrection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ingredientId = null,Object? aliasText = null,}) {
  return _then(_self.copyWith(
ingredientId: null == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String,aliasText: null == aliasText ? _self.aliasText : aliasText // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [CommitCorrection].
extension CommitCorrectionPatterns on CommitCorrection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CommitCorrection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CommitCorrection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CommitCorrection value)  $default,){
final _that = this;
switch (_that) {
case _CommitCorrection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CommitCorrection value)?  $default,){
final _that = this;
switch (_that) {
case _CommitCorrection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String ingredientId,  String aliasText)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CommitCorrection() when $default != null:
return $default(_that.ingredientId,_that.aliasText);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String ingredientId,  String aliasText)  $default,) {final _that = this;
switch (_that) {
case _CommitCorrection():
return $default(_that.ingredientId,_that.aliasText);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String ingredientId,  String aliasText)?  $default,) {final _that = this;
switch (_that) {
case _CommitCorrection() when $default != null:
return $default(_that.ingredientId,_that.aliasText);case _:
  return null;

}
}

}

/// @nodoc


class _CommitCorrection implements CommitCorrection {
  const _CommitCorrection({required this.ingredientId, required this.aliasText});
  

@override final  String ingredientId;
@override final  String aliasText;

/// Create a copy of CommitCorrection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CommitCorrectionCopyWith<_CommitCorrection> get copyWith => __$CommitCorrectionCopyWithImpl<_CommitCorrection>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CommitCorrection&&(identical(other.ingredientId, ingredientId) || other.ingredientId == ingredientId)&&(identical(other.aliasText, aliasText) || other.aliasText == aliasText));
}


@override
int get hashCode => Object.hash(runtimeType,ingredientId,aliasText);

@override
String toString() {
  return 'CommitCorrection(ingredientId: $ingredientId, aliasText: $aliasText)';
}


}

/// @nodoc
abstract mixin class _$CommitCorrectionCopyWith<$Res> implements $CommitCorrectionCopyWith<$Res> {
  factory _$CommitCorrectionCopyWith(_CommitCorrection value, $Res Function(_CommitCorrection) _then) = __$CommitCorrectionCopyWithImpl;
@override @useResult
$Res call({
 String ingredientId, String aliasText
});




}
/// @nodoc
class __$CommitCorrectionCopyWithImpl<$Res>
    implements _$CommitCorrectionCopyWith<$Res> {
  __$CommitCorrectionCopyWithImpl(this._self, this._then);

  final _CommitCorrection _self;
  final $Res Function(_CommitCorrection) _then;

/// Create a copy of CommitCorrection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ingredientId = null,Object? aliasText = null,}) {
  return _then(_CommitCorrection(
ingredientId: null == ingredientId ? _self.ingredientId : ingredientId // ignore: cast_nullable_to_non_nullable
as String,aliasText: null == aliasText ? _self.aliasText : aliasText // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$CommitPayload {

 String get title; double get servingsBase; String? get servingsRaw;/// What one batch MAKES, as the review's header states it (8.6 / D2 ·
/// D9, board frame h) — prefilled from `yield_raw` only when that was a
/// plain amount + unit, and otherwise whatever the human typed, or
/// nothing. Both halves or neither: a half-stated yield is half a fact.
/// The SECOND denomination is the editor's affordance, now at review too
/// (plan 0025 #4): the same header form, so the same two slots.
 double? get yieldQty; Unit? get yieldUnit; double? get yieldQty2; Unit? get yieldUnit2; int? get cookTimeSeconds; int? get totalTimeSeconds;/// Shelf life, as the header's SHELF LIFE section states it — unset
/// unless a human set it, because no page prints it.
 int? get keepsForDays; bool get freezable; int? get freezerDays;/// Where the recipe is FILED. Null files into the household's default
/// book at write, exactly where commit has always put an import; the
/// review's draft names that book from the start so FILE UNDER can move
/// it before it lands.
 String? get bookId; String? get sectionId; List<CommitGroup> get groups; List<CommitStub> get stubs; List<Step> get steps; List<CommitCorrection> get corrections;
/// Create a copy of CommitPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommitPayloadCopyWith<CommitPayload> get copyWith => _$CommitPayloadCopyWithImpl<CommitPayload>(this as CommitPayload, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommitPayload&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.servingsRaw, servingsRaw) || other.servingsRaw == servingsRaw)&&(identical(other.yieldQty, yieldQty) || other.yieldQty == yieldQty)&&(identical(other.yieldUnit, yieldUnit) || other.yieldUnit == yieldUnit)&&(identical(other.yieldQty2, yieldQty2) || other.yieldQty2 == yieldQty2)&&(identical(other.yieldUnit2, yieldUnit2) || other.yieldUnit2 == yieldUnit2)&&(identical(other.cookTimeSeconds, cookTimeSeconds) || other.cookTimeSeconds == cookTimeSeconds)&&(identical(other.totalTimeSeconds, totalTimeSeconds) || other.totalTimeSeconds == totalTimeSeconds)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.sectionId, sectionId) || other.sectionId == sectionId)&&const DeepCollectionEquality().equals(other.groups, groups)&&const DeepCollectionEquality().equals(other.stubs, stubs)&&const DeepCollectionEquality().equals(other.steps, steps)&&const DeepCollectionEquality().equals(other.corrections, corrections));
}


@override
int get hashCode => Object.hash(runtimeType,title,servingsBase,servingsRaw,yieldQty,yieldUnit,yieldQty2,yieldUnit2,cookTimeSeconds,totalTimeSeconds,keepsForDays,freezable,freezerDays,bookId,sectionId,const DeepCollectionEquality().hash(groups),const DeepCollectionEquality().hash(stubs),const DeepCollectionEquality().hash(steps),const DeepCollectionEquality().hash(corrections));

@override
String toString() {
  return 'CommitPayload(title: $title, servingsBase: $servingsBase, servingsRaw: $servingsRaw, yieldQty: $yieldQty, yieldUnit: $yieldUnit, yieldQty2: $yieldQty2, yieldUnit2: $yieldUnit2, cookTimeSeconds: $cookTimeSeconds, totalTimeSeconds: $totalTimeSeconds, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, bookId: $bookId, sectionId: $sectionId, groups: $groups, stubs: $stubs, steps: $steps, corrections: $corrections)';
}


}

/// @nodoc
abstract mixin class $CommitPayloadCopyWith<$Res>  {
  factory $CommitPayloadCopyWith(CommitPayload value, $Res Function(CommitPayload) _then) = _$CommitPayloadCopyWithImpl;
@useResult
$Res call({
 String title, double servingsBase, String? servingsRaw, double? yieldQty, Unit? yieldUnit, double? yieldQty2, Unit? yieldUnit2, int? cookTimeSeconds, int? totalTimeSeconds, int? keepsForDays, bool freezable, int? freezerDays, String? bookId, String? sectionId, List<CommitGroup> groups, List<CommitStub> stubs, List<Step> steps, List<CommitCorrection> corrections
});




}
/// @nodoc
class _$CommitPayloadCopyWithImpl<$Res>
    implements $CommitPayloadCopyWith<$Res> {
  _$CommitPayloadCopyWithImpl(this._self, this._then);

  final CommitPayload _self;
  final $Res Function(CommitPayload) _then;

/// Create a copy of CommitPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = null,Object? servingsBase = null,Object? servingsRaw = freezed,Object? yieldQty = freezed,Object? yieldUnit = freezed,Object? yieldQty2 = freezed,Object? yieldUnit2 = freezed,Object? cookTimeSeconds = freezed,Object? totalTimeSeconds = freezed,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? bookId = freezed,Object? sectionId = freezed,Object? groups = null,Object? stubs = null,Object? steps = null,Object? corrections = null,}) {
  return _then(_self.copyWith(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,servingsRaw: freezed == servingsRaw ? _self.servingsRaw : servingsRaw // ignore: cast_nullable_to_non_nullable
as String?,yieldQty: freezed == yieldQty ? _self.yieldQty : yieldQty // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit: freezed == yieldUnit ? _self.yieldUnit : yieldUnit // ignore: cast_nullable_to_non_nullable
as Unit?,yieldQty2: freezed == yieldQty2 ? _self.yieldQty2 : yieldQty2 // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit2: freezed == yieldUnit2 ? _self.yieldUnit2 : yieldUnit2 // ignore: cast_nullable_to_non_nullable
as Unit?,cookTimeSeconds: freezed == cookTimeSeconds ? _self.cookTimeSeconds : cookTimeSeconds // ignore: cast_nullable_to_non_nullable
as int?,totalTimeSeconds: freezed == totalTimeSeconds ? _self.totalTimeSeconds : totalTimeSeconds // ignore: cast_nullable_to_non_nullable
as int?,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,bookId: freezed == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as String?,sectionId: freezed == sectionId ? _self.sectionId : sectionId // ignore: cast_nullable_to_non_nullable
as String?,groups: null == groups ? _self.groups : groups // ignore: cast_nullable_to_non_nullable
as List<CommitGroup>,stubs: null == stubs ? _self.stubs : stubs // ignore: cast_nullable_to_non_nullable
as List<CommitStub>,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<Step>,corrections: null == corrections ? _self.corrections : corrections // ignore: cast_nullable_to_non_nullable
as List<CommitCorrection>,
  ));
}

}


/// Adds pattern-matching-related methods to [CommitPayload].
extension CommitPayloadPatterns on CommitPayload {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CommitPayload value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CommitPayload() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CommitPayload value)  $default,){
final _that = this;
switch (_that) {
case _CommitPayload():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CommitPayload value)?  $default,){
final _that = this;
switch (_that) {
case _CommitPayload() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String title,  double servingsBase,  String? servingsRaw,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2,  int? cookTimeSeconds,  int? totalTimeSeconds,  int? keepsForDays,  bool freezable,  int? freezerDays,  String? bookId,  String? sectionId,  List<CommitGroup> groups,  List<CommitStub> stubs,  List<Step> steps,  List<CommitCorrection> corrections)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CommitPayload() when $default != null:
return $default(_that.title,_that.servingsBase,_that.servingsRaw,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2,_that.cookTimeSeconds,_that.totalTimeSeconds,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.bookId,_that.sectionId,_that.groups,_that.stubs,_that.steps,_that.corrections);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String title,  double servingsBase,  String? servingsRaw,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2,  int? cookTimeSeconds,  int? totalTimeSeconds,  int? keepsForDays,  bool freezable,  int? freezerDays,  String? bookId,  String? sectionId,  List<CommitGroup> groups,  List<CommitStub> stubs,  List<Step> steps,  List<CommitCorrection> corrections)  $default,) {final _that = this;
switch (_that) {
case _CommitPayload():
return $default(_that.title,_that.servingsBase,_that.servingsRaw,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2,_that.cookTimeSeconds,_that.totalTimeSeconds,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.bookId,_that.sectionId,_that.groups,_that.stubs,_that.steps,_that.corrections);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String title,  double servingsBase,  String? servingsRaw,  double? yieldQty,  Unit? yieldUnit,  double? yieldQty2,  Unit? yieldUnit2,  int? cookTimeSeconds,  int? totalTimeSeconds,  int? keepsForDays,  bool freezable,  int? freezerDays,  String? bookId,  String? sectionId,  List<CommitGroup> groups,  List<CommitStub> stubs,  List<Step> steps,  List<CommitCorrection> corrections)?  $default,) {final _that = this;
switch (_that) {
case _CommitPayload() when $default != null:
return $default(_that.title,_that.servingsBase,_that.servingsRaw,_that.yieldQty,_that.yieldUnit,_that.yieldQty2,_that.yieldUnit2,_that.cookTimeSeconds,_that.totalTimeSeconds,_that.keepsForDays,_that.freezable,_that.freezerDays,_that.bookId,_that.sectionId,_that.groups,_that.stubs,_that.steps,_that.corrections);case _:
  return null;

}
}

}

/// @nodoc


class _CommitPayload implements CommitPayload {
  const _CommitPayload({required this.title, required this.servingsBase, this.servingsRaw, this.yieldQty, this.yieldUnit, this.yieldQty2, this.yieldUnit2, this.cookTimeSeconds, this.totalTimeSeconds, this.keepsForDays, this.freezable = false, this.freezerDays, this.bookId, this.sectionId, final  List<CommitGroup> groups = const <CommitGroup>[], final  List<CommitStub> stubs = const <CommitStub>[], final  List<Step> steps = const <Step>[], final  List<CommitCorrection> corrections = const <CommitCorrection>[]}): _groups = groups,_stubs = stubs,_steps = steps,_corrections = corrections;
  

@override final  String title;
@override final  double servingsBase;
@override final  String? servingsRaw;
/// What one batch MAKES, as the review's header states it (8.6 / D2 ·
/// D9, board frame h) — prefilled from `yield_raw` only when that was a
/// plain amount + unit, and otherwise whatever the human typed, or
/// nothing. Both halves or neither: a half-stated yield is half a fact.
/// The SECOND denomination is the editor's affordance, now at review too
/// (plan 0025 #4): the same header form, so the same two slots.
@override final  double? yieldQty;
@override final  Unit? yieldUnit;
@override final  double? yieldQty2;
@override final  Unit? yieldUnit2;
@override final  int? cookTimeSeconds;
@override final  int? totalTimeSeconds;
/// Shelf life, as the header's SHELF LIFE section states it — unset
/// unless a human set it, because no page prints it.
@override final  int? keepsForDays;
@override@JsonKey() final  bool freezable;
@override final  int? freezerDays;
/// Where the recipe is FILED. Null files into the household's default
/// book at write, exactly where commit has always put an import; the
/// review's draft names that book from the start so FILE UNDER can move
/// it before it lands.
@override final  String? bookId;
@override final  String? sectionId;
 final  List<CommitGroup> _groups;
@override@JsonKey() List<CommitGroup> get groups {
  if (_groups is EqualUnmodifiableListView) return _groups;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_groups);
}

 final  List<CommitStub> _stubs;
@override@JsonKey() List<CommitStub> get stubs {
  if (_stubs is EqualUnmodifiableListView) return _stubs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_stubs);
}

 final  List<Step> _steps;
@override@JsonKey() List<Step> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}

 final  List<CommitCorrection> _corrections;
@override@JsonKey() List<CommitCorrection> get corrections {
  if (_corrections is EqualUnmodifiableListView) return _corrections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_corrections);
}


/// Create a copy of CommitPayload
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CommitPayloadCopyWith<_CommitPayload> get copyWith => __$CommitPayloadCopyWithImpl<_CommitPayload>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CommitPayload&&(identical(other.title, title) || other.title == title)&&(identical(other.servingsBase, servingsBase) || other.servingsBase == servingsBase)&&(identical(other.servingsRaw, servingsRaw) || other.servingsRaw == servingsRaw)&&(identical(other.yieldQty, yieldQty) || other.yieldQty == yieldQty)&&(identical(other.yieldUnit, yieldUnit) || other.yieldUnit == yieldUnit)&&(identical(other.yieldQty2, yieldQty2) || other.yieldQty2 == yieldQty2)&&(identical(other.yieldUnit2, yieldUnit2) || other.yieldUnit2 == yieldUnit2)&&(identical(other.cookTimeSeconds, cookTimeSeconds) || other.cookTimeSeconds == cookTimeSeconds)&&(identical(other.totalTimeSeconds, totalTimeSeconds) || other.totalTimeSeconds == totalTimeSeconds)&&(identical(other.keepsForDays, keepsForDays) || other.keepsForDays == keepsForDays)&&(identical(other.freezable, freezable) || other.freezable == freezable)&&(identical(other.freezerDays, freezerDays) || other.freezerDays == freezerDays)&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.sectionId, sectionId) || other.sectionId == sectionId)&&const DeepCollectionEquality().equals(other._groups, _groups)&&const DeepCollectionEquality().equals(other._stubs, _stubs)&&const DeepCollectionEquality().equals(other._steps, _steps)&&const DeepCollectionEquality().equals(other._corrections, _corrections));
}


@override
int get hashCode => Object.hash(runtimeType,title,servingsBase,servingsRaw,yieldQty,yieldUnit,yieldQty2,yieldUnit2,cookTimeSeconds,totalTimeSeconds,keepsForDays,freezable,freezerDays,bookId,sectionId,const DeepCollectionEquality().hash(_groups),const DeepCollectionEquality().hash(_stubs),const DeepCollectionEquality().hash(_steps),const DeepCollectionEquality().hash(_corrections));

@override
String toString() {
  return 'CommitPayload(title: $title, servingsBase: $servingsBase, servingsRaw: $servingsRaw, yieldQty: $yieldQty, yieldUnit: $yieldUnit, yieldQty2: $yieldQty2, yieldUnit2: $yieldUnit2, cookTimeSeconds: $cookTimeSeconds, totalTimeSeconds: $totalTimeSeconds, keepsForDays: $keepsForDays, freezable: $freezable, freezerDays: $freezerDays, bookId: $bookId, sectionId: $sectionId, groups: $groups, stubs: $stubs, steps: $steps, corrections: $corrections)';
}


}

/// @nodoc
abstract mixin class _$CommitPayloadCopyWith<$Res> implements $CommitPayloadCopyWith<$Res> {
  factory _$CommitPayloadCopyWith(_CommitPayload value, $Res Function(_CommitPayload) _then) = __$CommitPayloadCopyWithImpl;
@override @useResult
$Res call({
 String title, double servingsBase, String? servingsRaw, double? yieldQty, Unit? yieldUnit, double? yieldQty2, Unit? yieldUnit2, int? cookTimeSeconds, int? totalTimeSeconds, int? keepsForDays, bool freezable, int? freezerDays, String? bookId, String? sectionId, List<CommitGroup> groups, List<CommitStub> stubs, List<Step> steps, List<CommitCorrection> corrections
});




}
/// @nodoc
class __$CommitPayloadCopyWithImpl<$Res>
    implements _$CommitPayloadCopyWith<$Res> {
  __$CommitPayloadCopyWithImpl(this._self, this._then);

  final _CommitPayload _self;
  final $Res Function(_CommitPayload) _then;

/// Create a copy of CommitPayload
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = null,Object? servingsBase = null,Object? servingsRaw = freezed,Object? yieldQty = freezed,Object? yieldUnit = freezed,Object? yieldQty2 = freezed,Object? yieldUnit2 = freezed,Object? cookTimeSeconds = freezed,Object? totalTimeSeconds = freezed,Object? keepsForDays = freezed,Object? freezable = null,Object? freezerDays = freezed,Object? bookId = freezed,Object? sectionId = freezed,Object? groups = null,Object? stubs = null,Object? steps = null,Object? corrections = null,}) {
  return _then(_CommitPayload(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,servingsBase: null == servingsBase ? _self.servingsBase : servingsBase // ignore: cast_nullable_to_non_nullable
as double,servingsRaw: freezed == servingsRaw ? _self.servingsRaw : servingsRaw // ignore: cast_nullable_to_non_nullable
as String?,yieldQty: freezed == yieldQty ? _self.yieldQty : yieldQty // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit: freezed == yieldUnit ? _self.yieldUnit : yieldUnit // ignore: cast_nullable_to_non_nullable
as Unit?,yieldQty2: freezed == yieldQty2 ? _self.yieldQty2 : yieldQty2 // ignore: cast_nullable_to_non_nullable
as double?,yieldUnit2: freezed == yieldUnit2 ? _self.yieldUnit2 : yieldUnit2 // ignore: cast_nullable_to_non_nullable
as Unit?,cookTimeSeconds: freezed == cookTimeSeconds ? _self.cookTimeSeconds : cookTimeSeconds // ignore: cast_nullable_to_non_nullable
as int?,totalTimeSeconds: freezed == totalTimeSeconds ? _self.totalTimeSeconds : totalTimeSeconds // ignore: cast_nullable_to_non_nullable
as int?,keepsForDays: freezed == keepsForDays ? _self.keepsForDays : keepsForDays // ignore: cast_nullable_to_non_nullable
as int?,freezable: null == freezable ? _self.freezable : freezable // ignore: cast_nullable_to_non_nullable
as bool,freezerDays: freezed == freezerDays ? _self.freezerDays : freezerDays // ignore: cast_nullable_to_non_nullable
as int?,bookId: freezed == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as String?,sectionId: freezed == sectionId ? _self.sectionId : sectionId // ignore: cast_nullable_to_non_nullable
as String?,groups: null == groups ? _self._groups : groups // ignore: cast_nullable_to_non_nullable
as List<CommitGroup>,stubs: null == stubs ? _self._stubs : stubs // ignore: cast_nullable_to_non_nullable
as List<CommitStub>,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<Step>,corrections: null == corrections ? _self._corrections : corrections // ignore: cast_nullable_to_non_nullable
as List<CommitCorrection>,
  ));
}


}

// dart format on
