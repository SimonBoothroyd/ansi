// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The import repository the app uses.
///
/// `commit` is always the local PowerSync writer ([SqliteImportRepository]).
/// The extract→match step is what varies: with Supabase configured
/// ([Env.isConfigured]) it runs for real against the `import-recipe` edge
/// function ([EdgeImportRepository]).
///
/// Unconfigured, extraction has nowhere to run, so it FAILS LOUDLY
/// ([_UnconfiguredImport]). It used to fall through to the canned demo payload
/// — which meant a misconfigured build silently answered "import this URL" with
/// somebody else's spaghetti recipe. Tests and the on-device smoke test get the
/// canned repository by naming [SqliteImportRepository] directly, never by
/// accident.

@ProviderFor(importRepository)
const importRepositoryProvider = ImportRepositoryProvider._();

/// The import repository the app uses.
///
/// `commit` is always the local PowerSync writer ([SqliteImportRepository]).
/// The extract→match step is what varies: with Supabase configured
/// ([Env.isConfigured]) it runs for real against the `import-recipe` edge
/// function ([EdgeImportRepository]).
///
/// Unconfigured, extraction has nowhere to run, so it FAILS LOUDLY
/// ([_UnconfiguredImport]). It used to fall through to the canned demo payload
/// — which meant a misconfigured build silently answered "import this URL" with
/// somebody else's spaghetti recipe. Tests and the on-device smoke test get the
/// canned repository by naming [SqliteImportRepository] directly, never by
/// accident.

final class ImportRepositoryProvider
    extends
        $FunctionalProvider<
          ImportRepository,
          ImportRepository,
          ImportRepository
        >
    with $Provider<ImportRepository> {
  /// The import repository the app uses.
  ///
  /// `commit` is always the local PowerSync writer ([SqliteImportRepository]).
  /// The extract→match step is what varies: with Supabase configured
  /// ([Env.isConfigured]) it runs for real against the `import-recipe` edge
  /// function ([EdgeImportRepository]).
  ///
  /// Unconfigured, extraction has nowhere to run, so it FAILS LOUDLY
  /// ([_UnconfiguredImport]). It used to fall through to the canned demo payload
  /// — which meant a misconfigured build silently answered "import this URL" with
  /// somebody else's spaghetti recipe. Tests and the on-device smoke test get the
  /// canned repository by naming [SqliteImportRepository] directly, never by
  /// accident.
  const ImportRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'importRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$importRepositoryHash();

  @$internal
  @override
  $ProviderElement<ImportRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ImportRepository create(Ref ref) {
    return importRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ImportRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ImportRepository>(value),
    );
  }
}

String _$importRepositoryHash() => r'c7deb4afe5ccc5bfffc7b3b1c9d2c7ff2477a428';
