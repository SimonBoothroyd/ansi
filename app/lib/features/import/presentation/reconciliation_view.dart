/// The v3 review screen (owner refinement): ONE editable surface. There is no
/// separate triage/preview split any more — the imported recipe is reviewed and
/// confirmed here, every line an expandable [ReviewLineCard] (compact by
/// default, tap to edit in place). The honest-import warnings ride the top and
/// commit happens at the bottom.
///
/// The never-invent flags (0014) are shown, not hidden: parse warnings, a
/// degraded image, a truncated source, and each line's own flags.
///
/// The METHOD is editable here too: the editor's own step cards, hosted over
/// the review's draft by [ImportMethodEditing]. Chips key on the preview's
/// `line-<i>` ids and convert back to line indexes at commit.
///
/// The **structure** is the human's as well: a section can be renamed, added
/// and deleted (which never deletes its lines — they move into the section
/// above), and a line the page forgot can be added, taking a flat index past
/// the payload's last. All of that rides `ImportReconciling.sections`; the
/// payload stays the server's word about the page, so `from source:` never
/// starts lying.
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
    // Per-line validity (matched? range picked? unit in the ingredient's
    // allowed set?) + inline unit chips — drives each card's flag, its unit
    // suggestions, AND the Save gate. Read through `AsyncValue.value`, NOT
    // `asData`: a recompute passes through a loading state whose data-only
    // view is null, and reading THAT blinked every card's border, the counter
    // and the Save button on every keystroke. `.value` keeps the last map
    // until the new one lands.
    final validation = ref.watch(importValidationProvider);
    final byLine = validation.value;
    // The method's step cards read the same recipe a save would write — so the
    // "Reads as" fold shows live amounts, and a chip keyed on
    // `previewLineId(i)` resolves without any extra plumbing (seam D4). The
    // measure a line's unit names rides in from the SAME validation map the
    // card prints it from, so the chip sheet cannot say "piece" where the card
    // says "avocado".
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

    // The sections are the HUMAN's, not the payload's: renamed, deleted and
    // added here, holding flat line indexes. `lineAt` is what covers a line
    // the review minted, whose index the payload has no entry for.
    //
    // They render as ONE flat list — a heading row, then its line rows — so a
    // line dragged under another heading is filed under it. Every index a
    // section holds takes a row whether or not a resolution answers for it:
    // the row positions ARE the drag's arithmetic, and a silently skipped row
    // would file the next drop one line off.
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
      // Once you start dragging the list you have finished typing, and a
      // field left focused off the top of the screen asks to be scrolled back
      // to on every keyboard metrics change — which is enough to throw the
      // page to the title while a line further down is being corrected.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          // A list rather than one box: the slivers stay lazy, so a long
          // method's step cards are not all built to show the top of the page.
          sliver: SliverList.list(
            children: [
              // The never-invent strip sits ABOVE the form: with the title an
              // editable field now, it reads as "about the whole import"
              // before the fields begin.
              ImportSourceNotes(payload: payload),
              // The editor's header, hosted by the controller (D4). What
              // only the review knows is drawn around it through the note
              // slot, not inside a copy of it: whether the page printed a
              // serving count, and what it said about the yield —
              // `yield_raw` stays visible as the reference the fields are
              // (or are not) filled from, the same honesty every line card
              // has under it. Nothing here gates Save.
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
              // The count is what the recipe will HAVE — a dropped line is
              // on its way out, and counting it would contradict the greyed
              // card saying so.
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
              // The two doors sit TIGHT under the last line: they belong to
              // the list, not to the screen, and a gap reads as a section
              // break that is not there.
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
/// line index that section holds.
///
/// Both forms of the review build it — the phone's expanding cards and the
/// wide screen's bare rows — because the arithmetic is load-bearing and must
/// not be written twice. **Every index a section holds takes a row** whether or
/// not a resolution answers for it: the row positions ARE the drag's
/// arithmetic, and a silently skipped row would file the next drop one line
/// off.
///
/// [row] is handed the line, its resolution, its validation and its position
/// in this list — the drag index — and returns whatever that screen draws.
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

/// The Save gate, and the one sentence that says why it is shut.
///
/// It is a widget rather than a slab of the body because the wide review draws
/// it as the **lines column's footer** — the number on it is about the lines,
/// and a bar across the source pane would say the page has something to save.
/// Two places, one rule: the gate, its retry and its three labels are written
/// once here, and `buildCommit` re-asserts the same map at the seam so this
/// button is never the only thing holding the invariant.
class ReviewCommitBar extends ConsumerWidget {
  const ReviewCommitBar({required this.state, super.key});

  final ImportReconciling state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(importControllerProvider.notifier);
    // `.value`, never `asData`: a recompute passes through a loading state
    // whose data-only view is null, and reading THAT blinked the button on
    // every keystroke.
    final validation = ref.watch(importValidationProvider);
    final byLine = validation.value;
    final issuesByLine = byLine == null
        ? null
        : {for (final e in byLine.entries) e.key: e.value.issues};
    // The vocab read behind the gate failed and has never answered: Save
    // cannot open, and the count it would otherwise show is the structural
    // one — zero, once every line is matched. "0 line(s) need you" over a
    // disabled button is a wall with no door.
    final unchecked = byLine == null && validation.hasError;
    // Save is gated on EVERY line being valid: matched, range picked, and a
    // unit inside the matched ingredient's allowed set (round-2 #2). While
    // validation has never yet loaded it stays disabled.
    final canSave =
        issuesByLine != null && state.canCommit && allLinesValid(issuesByLine);
    // ONE count, shared with the header's "N to review" (they were two
    // different rules and the header never decremented).
    final outstanding = ref.watch(importOutstandingLinesProvider);
    return FButton(
      // A failed check is the one disabled state with something to do:
      // re-running the read is the whole fix, so the button becomes the retry
      // rather than a dead end.
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

/// One section's heading: the name as an editable field, and the bin.
///
/// **Deleting a heading never deletes its lines** — they move into the
/// section above, which is why the bin needs no confirm. Dropping food is
/// what each line's own bin already does.
///
/// A single UNNAMED section shows no row at all: that is the ordinary shape
/// of a recipe that never divided its ingredients, and an empty field over
/// the first line would be furniture. `＋ section` is the way out of it, and
/// the moment there are two, both are nameable.
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

/// The list's own two doors, tight under the last line: add a line the page
/// forgot, and add a section to put lines in.
///
/// A line added here lands in the LAST section, which is what makes
/// `＋ section` then `＋ ingredient` read as one gesture.
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
    // keyboard shrinks the review under it, and the doors can be unmounted by
    // the time a row is tapped. A `WidgetRef` used after unmount throws
    // (Riverpod 3) and the pick would be lost.
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
          // No words on the review's dock: a review line stores a unit id and
          // has no column for one of the target's own words, so a `blob`
          // picked here could only land as a whole batch. A word is said on
          // the line once the recipe exists, in the editor, where it is stored
          // as the pointer it is (ADR-0018).
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

/// What the extractor could NOT read cleanly: a truncated source, a
/// degraded/poor photo, and the model's own [ReconciliationPayload.parseWarnings]
/// — which were carried all the way to the client and then never rendered,
/// while this file's doc claimed they were shown. Empty when the import came
/// back clean.
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

/// [sourceNotes] at the top of the review — the never-invent flags (0014)
/// belong on screen, not in a log. Each is a reason to look harder at the lines
/// below, so they read as one quiet block rather than an alarm.
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
