// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The import repository the app uses.
///
/// `commit` is always the local writer ([SqliteImportRepository]). With
/// Supabase configured ([Env.isConfigured]) extraction runs against the edge
/// function ([EdgeImportRepository]); unconfigured it fails loudly
/// ([_UnconfiguredImport]) rather than serving the canned payload. Tests get
/// the canned repository by naming [SqliteImportRepository] directly.

@ProviderFor(importRepository)
const importRepositoryProvider = ImportRepositoryProvider._();

/// The import repository the app uses.
///
/// `commit` is always the local writer ([SqliteImportRepository]). With
/// Supabase configured ([Env.isConfigured]) extraction runs against the edge
/// function ([EdgeImportRepository]); unconfigured it fails loudly
/// ([_UnconfiguredImport]) rather than serving the canned payload. Tests get
/// the canned repository by naming [SqliteImportRepository] directly.

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
  /// `commit` is always the local writer ([SqliteImportRepository]). With
  /// Supabase configured ([Env.isConfigured]) extraction runs against the edge
  /// function ([EdgeImportRepository]); unconfigured it fails loudly
  /// ([_UnconfiguredImport]) rather than serving the canned payload. Tests get
  /// the canned repository by naming [SqliteImportRepository] directly.
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
