/// The v3 review screen (owner refinement): ONE editable surface. There is no
/// separate triage/preview split any more — the imported recipe is reviewed and
/// confirmed here, every line an expandable [ReviewLineCard] (compact by
/// default, tap to edit in place). The honest-import warnings ride the top and
/// commit happens at the bottom.
///
/// The never-invent flags (0014) are shown, not hidden: parse warnings, a
/// degraded image, a truncated source, and each line's own flags.
///
/// The METHOD is editable here too (seam D4): the shipped editor v2 step
/// cards, hosted over the review's own draft by `ImportMethodEditing`. Chips
/// key on the preview's `line-<i>` ids and convert back to line indexes at
/// commit; the only thing the review cannot do is mint a brand-new line.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../recipes/presentation/format.dart';
import '../../recipes/presentation/method_editor.dart';
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
    final byLine = ref.watch(importValidationProvider).value;
    final issuesByLine = byLine == null
        ? null
        : {for (final e in byLine.entries) e.key: e.value.issues};
    // The method's step cards read the same recipe a save would write — so
    // the "Reads as" fold shows live amounts, and a chip keyed on
    // `previewLineId(i)` resolves without any extra plumbing (seam D4).
    final recipe = buildPreviewRecipe(
      payload,
      state.resolutions,
      servingsBase: state.servings,
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text(
          payload.title.isEmpty ? 'Untitled recipe' : payload.title,
          style: ansiSerif(size: 28, weight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        _SourceNotes(payload: payload),
        _ServingsRow(state: state, onChanged: controller.setServings),
        const SizedBox(height: 12),
        _MakesRow(state: state, onChanged: controller.setYield),
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
          onPress: canSave
              ? () => controller.commit(issuesByLine: issuesByLine)
              : null,
          child: Text(
            canSave
                ? 'Save recipe'
                : keptLines(state.resolutions).isEmpty
                // Every line dropped: the count would read "0 line(s) need
                // you", which is true and useless.
                ? 'Nothing left to save'
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

class _ServingsRow extends StatelessWidget {
  const _ServingsRow({required this.state, required this.onChanged});

  final ImportReconciling state;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final unclear = state.payload.servingsBase == null;
    return Row(
      children: [
        Text('SERVES', style: ansiLabel()),
        if (unclear) ...[
          const SizedBox(width: 8),
          Text(
            'not printed — set it',
            style: ansiMono(size: 10, color: AnsiColors.aging),
          ),
        ],
        const Spacer(),
        FButton.icon(
          onPress: state.servings > 1
              ? () => onChanged(state.servings - 1)
              : null,
          child: const Icon(FLucideIcons.minus),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            formatQuantity(state.servings),
            style: ansiSans(size: 17, weight: FontWeight.w700),
          ),
        ),
        FButton.icon(
          onPress: () => onChanged(state.servings + 1),
          child: const Icon(FLucideIcons.plus),
        ),
      ],
    );
  }
}

/// The MAKES row (step 8.6 / D2 · D9, design board frame h — the Review half),
/// under SERVES: what one batch of this recipe makes.
///
/// It is the editor's row wearing the review screen's honesty: the `yield_raw`
/// SOURCE LINE stays visible above the fields, and the fields themselves are
/// prefilled ONLY from a plain `amount + known unit` ("MAKES: 8 SLIDERS" → 8
/// piece). Anything fancier — "MAKES ENOUGH FOR A CROWD" — leaves them empty
/// over that visible text and waits for a human: 0014's attempt-then-flag, the
/// same pattern servings uses three lines up. A wrong yield would silently
/// poison every derived batch, session and shopping number downstream; an
/// empty one is honest and one tap from right.
///
/// The row is deliberately NOT the editor widget itself: only the review has
/// an unset UNIT to render ("— ▾"), because only here does the field start
/// from what a page printed rather than from a stated fact. The optional
/// SECOND denomination is the editor's (frame h's other half) — one row here,
/// as drawn.
///
/// The yield NEVER gates Save.
class _MakesRow extends StatelessWidget {
  const _MakesRow({required this.state, required this.onChanged});

  final ImportReconciling state;
  final void Function(double? qty, Unit? unit) onChanged;

  /// The units a yield may be stated in — everything an ingredient line can
  /// say except the imprecise words ("makes a pinch" is not a yield) and
  /// `batch`, which is what a yield is measured *against*, never in.
  static final List<Unit> _units = [
    for (final u in kIngredientUnits)
      if (u.family != UnitFamily.imprecise) u,
  ];

  @override
  Widget build(BuildContext context) {
    final source = state.payload.yieldRaw?.trim();
    final unit = state.yieldUnit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('MAKES', style: ansiLabel()),
            const SizedBox(width: 6),
            Text(
              '· optional',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ],
        ),
        // What the page actually said, always visible — the reference the
        // fields are (or are not) filled from.
        if (source != null && source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'from source:  $source',
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              width: 110,
              child: FTextField(
                hint: '—',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(
                    text: formatQuantity(state.yieldQty),
                  ),
                  onChange: (v) {
                    final text = v.text.trim();
                    onChanged(
                      text.isEmpty ? null : double.tryParse(text),
                      // Typing a number before touching the unit means the
                      // count the page named: `piece` is the honest default,
                      // and it is one tap from anything else.
                      unit ?? pieces,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FSelect<String>.rich(
                // No unit yet reads as "—", never as a plausible-looking one.
                format: (id) => unitById(id)?.label ?? '—',
                control: FSelectControl<String>.lifted(
                  value: unit?.id,
                  onChange: (id) {
                    final picked = id == null ? null : unitById(id);
                    if (picked != null) onChanged(state.yieldQty, picked);
                  },
                ),
                children: [
                  for (final u in _units)
                    FSelectItem(title: Text(u.label), value: u.id),
                ],
              ),
            ),
          ],
        ),
        if (state.yieldQty == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              source == null || source.isEmpty
                  ? 'the page didn’t say what this makes — set it, or leave '
                        'it unset. Nothing is invented, and a yield-less '
                        'recipe still saves, links and scales.'
                  : 'the page didn’t say a number — set one, or leave it '
                        'unset. Nothing is invented, and a yield-less recipe '
                        'still saves, links and scales; only the derived '
                        'numbers wait.',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
      ],
    );
  }
}
