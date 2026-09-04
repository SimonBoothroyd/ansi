/// The Open Food Facts reader, as a provider — the barcode path's one injection
/// seam.
///
/// `scanBarcodeForDraft` and the New-ingredient sheet already take an
/// [OffLookup] parameter, which is how the *widget* tests reach in. That hook
/// does not reach the **integration** harness: there the sheet is opened by the
/// manager list, deep inside a real navigation stack that nothing outside can
/// pass a parameter through. So the default arrives by provider instead, and
/// `make test-sim` overrides it the way scenario 4 overrides the import
/// repository — one `ProviderScope` override, every other collaborator real.
///
/// Production call sites are unchanged: they pass no lookup and get exactly
/// what they got before, a real keyless client aimed at Open Food Facts.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'off_lookup.dart';

part 'off_lookup_provider.g.dart';

/// The app's Open Food Facts client.
///
/// `keepAlive` because it wraps one long-lived `http.Client`: rebuilding it
/// per sheet would open and drop a connection pool on every scan. It is closed
/// with the container rather than with any one surface, which is also why the
/// scan sheet must not close what it did not make — see `BarcodeScanSheet`'s
/// ownership rule.
@Riverpod(keepAlive: true)
OffLookup offLookup(Ref ref) {
  final lookup = OffLookup();
  ref.onDispose(lookup.close);
  return lookup;
}
