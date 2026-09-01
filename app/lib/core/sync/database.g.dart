// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The open [PowerSyncDatabase]. Has no default — `bootstrap.dart` overrides it
/// with the result of [openAnsiDatabase]. Repo tests don't use it.

@ProviderFor(powerSyncDatabase)
const powerSyncDatabaseProvider = PowerSyncDatabaseProvider._();

/// The open [PowerSyncDatabase]. Has no default — `bootstrap.dart` overrides it
/// with the result of [openAnsiDatabase]. Repo tests don't use it.

final class PowerSyncDatabaseProvider
    extends
        $FunctionalProvider<
          PowerSyncDatabase,
          PowerSyncDatabase,
          PowerSyncDatabase
        >
    with $Provider<PowerSyncDatabase> {
  /// The open [PowerSyncDatabase]. Has no default — `bootstrap.dart` overrides it
  /// with the result of [openAnsiDatabase]. Repo tests don't use it.
  const PowerSyncDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'powerSyncDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$powerSyncDatabaseHash();

  @$internal
  @override
  $ProviderElement<PowerSyncDatabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PowerSyncDatabase create(Ref ref) {
    return powerSyncDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PowerSyncDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PowerSyncDatabase>(value),
    );
  }
}

String _$powerSyncDatabaseHash() => r'24475f6f71280bedc6987b1d44f3b31c45f6688d';

/// The open database, as the common [SqliteConnection] type so repositories and
/// their tests depend on the query surface, not on PowerSync specifically.
///
/// Derives from [powerSyncDatabase] in the app; a test overrides *this*
/// provider directly with an in-memory connection.

@ProviderFor(database)
const databaseProvider = DatabaseProvider._();

/// The open database, as the common [SqliteConnection] type so repositories and
/// their tests depend on the query surface, not on PowerSync specifically.
///
/// Derives from [powerSyncDatabase] in the app; a test overrides *this*
/// provider directly with an in-memory connection.

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
  /// Derives from [powerSyncDatabase] in the app; a test overrides *this*
  /// provider directly with an in-memory connection.
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

String _$databaseHash() => r'cf9606dd3c7cfd4c9b4e3443d0c21ee1d0aa3cb7';
