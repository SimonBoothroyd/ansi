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
/// function ([EdgeImportRepository]); unconfigured (dev/offline, and tests) it
/// falls back to the canned/fake repository so the flow still exercises end to
/// end without a backend.

@ProviderFor(importRepository)
const importRepositoryProvider = ImportRepositoryProvider._();

/// The import repository the app uses.
///
/// `commit` is always the local PowerSync writer ([SqliteImportRepository]).
/// The extract→match step is what varies: with Supabase configured
/// ([Env.isConfigured]) it runs for real against the `import-recipe` edge
/// function ([EdgeImportRepository]); unconfigured (dev/offline, and tests) it
/// falls back to the canned/fake repository so the flow still exercises end to
/// end without a backend.

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
  /// function ([EdgeImportRepository]); unconfigured (dev/offline, and tests) it
  /// falls back to the canned/fake repository so the flow still exercises end to
  /// end without a backend.
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

String _$importRepositoryHash() => r'9ba16193303fe20d00999a34a404a59c96e3dd22';
