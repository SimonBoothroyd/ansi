/// The ingredients manager list (`/ingredients`) — design board "Ingredients
/// manager · v1" frame (a). A **pushed** route with a back chevron and no
/// bottom nav (the four tabs are the loop; a vocabulary is reference data),
/// reached from Library ▸ ⋯ ▸ Ingredients.
///
/// The old "Fleshing-out queue" frame becomes a **band on top of the whole
/// vocabulary** rather than its own screen: a vocabulary you can only see
/// when it is broken is not a vocabulary you can edit.
///
/// Rows are the 7.7 picker rows ([IngredientRow]) — same hints, same honest
/// silence where a number is missing — with a chevron instead of a `+`, and
/// one thing the picker's rows do not carry: the **USDA food behind a filled
/// row**, named as a muted second line. This is the screen
/// you scan, so it is where a wrong match is worth catching; the picker stays
/// quiet because a description under every row is noise while you type.
/// Search is the same deterministic local search the picker uses
/// ([useIngredientSearch]); typing collapses the band into the results, which
/// is what a search is for.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/aisles.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_scroll.dart';
import '../../../shared/ansi_search_field.dart';
import '../../../shared/guarded_navigation.dart';
import '../data/ingredient_providers.dart';
import '../domain/ingredient.dart';
import 'ingredient_detail_view.dart';
import 'ingredient_picker.dart';

/// The manager's route.
const kIngredientsRoute = '/ingredients';

/// The vocabulary row the fact-sheet pane is reading — exported so a test
/// names the lit row rather than hunting for a background colour. Only one row
/// carries it.
const kVocabularyReadingRowKey = ValueKey('vocabulary-reading-row');

/// How wide the fact-sheet pane is ever drawn beside the vocabulary. A row
/// reads at a page's measure, not at a desk's width.
const kFactSheetPaneWidth = 720.0;

/// The vocabulary's own scroller — exported so a test names the list rather
/// than picking a `ListView` out of a page that has several.
const kVocabularyScrollKey = ValueKey('vocabulary-scroller');

/// Where the vocabulary was last left.
///
/// `/ingredients` and `/ingredients/:id` are two routes, so a pick rebuilds
/// the page under the reader and its scroller with it. A `PageStorageKey`
/// cannot carry the offset across that: a bucket belongs to one route, and
/// which route the manager is on is exactly what a pick changes. One manager
/// is ever on screen, so one offset is enough — and it is the one fact about
/// this screen worth keeping, because a vocabulary you have to find your
/// place in again is a vocabulary you scroll twice.
double _vocabularyOffset = 0;

/// Forgets where the vocabulary was left. One process pumps manager after
/// manager in a suite; a reader opens one.
@visibleForTesting
void resetVocabularyScroll() => _vocabularyOffset = 0;

/// How many index-guided jumps the reveal below is allowed before it gives up.
/// Each one builds the rows around where the lit row should be, so the second
/// pass normally finds it; the cap is there so a list that cannot settle stops
/// asking for frames rather than spinning.
const _revealAttempts = 6;

class IngredientListView extends HookConsumerWidget {
  const IngredientListView({this.selectedId, super.key});

  /// The row the fact-sheet pane opens on, on a window wide enough to hold the
  /// vocabulary and one row at once — what a deep link to `/ingredients/:id`
  /// hands over. Null on `/ingredients`, where the pane waits for a pick.
  ///
  /// Ignored below [AnsiLayout.expanded], where a row is a pushed page of its
  /// own and this screen is only ever the list.
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);
    final vocabulary = ref.watch(vocabularyProvider);
    // The search field owns its controller (a hook, so it survives every
    // rebuild) and the list branches on WHAT THE FIELD SAYS — never on a query
    // that has outlived the text that produced it. An empty field is therefore
    // the whole vocabulary, by construction: no round-trip, stale `onChange` or
    // re-seeded control can leave the list showing search results under a field
    // displaying its hint.
    final field = useTextEditingController();
    final typed = useValueListenable(field).text;
    final searching = typed.trim().isNotEmpty;
    // Fetching is a side effect of the text changing; a selection-only change
    // must not re-run the query.
    final lastRun = useRef<String?>(null);
    useEffect(() {
      void onEdit() {
        if (lastRun.value == field.text) return;
        lastRun.value = field.text;
        search.run(field.text);
      }

      field.addListener(onEdit);
      return () => field.removeListener(onEdit);
    }, [field]);

    // Decorative emptiness, weighed (D6): the screen's own `when` renders the
    // loading and error branches, so this fallback only ever covers the frame
    // before the first emission.
    final all = vocabulary.asData?.value ?? const <Ingredient>[];
    final stubs = [
      for (final i in all)
        if (i.status == IngredientStatus.stub) i,
    ];

    // Wide enough for the vocabulary and one row at once: a row then opens IN
    // PLACE, in the pane beside the list, rather than as a page over it.
    final wide = AnsiLayout.of(context) == AnsiLayout.expanded;
    final sections = _sections(all);

    // **The location IS the selection.** A pick restates `/ingredients/:id`,
    // so the row the pane is reading is the row the address bar names: a
    // refresh keeps it, the link is worth sending, and a recipe's ingredient
    // door and a tap in this list land in exactly the same place. It goes
    // through [restateOnce] — `replace` inside `Router.neglect` — so reading
    // down a vocabulary leaves no history to walk back out through: Back
    // leaves the manager, it does not step back up the rows.
    //
    // [picked] and [atFields] are the fallback for a screen pumped with no
    // router above it, which is how much of this suite builds one.
    final routed = context.topLocationPath != null;
    final picked = useState<String?>(selectedId);
    final atFields = useState(false);
    useEffect(() {
      picked.value = selectedId;
      atFields.value = false;
      return null;
    }, [selectedId]);
    final reading = wide ? (routed ? selectedId : picked.value) : null;
    final readingAtFields = !routed && atFields.value;

    // A vocabulary row opens as a row: what it is, what it converts, what it
    // counts for — the same posture a recipe opens in from the Library, with
    // `⋯ ▸ Edit` behind it.
    void open(Ingredient i) {
      if (!wide) {
        context.pushOnce(ingredientDetailRoute(i.id));
        return;
      }
      if (routed) {
        context.restateOnce(ingredientDetailRoute(i.id));
        return;
      }
      picked.value = i.id;
      atFields.value = false;
    }

    // The band is a WORK QUEUE, and its rows say what each one is short of.
    // Landing them on a fact sheet that repeats "needs macros" would put a
    // menu between the queue and the fields it exists to fill in.
    void fleshOut(Ingredient i) {
      if (!wide) {
        context.pushOnce(ingredientDetailRoute(i.id, edit: true));
        return;
      }
      if (routed) {
        context.restateOnce(ingredientDetailRoute(i.id, edit: true));
        return;
      }
      picked.value = i.id;
      atFields.value = true;
    }

    // The `＋` opens the form itself: it writes on Save, so it can BE the
    // create surface — back out of it and there is nothing to clean up.
    void addNew() => context.pushOnce(newIngredientRoute());

    // Arriving on `/ingredients/:id` — a pasted link, a recipe's ingredient
    // door — lights a row that can be three hundred rows down the vocabulary,
    // and a lit row nobody can see is not a selection. Put it on screen once,
    // after the list has laid out.
    //
    // The vocabulary is one lazy sliver, so the row a deep link lands on has
    // no render object to reveal: the walk jumps to where the row's INDEX says
    // it roughly is, which builds it, and then reveals it exactly. A row that
    // is already on screen is left alone — that is every tap, and a tap must
    // not move the list out from under the finger.
    final listController = useScrollController(
      initialScrollOffset: _vocabularyOffset,
    );
    useEffect(() {
      void remember() {
        if (!listController.hasClients) return;
        _vocabularyOffset = listController.offset;
      }

      listController.addListener(remember);
      return () => listController.removeListener(remember);
    }, [listController]);
    final readingRowKey = useMemoized(GlobalKey.new);
    final ordered = searching
        ? search.results
        : [for (final section in sections) ...section.rows];
    useEffect(() {
      if (reading == null) return null;
      final index = ordered.indexWhere((i) => i.id == reading);
      if (index < 0) return null;
      var done = false;
      var attempts = 0;
      void step(Duration _) {
        if (done || !listController.hasClients) return;
        if (readingRowKey.currentContext case final rowContext?) {
          done = true;
          if (!_onScreen(rowContext, listController)) {
            unawaited(Scrollable.ensureVisible(rowContext, alignment: 0.3));
          }
          return;
        }
        if (attempts++ >= _revealAttempts) return;
        final extent = listController.position.maxScrollExtent;
        listController.jumpTo(
          (extent * index / ordered.length).clamp(0.0, extent),
        );
        WidgetsBinding.instance.addPostFrameCallback(step);
      }

      WidgetsBinding.instance.addPostFrameCallback(step);
      return () => done = true;
      // The vocabulary's own length is a dependency, not decoration: a cold
      // deep link builds this screen before the rows have arrived, and an
      // effect that only watched the selection would have given up on an
      // empty list and never looked again.
    }, [reading, ordered.length]);

    final header = FHeader.nested(
      title: Text('Ingredients', style: ansiHeaderTitle()),
      prefixes: [FHeaderAction.back(onPress: () => ansiBack(context))],
      suffixes: [
        FHeaderAction(icon: const Icon(FLucideIcons.plus), onPress: addNew),
      ],
    );

    final searchField = AnsiSearchField(
      hint: 'Search your vocabulary',
      controller: field,
    );

    if (wide) {
      return FScaffold(
        childPad: false,
        header: header,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The list takes the width the sheet does not, and never goes under
            // a readable column of rows.
            Expanded(
              child: _ListPane(
                searchField: searchField,
                stubBand: searching || stubs.isEmpty
                    ? null
                    : _StubBand(stubs: stubs, onOpen: fleshOut),
                addDoor: _addDoor(addNew),
                rows: _vocabularyStates(
                  ref,
                  vocabulary,
                  all,
                  () => ListView(
                    key: kVocabularyScrollKey,
                    controller: listController,
                    padding: ansiScrollPadding(
                      context,
                      const EdgeInsets.fromLTRB(22, 0, 22, 8),
                    ),
                    children: searching
                        ? _searchResults(
                            search.results,
                            typed,
                            open,
                            reading: reading,
                            readingKey: readingRowKey,
                          )
                        : _vocabularyRows(
                            sections,
                            open,
                            reading: reading,
                            readingKey: readingRowKey,
                          ),
                  ),
                ),
              ),
            ),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kFactSheetPaneWidth,
                ),
                child: _SheetPane(
                  ingredientId: reading,
                  atFields: readingAtFields,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return FScaffold(
      childPad: false,
      header: header,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: searchField,
          ),
          Expanded(
            child: _vocabularyStates(
              ref,
              vocabulary,
              all,
              () => ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  if (searching)
                    // The typed text, not the hook's query: the "no match"
                    // line must name what the field shows.
                    ..._searchResults(search.results, typed, open)
                  else ...[
                    if (stubs.isNotEmpty)
                      _StubBand(stubs: stubs, onOpen: fleshOut),
                    ..._vocabularyRows(sections, open),
                  ],
                  const SizedBox(height: 16),
                  _addDoor(addNew),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The list's four states, with [rows] as the one that has a vocabulary to
  /// show. Shared by the phone's one column and the wide list pane, so a
  /// vocabulary that failed to load says the same thing in both.
  Widget _vocabularyStates(
    WidgetRef ref,
    AsyncValue<List<Ingredient>> vocabulary,
    List<Ingredient> all,
    Widget Function() rows,
  ) => switch (vocabulary) {
    AsyncError(:final error, :final stackTrace) => AnsiErrorState(
      what: 'your vocabulary',
      error: error,
      stackTrace: stackTrace,
      onRetry: () => ref.invalidate(vocabularyProvider),
    ),
    AsyncLoading() when all.isEmpty => const SizedBox.shrink(),
    _ when all.isEmpty => Center(
      child: Text(
        'No ingredients yet — the vocabulary arrives with your '
        'household’s first sync.',
        textAlign: TextAlign.center,
        style: ansiMono(size: 12, color: AnsiColors.muted),
      ),
    ),
    _ => rows(),
  };

  /// The whole vocabulary, in its aisle sections. [reading] is the row the
  /// fact-sheet pane is on, which is lit; null on a phone, where the row a
  /// person is reading is a page and not a row.
  List<Widget> _vocabularyRows(
    List<({String label, List<Ingredient> rows})> sections,
    ValueChanged<Ingredient> onOpen, {
    String? reading,
    GlobalKey? readingKey,
  }) => [
    for (final section in sections) ...[
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(
          '${section.label} · ${section.rows.length}',
          style: ansiLabel(),
        ),
      ),
      for (final (i, ing) in section.rows.indexed) ...[
        if (i > 0) Container(height: 1, color: AnsiColors.line),
        // The header already said the section, so the row does not repeat it.
        _ManagerRow(
          ingredient: ing,
          onOpen: onOpen,
          showCategory: false,
          reading: ing.id == reading,
          readingKey: readingKey,
        ),
      ],
    ],
  ];

  /// The `＋`'s twin at the foot of the list: the one door to making a row.
  Widget _addDoor(VoidCallback addNew) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: addNew,
    child: FCard(
      child: Text(
        // The scan door does not exist in a browser (the detector wants a
        // camera the tab has not got), so the card must not advertise it there.
        kIsWeb
            ? 'add an ingredient'
            : 'add an ingredient — by hand, or scan a barcode',
        textAlign: TextAlign.center,
        style: ansiMono(size: 11, color: AnsiColors.herb),
      ),
    ),
  );

  /// The vocabulary cut into aisle sections, in the same shop-walk order the
  /// Shop tab groups by ([kAisleOrder]) — you learn one order, not two.
  /// [all] arrives ordered by canonical name, so each section stays A–Z by
  /// construction.
  List<({String label, List<Ingredient> rows})> _sections(
    List<Ingredient> all,
  ) {
    final byAisle = <String, List<Ingredient>>{};
    for (final ing in all) {
      (byAisle[aisleKey(ing.category)] ??= []).add(ing);
    }
    final keys = byAisle.keys.toList()..sort(compareAisles);
    return [
      for (final key in keys) (label: aisleLabel(key), rows: byAisle[key]!),
    ];
  }

  List<Widget> _searchResults(
    List<Ingredient> results,
    String query,
    ValueChanged<Ingredient> onOpen, {
    String? reading,
    GlobalKey? readingKey,
  }) {
    if (results.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No match for "$query".',
            textAlign: TextAlign.center,
            style: ansiMono(size: 12, color: AnsiColors.muted),
          ),
        ),
      ];
    }
    return [
      for (final (i, ing) in results.indexed) ...[
        if (i > 0) Container(height: 1, color: AnsiColors.line),
        _ManagerRow(
          ingredient: ing,
          onOpen: onOpen,
          reading: ing.id == reading,
          readingKey: readingKey,
        ),
      ],
    ];
  }
}

/// Whether the lit row is where a reader can already see it, whole.
///
/// A tap's own row always is, and the reveal leaves the list exactly where the
/// finger left it — scrolling under a tap is the manager's own version of the
/// page jumping as you read.
bool _onScreen(BuildContext rowContext, ScrollController controller) {
  final row = rowContext.findRenderObject();
  final viewport = controller.position.context.notificationContext
      ?.findRenderObject();
  if (row is! RenderBox || viewport is! RenderBox) return false;
  if (!row.hasSize || !viewport.hasSize) return false;
  final top = viewport.globalToLocal(row.localToGlobal(Offset.zero)).dy;
  return top >= 0 && top + row.size.height <= viewport.size.height;
}

/// The picker row, wearing the manager's chevron. Rendering it twice in two
/// places is how the same ingredient starts telling two stories.
class _ManagerRow extends StatelessWidget {
  const _ManagerRow({
    required this.ingredient,
    required this.onOpen,
    this.showCategory = true,
    this.reading = false,
    this.readingKey,
  });

  final Ingredient ingredient;
  final ValueChanged<Ingredient> onOpen;

  /// The row the fact-sheet pane is on, lit so the two panes read as one page.
  final bool reading;

  /// The list's one handle on whichever row is lit, so the scroller can find
  /// it once it exists. It travels with the selection, which is a reparent
  /// inside the one list.
  final GlobalKey? readingKey;

  /// False under a section header, which has already said it. Search results
  /// replace the headers with one flat list, so there the row says it again.
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final row = IngredientRow(
      ingredient: ingredient,
      onPick: onOpen,
      advisoryDensityGap: true,
      showCategory: showCategory,
      // A-D1: the manager names the USDA food behind a filled row, so a wrong
      // match is caught in the scan rather than one opened row at a time. The
      // picker sets this false — see [IngredientRow.showSource].
      showSource: true,
      trailing: const Icon(
        FLucideIcons.chevronRight,
        size: 16,
        color: AnsiColors.muted,
      ),
    );
    if (!reading) return row;
    return KeyedSubtree(
      key: readingKey,
      child: Container(
        key: kVocabularyReadingRowKey,
        decoration: BoxDecoration(
          color: AnsiColors.herbSoft,
          borderRadius: BorderRadius.circular(11),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        child: row,
      ),
    );
  }
}

/// The vocabulary pane: the field and the work queue pinned at the top, the
/// aisle sections travelling under them, and the add door at the foot — where a
/// whole vocabulary cannot push it away.
class _ListPane extends StatelessWidget {
  const _ListPane({
    required this.searchField,
    required this.stubBand,
    required this.addDoor,
    required this.rows,
  });

  final Widget searchField;

  /// Null while searching, or on a vocabulary with no stubs left in it.
  final Widget? stubBand;
  final Widget addDoor;
  final Widget rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
        child: searchField,
      ),
      if (stubBand case final band?)
        Padding(padding: const EdgeInsets.fromLTRB(22, 0, 22, 12), child: band),
      Expanded(child: rows),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
        child: addDoor,
      ),
    ],
  );
}

/// The fact sheet, beside the vocabulary instead of pushed over it: the same
/// [IngredientDetailView] a phone pushes — one sheet, never a second copy of
/// one — with the page's own back control above both panes rather than in its
/// header.
class _SheetPane extends StatelessWidget {
  const _SheetPane({required this.ingredientId, required this.atFields});

  /// Null until a row is picked, which is how `/ingredients` opens.
  final String? ingredientId;

  /// Whether the sheet opens at the fields — the work queue's door, which
  /// exists to fill a stub in rather than to read it.
  final bool atFields;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: AnsiColors.line)),
    ),
    child: ingredientId == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Pick a row to read what it says.',
                textAlign: TextAlign.center,
                style: ansiMono(size: 12, color: AnsiColors.muted),
              ),
            ),
          )
        : IngredientDetailView(
            // Keyed by the row AND the posture it opens in: picking a row draws
            // that row's sheet instead of inheriting the last one's state, and
            // the work queue's door lands on the fields.
            key: ValueKey('sheet-$ingredientId-$atFields'),
            ingredientId: ingredientId,
            edit: atFields,
            embedded: true,
          ),
  );
}

/// "Needs fleshing out" — the stub band pinned above the vocabulary.
///
/// The per-row hint says **needs macros**, not "needs density · macros": the
/// D5 gate is macros alone, and a missing density is an advisory the full row
/// below already carries.
///
/// **G4** — and once a prefill has put macros there, the hint stops asking
/// for what the row already has. It reads **needs completing**, which is D5's
/// own language for the one thing still missing: a human standing behind the
/// numbers. "needs macros" stays for the truly bare stubs, where it is the
/// literal truth.
class _StubBand extends StatelessWidget {
  const _StubBand({required this.stubs, required this.onOpen});

  final List<Ingredient> stubs;
  final ValueChanged<Ingredient> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Needs fleshing out', style: ansiSans(size: 13)),
              Text(
                '${stubs.length} ${plural(stubs.length, 'stub')}',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in stubs)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.canonicalName,
                        style: ansiSans(size: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      [
                        if (s.macros == null)
                          'needs macros'
                        else
                          'needs completing',
                        // WHICH machine filled it — the band is a work queue,
                        // so the tag says what kind of fill is waiting for a
                        // human. The food's own name is on the row below, and
                        // no key of either kind is printed anywhere.
                        if (isUsdaPrefilled(s.source))
                          'usda prefilled'
                        else if (isBarcodeFilled(s.source))
                          'barcode prefilled',
                      ].join(' · '),
                      style: ansiMono(size: 10, color: AnsiColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'A stub stays out of macro totals until you confirm it.',
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
        ],
      ),
    );
  }
}
