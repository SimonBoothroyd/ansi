/// The import review screen: one editable surface.
///
/// Every line is an expandable [ReviewLineCard]; the honest-import warnings
/// ride the top and commit happens at the bottom. The method is editable
/// through [ImportMethodEditing], whose chips key on the preview's `line-<i>`
/// ids. Sections can be renamed, added and deleted (their lines move into the
/// section above), and lines can be added; all of that lives in
/// `ImportReconciling.sections`, and the payload stays as the server sent it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/reorder_grip.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/component_quantity_sheet.dart';
import '../../recipes/presentation/line_target_picker.dart';
import '../../recipes/presentation/method_editor.dart';
import '../../recipes/presentation/recipe_header_form.dart';
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
import '../domain/preview_recipe.dart';
import '../domain/reconciliation_payload.dart';
import '../domain/review_groups.dart';
import 'import_method_editing.dart';
import 'import_view_models.dart';
import 'recon_line_card.dart';

class ReconciliationBody extends HookConsumerWidget {
  const ReconciliationBody({required this.state, super.key});

  final ImportReconciling state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(importControllerProvider.notifier);
    final payload = state.payload;
    // Per-line validity and unit chips: drives each card's flag, its
    // suggestions and the Save gate. Read through `.value`, not `asData`: a
    // recompute passes through a loading state whose data-only view is null,
    // which blinked every card on each keystroke.
    final validation = ref.watch(importValidationProvider);
    final byLine = validation.value;
    // The method's step cards read the recipe a save would write, so a chip
    // keyed on `previewLineId(i)` resolves directly. The measure a line's unit
    // names comes from the same validation map the card prints.
    final recipe = buildPreviewRecipe(
      payload,
      state.resolutions,
      servingsBase: state.servings,
      sections: state.sections,
      measureByLine: {
        if (byLine != null)
          for (final e in byLine.entries)
            if (e.value.unitMeasure != null) e.key: e.value.unitMeasure!,
      },
    );
    final methodHost = ImportMethodEditing(
      controller: controller,
      state: state,
      preview: recipe,
    );

    // The sections are the review's own, holding flat line indexes; `lineAt`
    // covers a line added at review. They render as one flat list, a heading
    // row then its line rows. Every index takes a row, resolved or not, because
    // row positions are the drag's arithmetic.
    final collapseEpoch = useState(0);
    final rows = reviewRowList(
      state: state,
      byLine: byLine,
      row: (line, resolution, validation, dragIndex) => ReviewLineCard(
        key: ValueKey('review-line-${resolution.lineIndex}'),
        line: line,
        resolution: resolution,
        validation: validation,
        dragIndex: dragIndex,
        collapseEpoch: collapseEpoch.value,
      ),
    );

    final source = payload.yieldRaw?.trim();
    final sourceStated = source != null && source.isNotEmpty;
    return CustomScrollView(
      // Dragging dismisses the keyboard: a focused field off screen asks to be
      // scrolled back to on every keyboard metrics change.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          // A list rather than one box: the slivers stay lazy, so a long
          // method's step cards are not all built to show the top of the page.
          sliver: SliverList.list(
            children: [
              // The source notes sit above the form, since they are about the
              // whole import.
              ImportSourceNotes(payload: payload),
              // The editor's header, hosted by the controller. What only the
              // review knows is drawn through the note slot: whether the page
              // printed a serving count, and its `yield_raw`. Nothing here
              // gates Save.
              RecipeHeaderForm(
                host: controller,
                timeCaptions: false,
                notes: RecipeHeaderNotes(
                  besideServes: payload.servingsBase == null
                      ? 'not printed — set it'
                      : null,
                  underMakes: sourceStated ? 'from source:  $source' : null,
                  afterMakes: state.header.yieldQty != null
                      ? null
                      : sourceStated
                      ? 'the page didn’t say a number — set one, or leave it '
                            'unset. Nothing is invented, and a yield-less '
                            'recipe still saves, links and scales; only the '
                            'derived numbers wait.'
                      : 'the page didn’t say what this makes — set it, or '
                            'leave it unset. Nothing is invented, and a '
                            'yield-less recipe still saves, links and '
                            'scales.',
                ),
              ),
              const SizedBox(height: 10),
              // The count excludes dropped lines.
              ReviewSectionHeader(
                label: 'Ingredients',
                count: keptLines(state.resolutions).length,
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverReorderableList(
            itemCount: rows.length,
            itemBuilder: (context, index) => rows[index],
            onReorderItem: controller.moveLine,
            // An open card closes as soon as a drag begins: what crosses the
            // list is then a row like every other row.
            onReorderStart: (_) => collapseEpoch.value++,
            proxyDecorator: liftedRow,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          sliver: SliverList.list(
            children: [
              // The two doors sit tight under the last line, as part of the
              // list.
              ReviewListDoors(recipe: recipe, sections: state.sections),
              const SizedBox(height: 24),
              MethodEditor(recipe: recipe, notifier: methodHost),
              const SizedBox(height: 20),
              ReviewCommitBar(state: state),
            ],
          ),
        ),
      ],
    );
  }
}

/// The flat row list the review drags: a heading per section, then a row per
/// line index it holds. Shared by the phone's cards and the wide screen's rows.
/// Every index takes a row, resolved or not, because row positions are the
/// drag's arithmetic.
///
/// [row] receives the line, its resolution, its validation and its drag index.
List<Widget> reviewRowList({
  required ImportReconciling state,
  required Map<int, LineValidation>? byLine,
  required Widget Function(
    ReconLine line,
    LineResolution resolution,
    LineValidation? validation,
    int dragIndex,
  )
  row,
}) {
  final byIndex = {for (final r in state.resolutions) r.lineIndex: r};
  final rows = <Widget>[];
  for (final group in state.sections) {
    rows.add(
      ReviewSectionHeading(
        key: ValueKey('review-section-${group.id}'),
        group: group,
        removable: state.sections.length > 1,
      ),
    );
    for (final i in group.lines) {
      final resolution = byIndex[i];
      rows.add(
        resolution == null
            ? SizedBox.shrink(key: ValueKey('review-line-$i'))
            : row(state.lineAt(i), resolution, byLine?[i], rows.length),
      );
    }
  }
  return rows;
}

/// The Save gate and the sentence that says why it is shut. A widget of its own
/// because the wide review draws it as the lines column's footer. `buildCommit`
/// re-asserts the same map at the seam.
class ReviewCommitBar extends ConsumerWidget {
  const ReviewCommitBar({required this.state, super.key});

  final ImportReconciling state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(importControllerProvider.notifier);
    // `.value`, never `asData`; see the body's note on the same provider.
    final validation = ref.watch(importValidationProvider);
    final byLine = validation.value;
    final issuesByLine = byLine == null
        ? null
        : {for (final e in byLine.entries) e.key: e.value.issues};
    // The vocab read behind the gate failed and has never answered. Save cannot
    // open, and a structural count of zero would be misleading.
    final unchecked = byLine == null && validation.hasError;
    // Save requires every line valid: matched, range picked, unit allowed.
    // Disabled until validation has loaded once.
    final canSave =
        issuesByLine != null && state.canCommit && allLinesValid(issuesByLine);
    // ONE count, shared with the header's "N to review" (they were two
    // different rules and the header never decremented).
    final outstanding = ref.watch(importOutstandingLinesProvider);
    return FButton(
      // After a failed check the button becomes the retry.
      onPress: canSave
          ? () => controller.commit(issuesByLine: issuesByLine)
          : unchecked
          ? () => ref.invalidate(importValidationProvider)
          : null,
      child: Text(
        canSave
            ? 'Save recipe'
            : keptLines(state.resolutions).isEmpty
            // Every line dropped: the count would read "0 line(s) need you",
            // which is true and useless.
            ? 'Nothing left to save'
            : unchecked
            ? 'Couldn’t check the lines — try again'
            : '$outstanding line(s) need you',
      ),
    );
  }
}

/// One section's heading: the name as an editable field, and the bin. Deleting
/// a heading moves its lines into the section above, so the bin needs no
/// confirm. A single unnamed section shows no heading row.
class ReviewSectionHeading extends ConsumerWidget {
  const ReviewSectionHeading({
    required this.group,
    required this.removable,
    super.key,
  });

  final ReviewGroup group;
  final bool removable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!removable && (group.name == null || group.name!.isEmpty)) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(importControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: FTextField(
              hint: 'Section name (optional)',
              control: FTextFieldControl.managed(
                initial: TextEditingValue(text: group.name ?? ''),
                onChange: (v) => controller.setSectionName(group.id, v.text),
              ),
            ),
          ),
          if (removable) ...[
            const SizedBox(width: 8),
            Semantics(
              label: 'Delete section',
              button: true,
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: () => controller.removeSection(group.id),
                child: const Icon(FLucideIcons.trash2, size: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The list's two doors: add a line, and add a section. A new line lands in the
/// last section.
class ReviewListDoors extends ConsumerWidget {
  const ReviewListDoors({
    required this.recipe,
    required this.sections,
    super.key,
  });

  final Recipe recipe;
  final List<ReviewGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Expanded(
          child: FButton(
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            prefix: const Icon(FLucideIcons.plus),
            onPress: () => unawaited(_addLine(context, ref)),
            child: const Text('ingredient'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FButton(
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            prefix: const Icon(FLucideIcons.plus),
            onPress: ref.read(importControllerProvider.notifier).addSection,
            child: const Text('section'),
          ),
        ),
      ],
    ),
  );

  /// The editor's own two-step chain — the target picker, then the quantity
  /// sheet — landing on the review's `addLine` instead of the editor's.
  Future<void> _addLine(BuildContext context, WidgetRef ref) async {
    // Read through the container, not this widget's `ref`: the picker's
    // keyboard can unmount the doors before a row is tapped, and a `WidgetRef`
    // used after unmount throws.
    final container = ProviderScope.containerOf(context, listen: false);
    final controller = container.read(importControllerProvider.notifier);
    final groupId = sections.last.id;
    final picked = await showLineTargetPicker(
      context,
      editingRecipeId: recipe.id,
    );
    if (picked == null || !context.mounted) return;
    switch (picked) {
      case PickedIngredient(:final ingredient):
        final result = await showQuantityUnitSheet(
          context,
          ingredient: ingredient,
        );
        controller.addLine(
          groupId,
          name: ingredient.canonicalName,
          ingredientId: ingredient.id,
          quantity: result is QuantitySaved ? result.quantity : null,
          unit: result is QuantitySaved
              ? sheetChoiceUnit(
                  choice: result.choice,
                  unitPicked: true,
                  currentUnit: null,
                )
              : ingredient.defaultUnit.id,
        );
      case PickedSubRecipe(:final target):
        final result = await showComponentQuantitySheet(
          context,
          // No recipe measures and no ＋ on the review's dock: a review line
          // stores a unit id and has no column for one of the target's own
          // words (ADR-0018).
          target: target.copyWith(measures: const []),
        );
        controller.addLine(
          groupId,
          name: target.title,
          recipeId: target.id,
          quantity: result?.quantity,
          unit: (result?.unit ?? batches).id,
          optional: result?.optional ?? false,
        );
    }
  }
}

/// What the extractor could not read cleanly: a truncated source, a degraded
/// photo, and the model's [ReconciliationPayload.parseWarnings]. Empty for a
/// clean import.
List<String> sourceNotes(ReconciliationPayload payload) => <String?>[
  if (payload.truncated)
    'The source was longer than we could read — check nothing is missing.',
  switch (payload.imageQuality) {
    ImportImageQuality.ok => null,
    ImportImageQuality.degraded =>
      'The photo was hard to read — amounts especially.',
    ImportImageQuality.poor =>
      'The photo was very hard to read — check every line.',
  },
  ...payload.parseWarnings,
].whereType<String>().toList();

/// [sourceNotes] at the top of the review, as one quiet block.
class ImportSourceNotes extends StatelessWidget {
  const ImportSourceNotes({required this.payload, super.key});

  final ReconciliationPayload payload;

  @override
  Widget build(BuildContext context) {
    final notes = sourceNotes(payload);
    if (notes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AnsiColors.paper,
          border: Border.all(color: AnsiColors.aging),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    FLucideIcons.triangleAlert,
                    size: 12,
                    color: AnsiColors.aging,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'WHAT WE COULD NOT READ',
                    style: ansiLabel(color: AnsiColors.aging),
                  ),
                ],
              ),
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '· $note',
                    style: ansiMono(size: 11, color: AnsiColors.muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section header: the mono label + a count pill + a rule.
class ReviewSectionHeader extends StatelessWidget {
  const ReviewSectionHeader({
    required this.label,
    required this.count,
    super.key,
  });

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(
        children: [
          Text(label.toUpperCase(), style: ansiLabel(color: AnsiColors.ink)),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AnsiColors.herb,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              child: Text(
                '$count',
                style: ansiMono(size: 10, color: AnsiColors.surface),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: AnsiColors.line)),
        ],
      ),
    );
  }
}
