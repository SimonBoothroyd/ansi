/// The ingredient picker (step 7.7): top-anchored search over the synced
/// vocabulary, a Recent section before any
/// query, information-honest result rows (category · capability hints · a
/// per-100 macro line for complete rows, a `stub` badge — never zeros), and
/// the add-new affordance.
///
/// Search is the shared [searchRank] rule, in the repository. When nothing was
/// spelled right the guarded typo tier answers instead, and those rows arrive
/// under a `DID YOU MEAN` header — the phone offers a guess for a human to
/// pick, it never resolves on one (ADR-0004).
///
/// **Add-new is one chain, everywhere**: the footer pushes the ingredient form
/// with the query prefilled and *waits for back*, and the row the form pops is
/// what reaches the host — so the quantity sheet that follows offers the units
/// the form just set. No path mints a stub as a side effect of something else;
/// the form is on the way, not a detour.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/search/search_query.dart';
import '../../../core/search/search_rank.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/picker_shell.dart';
import '../../../shared/write.dart' show hostContextOf;
import '../data/ingredient_providers.dart';
import '../domain/ingredient.dart';
import 'ingredient_detail_view.dart' show newIngredientRoute;
import 'macros_format.dart';

/// Opens the picker as a bottom sheet; resolves to the chosen ingredient — an
/// existing row, or one the add-new chain just created and fleshed out — or
/// null if dismissed. [title] carries the destination context ('Add to "for
/// the curry"').
Future<Ingredient?> showIngredientPicker(
  BuildContext context, {
  String title = 'Add an ingredient',
}) {
  return showAnsiSheet<Ingredient>(
    context: context,
    builder: (_) => _IngredientPickerSheet(title: title),
  );
}

/// The search state both hosts share (the picker sheet and the shopping
/// top-up embed): query text, results, whether the results are the recents
/// feed (empty query) or a search, and whether the search had to guess.
({
  String query,
  List<Ingredient> results,
  bool showingRecents,
  bool guessed,
  Future<void> Function(String) run,
})
useIngredientSearch(WidgetRef ref, BuildContext context) {
  final query = useState('');
  final results = useState<List<Ingredient>>(const []);
  final showingRecents = useState(false);
  final guessed = useState(false);
  // Monotonic ticket so a slow older search can never overwrite a newer
  // one's results (or touch state after the host is dismissed).
  final searchSeq = useRef(0);

  Future<void> run(String q) async {
    query.value = q;
    final ticket = ++searchSeq.value;
    final repo = ref.read(ingredientRepositoryProvider);
    // Empty query → the recents feed; an unused vocab falls back to the
    // plain alphabetical list so the picker is never blank.
    var recents = false;
    var found = <Ingredient>[];
    var guesses = false;
    if (q.trim().isEmpty) {
      found = await repo.recentlyUsed();
      recents = found.isNotEmpty;
    }
    if (found.isEmpty) {
      final matches = await repo.search(q);
      found = matches.rows;
      guesses = matches.guessed;
    }
    if (!context.mounted || ticket != searchSeq.value) return;
    showingRecents.value = recents;
    guessed.value = guesses;
    results.value = found;
  }

  useEffect(() {
    run('');
    return null;
  }, const []);

  return (
    query: query.value,
    results: results.value,
    showingRecents: showingRecents.value,
    guessed: guessed.value,
    run: run,
  );
}

class _IngredientPickerSheet extends HookConsumerWidget {
  const _IngredientPickerSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);

    return PickerShell(
      title: title,
      searchHint: 'Search ingredients',
      searchAutofocus: true,
      onQueryChanged: search.run,
      body: IngredientResultList(
        results: search.results,
        query: search.query,
        showingRecents: search.showingRecents,
        guessed: search.guessed,
        onPick: (ing) => Navigator.of(context).pop(ing),
      ),
      footer: AddNewIngredientRow(
        query: search.query,
        onCreated: (ing) => Navigator.of(context).pop(ing),
      ),
    );
  }
}

/// The scrolling results — frame-a rows, with the Recent header before any
/// query.
///
/// [trailing] is the one extension point (step 8.6 / D7, board frame c): a
/// section rendered UNDER the ingredient rows in the same scroll view — the
/// "Your recipes" section the line picker adds. Nothing else about the list
/// moves; when it is empty this is the shipped 7.7 list exactly.
class IngredientResultList extends StatelessWidget {
  const IngredientResultList({
    required this.results,
    required this.query,
    required this.showingRecents,
    required this.onPick,
    this.guessed = false,
    this.trailing = const [],
    super.key,
  });

  final List<Ingredient> results;
  final String query;
  final bool showingRecents;
  final ValueChanged<Ingredient> onPick;

  /// Whether [results] are the typo tier's guesses rather than spellings.
  /// True only when nothing was spelled right, so the band is the whole list
  /// or it is absent — a guess is never a tail under real hits.
  final bool guessed;

  /// Extra sections below the ingredient rows.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty && trailing.isEmpty) return _EmptyState(query: query);
    return ListView(
      children: [
        if (showingRecents)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('RECENT', style: ansiLabel()),
          )
        // Nothing was spelled right, so say so above the rows. The header is
        // the whole reason a four-character floor is safe: it is the
        // difference between "we found this" and "we guessed this".
        else if (guessed && results.isNotEmpty)
          const DidYouMeanHeader()
        // With a second section below, the ingredient rows need a name of
        // their own — the board's frame-c header. Without one they are the
        // whole list and labelling them would be noise.
        else if (trailing.isNotEmpty && results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('INGREDIENTS', style: ansiLabel()),
          ),
        for (final (i, ing) in results.indexed) ...[
          if (i > 0) Container(height: 1, color: AnsiColors.line),
          IngredientRow(ingredient: ing, onPick: onPick),
        ],
        ...trailing,
      ],
    );
  }
}

/// An empty result list is an ANSWER, not a failure — "nothing here is a
/// chicken thigh" is the honest reply from a vegan vocabulary. When the query
/// was also too short for the rule to guess at, it says that too, so the
/// silence is legible rather than mysterious.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final tokens = searchTokens(query);
    final floor = tokens.length == 1
        ? kMinFuzzTokenLenSingle
        : kMinFuzzTokenLenMulti;
    final tooShortToGuess =
        tokens.isNotEmpty && tokens.every((t) => t.length < floor);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            query.isEmpty ? 'No ingredients yet.' : 'No match for "$query".',
            textAlign: TextAlign.center,
            style: ansiMono(size: 12, color: AnsiColors.muted),
          ),
          if (tooShortToGuess) ...[
            const SizedBox(height: 6),
            Text(
              'Too few letters to guess from — try spelling it out.',
              textAlign: TextAlign.center,
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The muted second line under a vocabulary row: the category, what the row
/// can convert, how many measures it carries, and whether its macros are
/// still missing — joined with ` · `, and empty when there is nothing to say.
///
/// Every clause is a fact already on the row, never a judgement about it: a
/// row with no density is described, not scolded, and a stub says what it is
/// short of rather than showing a line of zeros.
///
/// [advisoryDensityGap] makes a missing density a clause of its own. Only a
/// screen that can fix it asks for it — the manager list passes true, the
/// picker leaves it false, because an advisory nobody can act on is noise.
String vocabRowHints(Ingredient ing, {bool advisoryDensityGap = false}) => [
  if (ing.category != null) ing.category!,
  if (ing.densityGPerMl != null)
    'has density'
  else if (advisoryDensityGap)
    'no density — volume units locked',
  if (ing.measureCount > 0)
    '${ing.measureCount} ${plural(ing.measureCount, 'measure')}',
  if (ing.status == IngredientStatus.stub) 'needs macros — no zeros shown',
].join(' · ');

/// One dense, information-honest result row: name (+`stub` badge), category
/// and capability hints, and a per-100 macro line for complete rows.
///
/// Shared by the picker (7.7) and the ingredients manager list (8.5) — the
/// two must read alike or the same ingredient tells two stories. Only the
/// trailing affordance differs: the picker adds, the manager navigates.
class IngredientRow extends StatelessWidget {
  const IngredientRow({
    required this.ingredient,
    required this.onPick,
    this.trailing,
    this.advisoryDensityGap = false,
    super.key,
  });

  final Ingredient ingredient;
  final ValueChanged<Ingredient> onPick;

  /// Defaults to the picker's `+`. The manager passes a chevron.
  final Widget? trailing;

  /// Whether a missing density is worth saying out loud. The manager list says
  /// it ("no density — volume units locked") because it is the screen that can
  /// fix it; the picker stays quiet because it can't (this is an advisory,
  /// never a completion blocker).
  final bool advisoryDensityGap;

  @override
  Widget build(BuildContext context) {
    final ing = ingredient;
    final stub = ing.status == IngredientStatus.stub;
    final macros = ing.macros;
    final hints = vocabRowHints(ing, advisoryDensityGap: advisoryDensityGap);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPick(ing),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          ing.canonicalName,
                          style: ansiSans(size: 15, weight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (stub) ...[
                        const SizedBox(width: 6),
                        const StubBadge(),
                      ],
                    ],
                  ),
                  if (hints.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hints,
                      style: ansiMono(size: 10, color: AnsiColors.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Honest numbers: only a complete row shows a macro line.
                  if (!stub && macros != null) ...[
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        text: formatMacroLine(macros),
                        style: ansiMono(size: 10, color: AnsiColors.herbDeep),
                        children: [
                          TextSpan(
                            text: ' ${macroBasisSuffix(ing.macrosBasis)}',
                            style: ansiMono(size: 10, color: AnsiColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                const Icon(FLucideIcons.plus, size: 18, color: AnsiColors.herb),
          ],
        ),
      ),
    );
  }
}

/// "＋ can't find it? add a new ingredient" — the add-new chain's front door in
/// every picker. Disabled until something is typed.
///
/// Tapping it writes nothing here. It pushes the ingredient form with the query
/// prefilled and WAITS for back — the only exit — and whatever the form pops
/// goes to [onCreated]: the row it created, with the units, measures and
/// density it set, or null if the person backed out, in which case nothing was
/// written and nothing resolves.
///
/// Needs a router in scope — every host that embeds it is under one.
class AddNewIngredientRow extends HookConsumerWidget {
  const AddNewIngredientRow({
    required this.query,
    required this.onCreated,
    this.label,
    super.key,
  });

  final String query;

  /// Receives the row as the form left it. Not called when the row was
  /// deleted on the form — there is nothing to hand back, and the host is
  /// simply back where it was.
  final ValueChanged<Ingredient> onCreated;

  /// The row's wording for a name, when the host's voice differs from the
  /// picker footer's default ("can’t find it? add "X" as a new ingredient").
  final String Function(String name)? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = query.trim();
    // The chain is modal end to end, but two taps in one frame would open
    // two sheets. The row goes inert for the duration instead.
    final busy = useState(false);
    final enabled = name.isNotEmpty && !busy.value;

    Future<void> addNew() async {
      busy.value = true;
      // The chain crosses two awaits with a keyboard in each; the handles
      // it continues through outlive this row (`hostContextOf`), so the
      // row the human just fleshed out is handed back whatever became of
      // the footer that started it.
      final host = hostContextOf(context);
      try {
        // ONE push, not a sheet and then a form. The form is the create surface
        // now: it lands ABOVE this picker's sheet, writes nothing until Save,
        // and pops with the row it made — so backing out resolves nothing and
        // leaves nothing behind, which the sheet could not offer because its
        // Create had already written a row.
        //
        // The picker stays open underneath the whole time, which is what lets
        // it resolve after. The host outlives the row (`hostContextOf`).
        // ignore: use_build_context_synchronously
        final created = await host.context.pushOnceFor<Ingredient?>(
          newIngredientRoute(name: name),
        );
        if (created == null) return;
        // The popped row IS the row as that one write left it — allowed
        // units, measures, a density, the macros — which is exactly what the
        // quantity sheet opening next must see. Re-reading is what the old
        // two-step needed, because the sheet handed over a row that predated
        // everything the form then did to it.
        onCreated(created);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? addNew : null,
      child: DashedBorderBox(
        color: enabled ? AnsiColors.herb : AnsiColors.line,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FLucideIcons.plus,
              size: 12,
              color: enabled ? AnsiColors.herb : AnsiColors.muted,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                enabled
                    ? (label?.call(name) ??
                          'can’t find it? add "$name" as a new ingredient')
                    : 'can’t find it? type a name to add it',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: ansiMono(
                  size: 11,
                  color: enabled ? AnsiColors.herb : AnsiColors.muted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StubBadge extends StatelessWidget {
  const StubBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return FBadge(
      variant: FBadgeVariant.secondary,
      child: Text('stub', style: ansiMono(size: 10, color: AnsiColors.muted)),
    );
  }
}
