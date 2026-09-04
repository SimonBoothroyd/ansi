/// Saying what one review line IS: the ingredient it resolved to, or the
/// candidates and the seeded search that answer it.
///
/// [Resolver] is the identity cell of a review line card — the chosen
/// ingredient (the whole row taps to re-match), the server's candidate chips,
/// or a recipe-title offer that turns the line into a component. Tapping into
/// it opens [showReconcileIngredientSheet], the seeded search with the
/// create-new door, which resolves to a [ReconcilePick] and writes nothing.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/picker_shell.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../../recipes/presentation/recipe_chip.dart';
import '../domain/line_resolution.dart';
import '../domain/reconciliation_payload.dart';

/// The band-appropriate resolver: the chosen ingredient (the whole row taps to
/// re-match) or, unresolved, the candidate chips / seeded-search entry point.
/// Resolving is delegated up so a caller could write several lines at once.
class Resolver extends StatelessWidget {
  const Resolver({
    required this.candidates,
    required this.resolution,
    required this.onResolveExisting,
    this.recipeCandidates = const [],
    this.onLinkRecipe,
    this.onUnlink,
    super.key,
  });

  final List<MatchCandidate> candidates;

  /// The household recipes the server thinks this line names (8.6 / D6).
  /// Rendered as chips in the SAME did-you-mean row, never instead of the
  /// ingredient ones — a line can be either, and the human says which.
  final List<RecipeCandidate> recipeCandidates;

  final LineResolution resolution;

  /// Resolves the line to a vocabulary row — a candidate, a search hit, or the
  /// row the create-new chain just made in the ingredient form, which lands on
  /// the line as the ordinary matched state.
  final void Function(String id, String name, {required bool correction})
  onResolveExisting;

  /// Links the line to the tapped recipe. Null where linking is not offered.
  final ValueChanged<RecipeCandidate>? onLinkRecipe;

  /// Un-links a linked line, back to the plain text it arrived as.
  final VoidCallback? onUnlink;

  Future<void> _openSearch(BuildContext context) async {
    final pick = await showReconcileIngredientSheet(
      context,
      seedName: resolution.ingredientText,
      candidates: candidates,
    );
    if (pick == null) return;
    switch (pick) {
      case PickExisting(:final ingredient):
        // A search override of the band's match is a correction → alias write.
        onResolveExisting(
          ingredient.id,
          ingredient.canonicalName,
          correction: true,
        );
      case PickCandidate(:final candidate):
        onResolveExisting(
          candidate.ingredientId,
          candidate.canonicalName,
          correction: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // LINKED: the identity cell is the recipe chip, with the same
    // tap-the-row-to-re-match affordance a chosen ingredient has (picking an
    // ingredient un-links it, D1's XOR) and an explicit unlink beside it, so
    // the decision is reversible right up to Save.
    if (resolution.isComponent) {
      return _LinkedRecipe(
        title: resolution.linkedRecipeTitle ?? resolution.ingredientText,
        onTap: () => _openSearch(context),
        onUnlink: onUnlink,
      );
    }
    if (resolution.chosenIngredientId != null) {
      return _Chosen(
        label: resolution.chosenName ?? 'Matched',
        onTap: () => _openSearch(context),
      );
    }

    final offers = onLinkRecipe == null
        ? const <RecipeCandidate>[]
        : recipeCandidates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (candidates.isNotEmpty || offers.isNotEmpty) ...[
          Text('Did you mean', style: ansiLabel()),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // The recipe offers lead the row — a line that names one of your
              // own recipes usually means it — but they never replace the
              // ingredient candidates beside them.
              for (final c in offers)
                ReconPill(
                  icon: kSubRecipeIcon,
                  label: 'your recipe · ${c.title}',
                  onTap: () => onLinkRecipe!(c),
                ),
              for (final c in candidates)
                ReconPill(
                  label: c.canonicalName,
                  onTap: () => onResolveExisting(
                    c.ingredientId,
                    c.canonicalName,
                    correction: false,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        FButton(
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          prefix: const Icon(FLucideIcons.search),
          onPress: () => _openSearch(context),
          child: Text(
            candidates.isEmpty && offers.isEmpty
                ? 'Find or create ingredient'
                : 'Something else',
          ),
        ),
      ],
    );
  }
}

/// The resolved ingredient — the WHOLE row is the re-match affordance now (the
/// tiny "change" link is gone): tap the ✓/＋ ingredient to open the picker.
class _Chosen extends StatelessWidget {
  const _Chosen({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AnsiColors.paper,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Icon(FLucideIcons.check, size: 15, color: AnsiColors.herb),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: ansiSans(size: 14, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // A quiet hint that the row itself re-matches — the affordance is
              // the whole tap target, not a separate control.
              Text(
                'tap to change',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
              const SizedBox(width: 4),
              const Icon(
                FLucideIcons.chevronRight,
                size: 14,
                color: AnsiColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A LINKED line's identity cell: lane U's recipe chip, the whole row a
/// re-match target (picking an ingredient un-links it — one identity, D1), and
/// an explicit unlink so the offer can be taken back without hunting for the
/// ingredient the line never had.
class _LinkedRecipe extends StatelessWidget {
  const _LinkedRecipe({
    required this.title,
    required this.onTap,
    this.onUnlink,
  });

  final String title;
  final VoidCallback onTap;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Row(
                  children: [
                    Flexible(child: RecipeChip(title: title, size: 14)),
                    const SizedBox(width: 8),
                    Text(
                      'tap to change',
                      style: ansiMono(size: 10, color: AnsiColors.muted),
                    ),
                  ],
                ),
              ),
            ),
            if (onUnlink != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUnlink,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        FLucideIcons.undo2,
                        size: 13,
                        color: AnsiColors.herb,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'unlink',
                        style: ansiMono(size: 11, color: AnsiColors.herb),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One tappable offer on a review card — a candidate ingredient, a recipe the
/// line might name, or a unit the card suggests. Shared with the card so the
/// two rows of offers read as the same kind of answer.
class ReconPill extends StatelessWidget {
  const ReconPill({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.quiet = false,
    super.key,
  });

  final String label;

  /// A leading glyph — the sub-recipe mark on a recipe offer, so the chip
  /// reads as a different KIND of answer, not another ingredient.
  final IconData? icon;

  /// The chip carries the line's current value — filled, so a selection stays
  /// visible when the fold reorders the row around it.
  final bool selected;

  /// A chrome chip (the fold's "more") rather than a choice — it reads mono and
  /// muted so it never looks like one of the units.
  final bool quiet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herbSoft : AnsiColors.surface,
          border: Border.all(
            color: selected ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: AnsiColors.herb),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: quiet
                      ? ansiMono(size: 11, color: AnsiColors.muted)
                      : ansiSans(
                          size: 13,
                          color: selected
                              ? AnsiColors.herbDeep
                              : AnsiColors.ink,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- The seeded search / create-new sheet ------------------------------------

/// A reconciliation pick: a server candidate, or an existing vocab ingredient —
/// which is also what the create-new footer hands back, once the row exists and
/// the flesh-out form has been walked.
sealed class ReconcilePick {
  const ReconcilePick();
}

class PickCandidate extends ReconcilePick {
  const PickCandidate(this.candidate);
  final MatchCandidate candidate;
}

class PickExisting extends ReconcilePick {
  const PickExisting(this.ingredient);
  final Ingredient ingredient;
}

/// Opens the vocab search sheet PRE-SEEDED with this line's [candidates] +
/// recents + create-new — never blank (decision 5). Resolves to a
/// [ReconcilePick] or null if dismissed.
///
/// Create-new is the picker's own add-new chain: the ingredient form with the
/// line's text prefilled, pushed over THIS sheet and awaited, and the row it
/// pops resolved as a [PickExisting] — the ordinary matched state, no special
/// case. Nothing is deferred to commit: a line cannot carry a name instead of
/// an id, so there is nothing to coalesce there.
Future<ReconcilePick?> showReconcileIngredientSheet(
  BuildContext context, {
  required String seedName,
  List<MatchCandidate> candidates = const [],
}) {
  return showAnsiSheet<ReconcilePick>(
    context: context,
    builder: (_) => _ReconcileSheet(seedName: seedName, candidates: candidates),
  );
}

class _ReconcileSheet extends HookConsumerWidget {
  const _ReconcileSheet({required this.seedName, required this.candidates});

  final String seedName;
  final List<MatchCandidate> candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);
    // The seeded candidates lead the list before any query; once the user
    // types, their own search takes over.
    final showSuggested = candidates.isNotEmpty && search.query.trim().isEmpty;

    return PickerShell(
      title: 'Match "$seedName"',
      searchHint: 'Search ingredients',
      searchAutofocus: true,
      onQueryChanged: search.run,
      aboveList: showSuggested
          ? _SuggestedForLine(
              candidates: candidates,
              onPick: (c) => Navigator.of(context).pop(PickCandidate(c)),
            )
          : null,
      body: IngredientResultList(
        results: search.results,
        query: search.query,
        showingRecents: search.showingRecents,
        onPick: (ing) => Navigator.of(context).pop(PickExisting(ing)),
      ),
      // The picker footer's own row, in its `.addnew` voice — it no longer
      // creates a stub-by-default, so it no longer reads like one. Seeded
      // with the query, else the raw line text, so "curry leaves" becomes the
      // row without retyping.
      footer: AddNewIngredientRow(
        query: search.query.trim().isEmpty ? seedName : search.query,
        label: (name) => 'create "$name" as a new ingredient',
        onCreated: (ing) => Navigator.of(context).pop(PickExisting(ing)),
      ),
    );
  }
}

/// The "Suggested for this line" block — the line's server candidates, offered
/// before the user searches so the picker opens with the likely answers.
class _SuggestedForLine extends StatelessWidget {
  const _SuggestedForLine({required this.candidates, required this.onPick});

  final List<MatchCandidate> candidates;
  final ValueChanged<MatchCandidate> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SUGGESTED FOR THIS LINE', style: ansiLabel()),
          const SizedBox(height: 4),
          for (final c in candidates)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.canonicalName,
                        style: ansiSans(size: 15, weight: FontWeight.w600),
                      ),
                    ),
                    const Icon(
                      FLucideIcons.plus,
                      size: 18,
                      color: AnsiColors.herb,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
