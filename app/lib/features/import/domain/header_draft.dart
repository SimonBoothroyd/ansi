/// The review's header draft: the [Recipe] the shared header form edits at
/// import, seeded from the payload. Pure Dart. A field is prefilled only where
/// the page plainly said it, and starts unset otherwise.
library;

import '../../recipes/domain/recipe.dart';
import 'reconciliation_payload.dart';
import 'yield_prefill.dart';

/// The id the draft carries until commit mints the real one. Nothing reads
/// it; the repository assigns the recipe's id when the row is written.
const kImportHeaderDraftId = 'import-draft';

/// Seeds the header draft from [payload]:
///
/// - title and servings as printed (servings defaults to 1 when unclear, which
///   the review flags);
/// - makes from `yield_raw` only when it was a plain amount and unit
///   ([parseYieldRaw]);
/// - times from the printed cook and total time, the low end of a range;
/// - shelf life unset, and filed into [bookId].
Recipe headerDraft(
  ReconciliationPayload payload, {
  required String? bookId,
  String? sectionId,
}) {
  final prefill = parseYieldRaw(payload.yieldRaw);
  return Recipe(
    id: kImportHeaderDraftId,
    title: payload.title,
    servingsBase: (payload.servingsBase ?? 1).toDouble(),
    yieldQty: prefill?.qty,
    yieldUnit: prefill?.unit,
    cookTimeSeconds: payload.cookTimeSeconds?.lowSeconds,
    totalTimeSeconds: payload.totalTimeSeconds?.lowSeconds,
    bookId: bookId,
    sectionId: sectionId,
  );
}
