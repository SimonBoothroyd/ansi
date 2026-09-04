/// *Choose another ▸* — the USDA short-list a person picks from (plan 0027
/// **U-D3**, board frame c), and the candidate rows the New-ingredient
/// sheet's USDA leg draws too (**U-D7**, frame d).
///
/// `usda_food` never syncs to a device (ADR-0005), so this is not a browser
/// over the reference set: it is the top few answers to ONE question — the
/// row's match text — in the same total order the prefill trigger uses, so
/// the first row is what the trigger picked and the rest are what it would
/// have picked had each earlier one not existed. Candidates with nothing to
/// copy (a name and no numbers) are left out: picking one could fill
/// nothing, and the trigger never offers them either.
///
/// The sheet only *asks and hands back*. The write — `applyUsdaProbe` with
/// the explicit-pick guard lifted — belongs to the form that opened it, so
/// there is one place that decides what a pick does to a row.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../data/ingredient_providers.dart';
import '../domain/ingredient.dart';
import '../domain/normalize.dart';
import '../domain/usda_probe.dart';

/// Opens the short-list and resolves with the pick, or null when the sheet
/// was closed without one.
///
/// [name] is what to ASK about — the form passes the text in its name field,
/// not the stored row. That is what retired **F1**: the lookup used to have
/// to save the form first, because it probed the row's stored name and a
/// rename sitting unsaved meant it asked about the old one. A query taken
/// from the field cannot be stale, so nothing has to be written before you
/// may look something up.
///
/// [ingredient] is still needed, but only to TAG: the row's current match is
/// marked rather than offered again, and a food the household declined is
/// marked as refused.
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
    // The probe's default limit IS "the next five" (U-D3).
    final candidates = useFuture(
      useMemoized(() => probe.search(matchText), [matchText]),
    );

    return Container(
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(FLucideIcons.x, size: 22),
              ),
              Expanded(
                child: Text(
                  'USDA · for “$name”',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: ansiSerif(size: 18),
                ),
              ),
              const SizedBox(width: 22),
            ],
          ),
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
      ),
    );
  }
}

/// The candidate rows: description, category, and the band word — with the
/// row's own current match tagged rather than offered again, and the food a
/// person declined tagged so they can see what they said no to.
///
/// Shared between the pick sheet and the New-ingredient sheet's USDA leg,
/// so "what a USDA row looks like" has one answer. [selected] is the leg's
/// highlighted pick (the sheet has none — a tap there pops).
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

  /// The row being re-chosen, if any: its current `usda_fdc:` match reads
  /// *current* and is not offered; a declined row's refused food reads
  /// *declined* (matched by label — the decline keeps no id) and is.
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
                : c.band.word,
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
