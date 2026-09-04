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
/// `line-<i>` ids and convert back to line indexes at commit; the only thing
/// the review cannot do is mint a brand-new line.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../recipes/presentation/method_editor.dart';
import '../../recipes/presentation/recipe_header_form.dart';
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
import '../domain/preview_recipe.dart';
import '../domain/reconciliation_payload.dart';
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
    final flat = payload.flatLines;
    final byIndex = {for (final r in state.resolutions) r.lineIndex: r};
    // Per-line validity (matched? range picked? unit in the ingredient's
    // allowed set?) + inline unit chips — drives each card's flag, its unit
    // suggestions, AND the Save gate. Read through `AsyncValue.value`, NOT
    // `asData`: a recompute passes through a loading state whose data-only
    // view is null, and reading THAT blinked every card's border, the counter
    // and the Save button on every keystroke. `.value` keeps the last map
    // until the new one lands.
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

    final rows = <Widget>[];
    var flatIndex = 0;
    for (final group in payload.groups) {
      if (group.name != null && group.name!.isNotEmpty) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 2),
            child: Text(
              group.name!,
              style: ansiSerif(
                size: 18,
                color: AnsiColors.herbDeep,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        );
      }
      for (final _ in group.lines) {
        final i = flatIndex;
        rows.add(
          ReviewLineCard(
            key: ValueKey('review-line-$i'),
            line: flat[i],
            resolution: byIndex[i]!,
            validation: byLine?[i],
          ),
        );
        flatIndex++;
      }
    }

    // Save is gated on EVERY line being valid: matched, range picked, and a
    // unit inside the matched ingredient's allowed set (round-2 #2). While
    // validation has never yet loaded it stays disabled — and `buildCommit`
    // re-checks the same map, so the button can't be the only thing holding
    // the invariant.
    final canSave =
        issuesByLine != null && state.canCommit && allLinesValid(issuesByLine);
    // ONE count, shared with the header's "N to review" (they were two
    // different rules and the header never decremented).
    final outstanding = ref.watch(importOutstandingLinesProvider);

    final source = payload.yieldRaw?.trim();
    final sourceStated = source != null && source.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        // The never-invent strip sits ABOVE the form: with the title an
        // editable field now, it reads as "about the whole import" before the
        // fields begin.
        _SourceNotes(payload: payload),
        // The editor's header, hosted by the controller (D4). What only the
        // review knows is drawn around it through the note slot, not inside
        // a copy of it: whether the page printed a serving count, and what it
        // said about the yield — `yield_raw` stays visible as the reference
        // the fields are (or are not) filled from, the same honesty every
        // line card has under it. Nothing here gates Save.
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
                      'unset. Nothing is invented, and a yield-less recipe '
                      'still saves, links and scales; only the derived '
                      'numbers wait.'
                : 'the page didn’t say what this makes — set it, or leave '
                      'it unset. Nothing is invented, and a yield-less '
                      'recipe still saves, links and scales.',
          ),
        ),
        const SizedBox(height: 10),
        // The count is what the recipe will HAVE — a dropped line is on its way
        // out, and counting it would contradict the greyed card saying so.
        _SectionHeader(
          label: 'Ingredients',
          count: keptLines(state.resolutions).length,
        ),
        ...rows,
        const SizedBox(height: 24),
        MethodEditor(recipe: recipe, notifier: methodHost),
        const SizedBox(height: 20),
        FButton(
          // A failed check is the one disabled state with something to do:
          // re-running the read is the whole fix, so the button becomes the
          // retry rather than a dead end.
          onPress: canSave
              ? () => controller.commit(issuesByLine: issuesByLine)
              : unchecked
              ? () => ref.invalidate(importValidationProvider)
              : null,
          child: Text(
            canSave
                ? 'Save recipe'
                : keptLines(state.resolutions).isEmpty
                // Every line dropped: the count would read "0 line(s) need
                // you", which is true and useless.
                ? 'Nothing left to save'
                : unchecked
                ? 'Couldn’t check the lines — try again'
                : '$outstanding line(s) need you',
          ),
        ),
      ],
    );
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
class _SourceNotes extends StatelessWidget {
  const _SourceNotes({required this.payload});

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
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

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
