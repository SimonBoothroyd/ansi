/// **The barcode path's one public door** (step 8.5).
///
/// ## Contract
///
/// ```dart
/// final draft = await scanBarcodeForDraft(context);
/// ```
///
/// * Opens the scan surface (camera reticle + a permanent typed-number
///   field), looks the code up in Open Food Facts **on the device**, and
///   resolves with an [IngredientDraft].
/// * Resolves **null** only when the user closed the surface without one.
/// * A found product resolves with a filled draft; a not-found code resolves
///   with `IngredientDraft.blank(barcode: …)` if the user takes the "add it
///   by hand" exit. Either way the caller has somewhere to go.
/// * It **never writes anything**. No repository, no provider, no row. Under
///   D1 a lookup prefills a draft and never completes an ingredient, so the
///   draft's macros can be null, and null means *absent*, not zero. The
///   caller confirms (D5: macros gate `complete`, and confirming is a human
///   act).
/// * The draft carries its own provenance: `IngredientDraft.sourceValue` is
///   the `off:<barcode>` value for the row's `source` column, and
///   `IngredientDraft.attribution` is the ODbL credit the form must show
///   beside anything OFF supplied.
///
/// Wiring it into a host is one import and one await; nothing else in this
/// directory needs to be referenced from outside it.
///
/// ## What lives behind this door
///
/// * `ingredient_draft.dart` — the hand-off type (pure Dart).
/// * `off_lookup.dart` — the keyless GET and its failure taxonomy.
/// * `off_lookup_provider.dart` — that client as a provider, the seam the
///   integration harness overrides.
/// * `off_mapper.dart` — OFF payload → draft, pure and fixture-tested.
/// * `barcode_scan_sheet.dart` — the surface and its three failure states.
library;

import 'package:flutter/widgets.dart';

import '../../../shared/ansi_modals.dart';
import 'barcode_scan_sheet.dart';
import 'ingredient_draft.dart';
import 'off_lookup.dart';

export 'barcode_scan_sheet.dart' show BarcodeCameraPane;
export 'ingredient_draft.dart'
    show
        DraftMacrosGap,
        DraftPackSize,
        DraftServingPanel,
        DraftSource,
        IngredientDraft;
// The two test-hook types below are named by [scanBarcodeForDraft]'s own
// signature, so a caller cannot inject either without them — they belong to
// the door, not behind it.
export 'off_lookup.dart' show OffLookup;
// The provider seam: app code never names it (the sheet reads it), but the
// integration harness overrides it, so it belongs to the door too.
export 'off_lookup_provider.dart' show offLookupProvider;

/// Opens the barcode surface and resolves with the draft the user leaves
/// with, or null if they closed it empty.
///
/// [lookup] and [cameraPane] exist for tests and are unused in app code — the
/// defaults are a real Open Food Facts client and the real camera preview.
Future<IngredientDraft?> scanBarcodeForDraft(
  BuildContext context, {
  OffLookup? lookup,
  BarcodeCameraPane? cameraPane,
}) {
  return showAnsiSheet<IngredientDraft>(
    context: context,
    builder: (sheetContext) => BarcodeScanSheet(
      lookup: lookup,
      cameraPane: cameraPane,
      onResolved: (draft) => Navigator.of(sheetContext).pop(draft),
      onDismiss: () => Navigator.of(sheetContext).pop(),
    ),
  );
}
