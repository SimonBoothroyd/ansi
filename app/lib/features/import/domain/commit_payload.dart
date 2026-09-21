/// The commit payload, built client-side once every reconciliation line is
/// resolved and written by the import repository. Pure Dart.
///
/// Every line has exactly one identity (`line_item_identity_xor`): an existing
/// `ingredientId`, or a `subRecipeId` for a review-linked line. The commit
/// creates no ingredient. Step refs are by line index here; the repository
/// assigns `line_item_id`s in flattened order and remaps the refs.
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import 'reconciliation_payload.dart';

part 'commit_payload.freezed.dart';

/// A resolved line. Exactly one identity is set: [ingredientId] or
/// [subRecipeId].
@freezed
abstract class CommitLine with _$CommitLine {
  const factory CommitLine({
    /// The flattened line index — its position in the commit's line order and
    /// the value step tokens ref before the remap.
    required int lineIndex,
    String? ingredientId,

    /// The household recipe this line was linked to at review. When set, the
    /// line is a component line: [ingredientId] is null and no `measure_id` is
    /// written.
    String? subRecipeId,
    double? quantity,
    String? unit,
    String? note,

    /// The recipe says this line may be left out: seeded from the extractor's
    /// flag, toggled at review, written to `recipe_line_item.optional`. Applies
    /// to component lines too.
    @Default(false) bool optional,
  }) = _CommitLine;
}

@freezed
abstract class CommitGroup with _$CommitGroup {
  const factory CommitGroup({
    String? name,
    @Default(<CommitLine>[]) List<CommitLine> lines,
  }) = _CommitGroup;
}

/// A user correction to write back as an alias (`source='import_correction'`):
/// the raw [aliasText] now points at [ingredientId].
@freezed
abstract class CommitCorrection with _$CommitCorrection {
  const factory CommitCorrection({
    required String ingredientId,
    required String aliasText,
  }) = _CommitCorrection;
}

@freezed
abstract class CommitPayload with _$CommitPayload {
  const factory CommitPayload({
    required String title,
    required double servingsBase,
    String? servingsRaw,

    /// What one batch makes, as the review's header states it: prefilled from
    /// `yield_raw` only when that was a plain amount and unit, else whatever
    /// the human typed. Both halves or neither. A second denomination has the
    /// same two slots.
    double? yieldQty,
    Unit? yieldUnit,
    double? yieldQty2,
    Unit? yieldUnit2,
    int? cookTimeSeconds,
    int? totalTimeSeconds,

    /// Shelf life, as the header's SHELF LIFE section states it — unset
    /// unless a human set it, because no page prints it.
    int? keepsForDays,
    @Default(false) bool freezable,
    int? freezerDays,

    /// Where the recipe is filed. Null files into the household's default book
    /// at write.
    String? bookId,
    String? sectionId,

    /// The recipe's own measures, as the review's MEASURES list states them
    /// (ADR-0018). Never prefilled. Each has passed `authorRecipeMeasure`
    /// against the yields above; the repository re-stamps the recipe id over
    /// the draft's placeholder.
    @Default(<RecipeMeasure>[]) List<RecipeMeasure> measures,
    @Default(<CommitGroup>[]) List<CommitGroup> groups,
    @Default(<Step>[]) List<Step> steps,
    @Default(<CommitCorrection>[]) List<CommitCorrection> corrections,
  }) = _CommitPayload;
}
