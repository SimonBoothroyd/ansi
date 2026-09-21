/// The Open Food Facts reader as a provider: the barcode path's injection seam.
///
/// Widget tests pass an [OffLookup] to `scanBarcodeForDraft`, but the
/// integration harness opens the scan deep inside a real navigation stack, so
/// there the default arrives by provider and `make test-sim` overrides it.
/// Production gets a real keyless client.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'off_lookup.dart';

part 'off_lookup_provider.g.dart';

/// The app's Open Food Facts client. `keepAlive` because it wraps one
/// long-lived `http.Client`. It is closed with the container, so the scan sheet
/// must not close a lookup it did not make.
@Riverpod(keepAlive: true)
OffLookup offLookup(Ref ref) {
  final lookup = OffLookup();
  ref.onDispose(lookup.close);
  return lookup;
}
