/// A tiny typed result: either an [Ok] value or an [Err] failure.
///
/// **Where it is used, and where it deliberately is not.** It is the return
/// type of the app's TOTAL PURE computations — `core/units` (conversion,
/// measure resolution) and the few domain files that do the same kind of
/// arithmetic (recipe macros, component maths, the barcode draft's apply).
/// A conversion that cannot be made is an ordinary answer, not an event, and
/// its caller is usually rendering the failure beside the number.
///
/// Repositories do **not** return it: they throw, and the write door
/// (`shared/write.dart`) turns a throw into a toast with a reason and a
/// retry. That split is on purpose. Threading [Result] through 71 repository
/// methods would buy nothing the door does not already give and would put the
/// failure surface back in each of 40 call sites.
///
/// Pure Dart — no Flutter imports.
library;

import 'package:meta/meta.dart';

@immutable
sealed class Result<T> {
  const Result();

  /// True when this is an [Ok].
  bool get isOk => this is Ok<T>;

  /// The value if [Ok], else null.
  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  /// Transform the contained value, leaving failures untouched.
  Result<R> map<R>(R Function(T value) f) => switch (this) {
    Ok(:final value) => Ok(f(value)),
    Err(:final failure) => Err(failure),
  };

  /// Fold both branches into a single value.
  R fold<R>(R Function(T value) onOk, R Function(Failure f) onErr) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };
}

@immutable
final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

@immutable
final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;
  @override
  int get hashCode => failure.hashCode;
}

/// A domain failure with a machine-readable [code] and a human [message].
@immutable
class Failure {
  const Failure(this.code, this.message);

  /// `namespace/reason` — the namespace is the module that refused
  /// (`unit/no_density`, `measure/invalid_amount`), so a caller can branch on
  /// the reason without matching on [message], which is prose and may change.
  final String code;
  final String message;

  @override
  String toString() => 'Failure($code: $message)';

  @override
  bool operator ==(Object other) =>
      other is Failure && other.code == code && other.message == message;
  @override
  int get hashCode => Object.hash(code, message);
}
