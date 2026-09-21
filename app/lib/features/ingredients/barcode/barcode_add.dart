/// The barcode path's one public door: `scanBarcodeForDraft`.
///
/// Opens the scan surface, looks the code up in Open Food Facts on the device,
/// and resolves with an [IngredientDraft]: filled for a found product, blank
/// for the "add it by hand" exit, null when closed. It writes nothing, and a
/// null macro panel means absent. The draft carries its provenance
/// ([IngredientDraft.sourceValue]) and the ODbL credit
/// ([IngredientDraft.attribution]).
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
// The two test-hook types below appear in [scanBarcodeForDraft]'s signature, so
// they are exported with it.
export 'off_lookup.dart' show OffLookup;
// The provider seam: app code never names it (the sheet reads it), but the
// integration harness overrides it, so it belongs to the door too.
export 'off_lookup_provider.dart' show offLookupProvider;

/// Opens the barcode surface and resolves with the draft the user leaves with,
/// or null if they closed it empty. [lookup] and [cameraPane] exist for tests.
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
