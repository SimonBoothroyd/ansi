/// A tiny typed result: either a [Ok] value or an [Err] failure.
///
/// Used across the domain so pure logic can report failures without throwing
/// across layers (see `docs/architecture.md`). Pure Dart — no Flutter imports.
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
