// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The open database, as the common [SqliteConnection] type so repositories and
/// their tests depend on the query surface, not on PowerSync specifically.
///
/// Has no default — `bootstrap.dart` (app) or a test overrides it.

@ProviderFor(database)
const databaseProvider = DatabaseProvider._();

/// The open database, as the common [SqliteConnection] type so repositories and
/// their tests depend on the query surface, not on PowerSync specifically.
///
/// Has no default — `bootstrap.dart` (app) or a test overrides it.

final class DatabaseProvider
    extends
        $FunctionalProvider<
          SqliteConnection,
          SqliteConnection,
          SqliteConnection
        >
    with $Provider<SqliteConnection> {
  /// The open database, as the common [SqliteConnection] type so repositories and
  /// their tests depend on the query surface, not on PowerSync specifically.
  ///
  /// Has no default — `bootstrap.dart` (app) or a test overrides it.
  const DatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'databaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$databaseHash();

  @$internal
  @override
  $ProviderElement<SqliteConnection> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SqliteConnection create(Ref ref) {
    return database(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SqliteConnection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SqliteConnection>(value),
    );
  }
}

String _$databaseHash() => r'8e1415f82fcabc6239ee759f3e7f06f341dc8b30';
