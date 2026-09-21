/// *Choose another ▸*: the USDA short-list a person picks from.
///
/// `usda_food` never syncs (ADR-0005), so this is the top few answers to one
/// question, the name in the form's field, ranked by coverage. Candidates with
/// nothing to copy are left out. The sheet only asks and hands back; the form
/// decides what a pick does.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../data/ingredient_providers.dart';
import '../domain/ingredient.dart';
import '../domain/normalize.dart';
import '../domain/usda_probe.dart';

/// Opens the short-list and resolves with the pick, or null when closed without
/// one. [name] is what to ask about: the text in the form's name field, so a
/// rename can be searched before saving. [ingredient] is used only to tag the
/// row's current match and a declined food.
Future<UsdaCandidate?> showUsdaPickSheet(
  BuildContext context, {
  required Ingredient ingredient,
  required String name,
}) => showAnsiSheet<UsdaCandidate>(
  context: context,
  builder: (_) => UsdaPickSheet(ingredient: ingredient, name: name),
);

class UsdaPickSheet extends HookConsumerWidget {
  const UsdaPickSheet({
    required this.ingredient,
    required this.name,
    super.key,
  });

  /// Tagging only — the current match, and a declined food. Never the query.
  final Ingredient ingredient;

  /// The question. The form's own name field, so a rename that has not been
  /// saved is still what USDA is asked about.
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final probe = ref.read(usdaProbeProvider);
    final matchText = normalizeMatchText(name);
    // The probe's default limit is the short-list's five.
    final candidates = useFuture(
      useMemoized(() => probe.search(matchText), [matchText]),
    );

    return AnsiSheetShell(
      title: 'USDA · for “$name”',
      children: [
        const SizedBox(height: 14),
        if (candidates.connectionState != ConnectionState.done)
          Text(
            'asking the server…',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          )
        else
          UsdaCandidateList(
            candidates: candidates.data ?? const [],
            queryName: name,
            current: ingredient,
            onPick: (c) => Navigator.of(context).pop(c),
          ),
        const SizedBox(height: 12),
        Text(
          'picking one fills density + macros from it and names it on the '
          'form — still a stub until you confirm',
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
      ],
    );
  }
}

/// The candidate rows: description, category, and whether the row answers every
/// word of the query. The current match and a declined food are tagged. Public
/// so every surface draws candidates alike. [selected] is a host's highlighted
/// pick; the sheet has none.
class UsdaCandidateList extends StatelessWidget {
  const UsdaCandidateList({
    required this.candidates,
    required this.queryName,
    required this.onPick,
    this.current,
    this.selected,
    super.key,
  });

  final List<UsdaCandidate> candidates;

  /// The name that was asked about — named in the empty state so "nothing
  /// came back" says for what.
  final String queryName;

  /// The row being re-chosen, if any. Its current `usda_fdc:` match reads
  /// *current* and is not offered; a declined food reads *declined* (matched by
  /// label, since the decline keeps no id) and is.
  final Ingredient? current;

  /// The candidate a leg has highlighted, by FDC id.
  final int? selected;

  final ValueChanged<UsdaCandidate> onPick;

  @override
  Widget build(BuildContext context) {
    final offered = [
      for (final c in candidates)
        if (c.hasSomethingToCopy) c,
    ];
    if (offered.isEmpty) {
      return Text(
        'nothing came back for “$queryName” — offline, or nothing close '
        'enough. The server runs the same lookup when the row syncs up.',
        style: ansiMono(size: 11, color: AnsiColors.muted),
      );
    }
    final currentId = usdaFdcId(current?.source);
    final declinedLabel = isUsdaDeclined(current?.source)
        ? current?.sourceLabel
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in offered)
          _CandidateRow(
            candidate: c,
            tag: c.fdcId == currentId
                ? 'current'
                : c.description == declinedLabel
                ? 'declined'
                : c.fit.tag,
            enabled: c.fdcId != currentId,
            selected: c.fdcId == selected,
            onTap: () => onPick(c),
          ),
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.tag,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  final UsdaCandidate candidate;
  final String tag;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = candidate.category;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herbSoft : AnsiColors.surface,
          border: Border.all(
            color: selected ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.description,
                    style: ansiSans(
                      size: 13,
                      color: enabled ? AnsiColors.ink : AnsiColors.muted,
                    ),
                  ),
                  if (category != null && category.isNotEmpty)
                    Text(
                      category,
                      style: ansiMono(size: 10, color: AnsiColors.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(tag, style: ansiMono(size: 10, color: AnsiColors.muted)),
          ],
        ),
      ),
    );
  }
}
