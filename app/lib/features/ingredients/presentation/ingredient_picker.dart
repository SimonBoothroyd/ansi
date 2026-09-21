/// The ingredient picker: top-anchored search over the synced vocabulary, a
/// Recent section before any query, result rows with hints and a per-100 macro
/// line (a `stub` badge, never zeros), and the add-new door.
///
/// Search is the shared [searchRank] rule, in the repository. Typo-tier results
/// arrive under a `DID YOU MEAN` header; the app offers a guess for a human to
/// pick and never resolves on one (ADR-0004). Add-new pushes the ingredient
/// form with the query prefilled and waits for the row it pops.
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
import 'macro_line_text.dart';
import 'macros_format.dart';

/// Opens the picker as a bottom sheet. Resolves to the chosen ingredient,
/// existing or just created, or null if dismissed. [title] carries the
/// destination context ('Add to "for the curry"').
Future<Ingredient?> showIngredientPicker(
  BuildContext context, {
  String title = 'Add an ingredient',
}) {
  return showAnsiSheet<Ingredient>(
    context: context,
    builder: (_) => _IngredientPickerSheet(title: title),
  );
}

/// The search state both hosts share: query text, results, whether they are the
/// recents feed or a search, and whether the search had to guess.
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

/// The scrolling results, with the Recent header before any query. [trailing]
/// is a section rendered under the ingredient rows in the same scroll view,
/// e.g. the line picker's "Your recipes".
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

  /// Whether [results] are typo-tier guesses. True only when nothing was
  /// spelled right, so guesses are the whole list or absent.
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
        // Nothing was spelled right; the header says these are guesses.
        else if (guessed && results.isNotEmpty)
          const DidYouMeanHeader()
        // With a second section below, the ingredient rows get a header of
        // their own.
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

/// An empty result list is an answer, not a failure. When the query was also
/// too short to guess at, it says so.
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

/// The muted second line under a vocabulary row: category, what the row can
/// convert, its measure count, and whether macros are missing, joined with ` ·
/// `. Empty when there is nothing to say.
///
/// [advisoryDensityGap] adds a clause for a missing density; only the manager
/// list, which can fix it, passes true. [showCategory] is false under a section
/// header that already said it.
String vocabRowHints(
  Ingredient ing, {
  bool advisoryDensityGap = false,
  bool showCategory = true,
}) => [
  if (showCategory && ing.category != null) ing.category!,
  if (ing.densityGPerMl != null)
    'has density'
  else if (advisoryDensityGap)
    'no density — volume units locked',
  if (ing.measureCount > 0)
    '${ing.measureCount} ${plural(ing.measureCount, 'measure')}',
  if (ing.status == IngredientStatus.stub) 'needs macros — no zeros shown',
].join(' · ');

/// One dense result row: name (+`stub` badge), hints, and a per-100 macro line
/// for complete rows. Shared by the picker and the ingredients manager list;
/// only the trailing affordance differs.
class IngredientRow extends StatelessWidget {
  const IngredientRow({
    required this.ingredient,
    required this.onPick,
    this.trailing,
    this.advisoryDensityGap = false,
    this.showSource = false,
    this.showCategory = true,
    super.key,
  });

  final Ingredient ingredient;
  final ValueChanged<Ingredient> onPick;

  /// Defaults to the picker's `+`. The manager passes a chevron.
  final Widget? trailing;

  /// Whether a missing density is said out loud. True on the manager list,
  /// which can fix it; an advisory, never a completion blocker.
  final bool advisoryDensityGap;

  /// Whether to name the USDA food behind a machine-filled row
  /// ([sourceProvenanceLine]). True on the manager list; the picker omits it as
  /// noise while typing.
  final bool showSource;

  /// Whether the fact line opens with the row's category. False under a section
  /// header that already said it.
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final ing = ingredient;
    final stub = ing.status == IngredientStatus.stub;
    final macros = ing.macros;
    final hints = vocabRowHints(
      ing,
      advisoryDensityGap: advisoryDensityGap,
      showCategory: showCategory,
    );
    final sourceLine = showSource ? sourceProvenanceLine(ing) : null;

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
                  // Which food filled this row, above its numbers. One muted
                  // mono line: USDA descriptions are long, and a three-line row
                  // stops being scannable.
                  if (sourceLine != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sourceLine,
                      style: ansiMono(size: 10, color: AnsiColors.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Honest numbers: only a complete row shows a macro line.
                  if (!stub && macros != null) ...[
                    const SizedBox(height: 3),
                    MacroLineText(
                      macros,
                      style: ansiMono(size: 10, color: AnsiColors.herbDeep),
                      suffix: macroBasisSuffix(ing.macrosBasis),
                      suffixStyle: ansiMono(size: 10, color: AnsiColors.muted),
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

/// "＋ can't find it? add a new ingredient": the add-new door in every picker.
/// Disabled until something is typed.
///
/// Tapping writes nothing here. It pushes the ingredient form with the query
/// prefilled and waits; the created row goes to [onCreated], and backing out
/// resolves nothing. Needs a router in scope.
class AddNewIngredientRow extends HookConsumerWidget {
  const AddNewIngredientRow({
    required this.query,
    required this.onCreated,
    this.label,
    super.key,
  });

  final String query;

  /// Receives the row as the form left it. Not called when the person backed
  /// out or deleted the row on the form.
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
      // The chain crosses two awaits with a keyboard in each, so it continues
      // through handles that outlive this row (`hostContextOf`).
      final host = hostContextOf(context);
      try {
        // One push: the form lands above this picker's sheet, writes nothing
        // until Save, and pops with the row it made. The picker stays open
        // underneath so it can resolve after.
        // ignore: use_build_context_synchronously
        final created = await host.context.pushOnceFor<Ingredient?>(
          newIngredientRoute(name: name),
        );
        if (created == null) return;
        // The popped row is the row as the write left it, which is what the
        // quantity sheet opening next must see.
        onCreated(created);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return DashedAction(
      icon: FLucideIcons.plus,
      enabled: enabled,
      label: enabled
          ? (label?.call(name) ??
                'can’t find it? add "$name" as a new ingredient')
          : 'can’t find it? type a name to add it',
      onTap: addNew,
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
