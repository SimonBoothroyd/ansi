/// The review's header draft — the [Recipe] the shared header form edits at
/// import, seeded from the payload. PURE DART.
///
/// The same attempt-then-flag rule servings has always used, applied to the
/// whole header: a field is prefilled ONLY where the page plainly said it,
/// and starts unset otherwise. Nothing is guessed from a fancier phrase.
library;

import '../../recipes/domain/recipe.dart';
import 'reconciliation_payload.dart';
import 'yield_prefill.dart';

/// The id the draft carries until commit mints the real one. Nothing reads
/// it; the repository assigns the recipe's id when the row is written.
const kImportHeaderDraftId = 'import-draft';

/// Seeds the header draft from [payload]:
///
/// - **title** and **servings** as the page printed them (servings defaults
///   to 1 when unclear, which the review flags beside the stepper);
/// - **makes** from `yield_raw` only when that was a plain amount + unit
///   ([parseYieldRaw]); the second denomination starts unset;
/// - **times** from the extractor's printed cook / total time — the low end
///   of a range, exactly what the commit has always written;
/// - **shelf life** unset and **filed into [bookId]** (the default book, the
///   same place commit has always put an import), because no page prints
///   either.
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
