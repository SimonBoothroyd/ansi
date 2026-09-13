/// The import review on a desk (design board `Import review`, the
/// `Wide · ≥ 1024` frames): the page on the left, the lines in the middle, one
/// line's form held open on the right.
///
/// **What the width is spent on, and nothing else.** The phone's review asks
/// somebody to hold two things in their head at once — what the page said, and
/// what we made of it — and the only place the page survives there is the
/// `from source:` line under each row. On a desk the page can simply *be*
/// there. That is the first thing the width buys; the second is editing a line
/// in a panel instead of in a card that expands in place, so correcting line
/// four never moves line five.
///
/// **Nothing else changes.** Every row, word, flag, count and door is the
/// phone's: the rows are [ReviewLineRow], the panel's contents are
/// [ReviewLineForm] — the phone's *expanded* card, exactly — the gate is
/// [ReviewCommitBar], the header form, the section doors and the method editor
/// are the same widgets in the same order, and the work queue is a **view** of
/// the one `importValidation` map the header count and Save already read. The
/// card just stopped being a fold and became a column. **The selected line is
/// view state**: it navigates nothing and writes nothing.
///
/// Below `expanded` this file is not built at all — the phone review, expanding
/// in place, is unchanged.
library;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/reorder_grip.dart';
import '../../ingredients/presentation/ingredient_detail_view.dart'
    show ingredientDetailRoute;
import '../../recipes/presentation/line_card.dart';
import '../../recipes/presentation/method_editor.dart';
import '../../recipes/presentation/recipe_header_form.dart';
import '../domain/import_repository.dart';
import '../domain/import_stage.dart';
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
import '../domain/preview_recipe.dart';
import '../domain/reconciliation_payload.dart';
import '../domain/work_queue.dart';
import 'import_method_editing.dart';
import 'import_view_models.dart';
import 'recon_line_card.dart';
import 'reconciliation_view.dart';

/// The widest the three columns are drawn, gutters included: 20 + 380 + 480 +
/// 340 + 20. Centred in the pane above it, like every other capped page.
const double kWideReviewCap = 1240;

/// The source column at rest, and the width it will not go under.
const double kWideSourceWidth = 380;
const double kWideSourceFloor = 300;

/// The lines column at rest, and its floor — the last width to be given up,
/// because the lines are what a person is reading.
const double kWideLinesWidth = 480;
const double kWideLinesFloor = 440;

/// The panel at rest, and its floor.
const double kWidePanelWidth = 340;
const double kWidePanelFloor = 300;

/// The three columns, named so a test can measure one.
const kWideSourceKey = ValueKey('wide-review-source');
const kWideLinesKey = ValueKey('wide-review-lines');
const kWidePanelKey = ValueKey('wide-review-panel');

/// The row the panel is reading. Only one row ever carries it.
const kWideSelectedRowKey = ValueKey('wide-review-selected-row');

/// The lit range inside the source column's text, when the payload named one.
const kWideSourceSpanKey = ValueKey('wide-review-source-span');

/// The commit bar, so a test can prove it sits under the LINES column.
const kWideCommitBarKey = ValueKey('wide-review-commit-bar');

/// The review at [AnsiLayout.expanded].
class WideReviewBody extends HookConsumerWidget {
  const WideReviewBody({required this.state, super.key});

  final ImportReconciling state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The selection is VIEW state: which line the panel is reading. It
    // navigates nothing, writes nothing, and survives no rebuild it shouldn't
    // — a line that stops existing (dropped and saved, a section deleted)
    // simply stops being found below, and the panel falls back to the queue.
    final selected = useState<int?>(null);

    // `.value`, never `asData`: a recompute passes through a loading state
    // whose data-only view is null, and reading THAT blinked every row's rule
    // and the panel on every keystroke (the phone's body documents this).
    final byLine = ref.watch(importValidationProvider).value;

    final reading = selected.value == null
        ? null
        : state.resolutions
              .where((r) => r.lineIndex == selected.value)
              .firstOrNull;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kWideReviewCap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ansiPageGutter),
          child: _Columns(
            source: _SourceColumn(
              key: kWideSourceKey,
              request: state.request,
              sourceText: state.payload.sourceText,
              span: reading == null
                  ? null
                  : state.lineAt(reading.lineIndex).sourceSpan,
              readingWords: reading == null
                  ? null
                  : rawLineText(state.lineAt(reading.lineIndex).raw),
            ),
            lines: _LinesColumn(
              key: kWideLinesKey,
              state: state,
              byLine: byLine,
              selected: selected.value,
              onSelect: (i) => selected.value = i,
            ),
            panel: _Panel(
              key: kWidePanelKey,
              state: state,
              byLine: byLine,
              reading: reading,
              onSelect: (i) => selected.value = i,
              onClose: () => selected.value = null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The reading state at [AnsiLayout.expanded]: the source column already
/// drawn, and the streamed checklist standing in the lane the lines and the
/// panel will take.
///
/// The pages are local files the cook just chose, so there is nothing to wait
/// for on the left — and when the review lands, that column does not move. The
/// checklist is the phone's, unchanged and centred in its lane rather than
/// stretched across it: four short rows spread over 900 px would be a progress
/// screen pretending to be a dashboard.
class WideReadingBody extends StatelessWidget {
  const WideReadingBody({
    required this.rows,
    required this.request,
    required this.checklist,
    super.key,
  });

  final List<StageProgress> rows;
  final ImportSource request;

  /// The phone's own checklist widget, handed in rather than rebuilt — one
  /// list of stages, one set of words, two lanes to stand it in.
  final Widget checklist;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kWideReviewCap),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ansiPageGutter),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: kWideSourceWidth,
              child: _SourceColumn(
                key: kWideSourceKey,
                request: request,
                sourceText: null,
                span: null,
                readingWords: null,
              ),
            ),
            Expanded(child: checklist),
          ],
        ),
      ),
    ),
  );
}

// --- The three columns -------------------------------------------------------

/// Which column a child of [_Columns] is.
enum _Col { source, lines, panel }

/// The three columns, and what happens to them as the pane narrows.
///
/// A [CustomMultiChildLayout] rather than a [Row] of flexes, because the rule
/// is a **priority** and not a proportion: at 1180 the source gives up its
/// width first, down to 300; then the panel, down to 300; and the lines go last
/// and never under 440, because they are what a person is reading. Flex would
/// shrink all three together and take the lines under their floor first.
///
/// It reads its own constraints, which is not a viewport read: this widget is
/// told how wide its pane is, the way every widget is, and it never asks how
/// wide the window is. The one viewport reader is still `ansi_layout.dart`.
class _Columns extends StatelessWidget {
  const _Columns({
    required this.source,
    required this.lines,
    required this.panel,
  });

  final Widget source;
  final Widget lines;
  final Widget panel;

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _ColumnsDelegate(),
    children: [
      LayoutId(id: _Col.source, child: source),
      LayoutId(id: _Col.lines, child: lines),
      LayoutId(id: _Col.panel, child: panel),
    ],
  );
}

class _ColumnsDelegate extends MultiChildLayoutDelegate {
  _ColumnsDelegate();

  @override
  void performLayout(Size size) {
    final widths = wideReviewColumnWidths(size.width);
    var x = 0.0;
    for (final entry in <(_Col, double)>[
      (_Col.source, widths.source),
      (_Col.lines, widths.lines),
      (_Col.panel, widths.panel),
    ]) {
      layoutChild(entry.$1, BoxConstraints.tight(Size(entry.$2, size.height)));
      positionChild(entry.$1, Offset(x, 0));
      x += entry.$2;
    }
  }

  @override
  bool shouldRelayout(_ColumnsDelegate oldDelegate) => false;
}

/// How wide each column is drawn in [available] px — the shrink policy, pulled
/// out so it can be read and tested without a widget.
///
/// Down from the cap: the source pays first, then the panel, then the lines.
/// Under the sum of the three floors (1040) there is nothing left to protect,
/// so all three shrink together in proportion — which is what the bottom of the
/// band looks like, a 1024 window whose rail leaves 920 for the page. Three
/// narrow columns is still the honest answer there; the alternative is a
/// column running off the edge.
({double source, double lines, double panel}) wideReviewColumnWidths(
  double available,
) {
  const ideal = kWideSourceWidth + kWideLinesWidth + kWidePanelWidth;
  const floors = kWideSourceFloor + kWideLinesFloor + kWidePanelFloor;
  if (available >= ideal) {
    return (
      source: kWideSourceWidth,
      lines: kWideLinesWidth,
      panel: kWidePanelWidth,
    );
  }
  if (available <= floors) {
    final scale = available / floors;
    return (
      source: kWideSourceFloor * scale,
      lines: kWideLinesFloor * scale,
      panel: kWidePanelFloor * scale,
    );
  }
  var deficit = ideal - available;
  double give(double width, double floor) {
    final paid = deficit.clamp(0.0, width - floor);
    deficit -= paid;
    return width - paid;
  }

  final source = give(kWideSourceWidth, kWideSourceFloor);
  final panel = give(kWidePanelWidth, kWidePanelFloor);
  final lines = give(kWideLinesWidth, kWideLinesFloor);
  return (source: source, lines: lines, panel: panel);
}

// --- The source column -------------------------------------------------------

/// The page itself, at a readable measure, scrolling on its own — so reading it
/// never moves a line out from under the hand.
///
/// A **link** import draws the URL and the fetched text, with the selected
/// line's span lit when the payload carried one (both fields are additive and
/// optional: without them this column says so rather than pretending). A
/// **photo** import draws the pages the cook handed over, the current one large
/// with a thumbnail each — and **no box on the photo**, because nothing on the
/// wire carries one; the selected line's own words are pinned under the page
/// instead of a rectangle somebody would trust.
class _SourceColumn extends StatelessWidget {
  const _SourceColumn({
    required this.request,
    required this.sourceText,
    required this.span,
    required this.readingWords,
    super.key,
  });

  final ImportSource request;
  final String? sourceText;
  final SourceSpan? span;

  /// The selected line as the page printed it — pinned under a photo page,
  /// where there is no span to light.
  final String? readingWords;

  @override
  Widget build(BuildContext context) {
    final body = switch (request) {
      ImportFromUrl(:final url) => _PageText(
        url: url,
        text: sourceText,
        span: span,
      ),
      ImportFromPhotos(:final imagePaths) => _PhotoPages(
        paths: imagePaths,
        readingWords: readingWords,
      ),
    };
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        border: Border(right: BorderSide(color: AnsiColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 20, 20),
        child: body,
      ),
    );
  }
}

/// A link import's source: the URL, then the page's own text with the selected
/// line lit.
class _PageText extends StatefulWidget {
  const _PageText({required this.url, required this.text, required this.span});

  final String url;
  final String? text;
  final SourceSpan? span;

  @override
  State<_PageText> createState() => _PageTextState();
}

class _PageTextState extends State<_PageText> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_PageText old) {
    super.didUpdateWidget(old);
    final span = widget.span;
    final text = widget.text;
    if (span == null || text == null || span == old.span) return;
    if (!_scroll.hasClients || text.isEmpty) return;
    // Proportional, and deliberately not claimed to be exact: the page's text
    // is one collapsed run with no line structure to count, so where a
    // character sits in the string is the only honest estimate of where it
    // sits in the column. The lit range is what actually says where the line
    // is; this only saves a scroll.
    final where = _scroll.position.maxScrollExtent * (span.start / text.length);
    _scroll.animateTo(
      where.clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('THE PAGE', style: ansiLabel()),
        const SizedBox(height: 6),
        Text(
          widget.url,
          style: ansiMono(size: 11, color: AnsiColors.muted),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        if (text == null || text.isEmpty)
          Text(
            'the page’s own text did not come back with this import — the '
            'lines below are what we read out of it, and each one still '
            'carries the words it was read from.',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: Text.rich(
                _spanned(text, widget.span),
                style: ansiSans(size: 13, height: 1.55),
              ),
            ),
          ),
      ],
    );
  }
}

/// [text] with [span] washed in the herb the Shop's read row uses — one idiom
/// for "the pane is reading this one".
///
/// A span the payload never sent, or one that does not fit the text it came
/// with, lights nothing: the plain page is the honest fallback, and a range
/// aimed at the wrong characters would tell a reader the page said something
/// it did not.
TextSpan _spanned(String text, SourceSpan? span) {
  if (span == null ||
      span.start < 0 ||
      span.end > text.length ||
      span.start >= span.end) {
    return TextSpan(text: text);
  }
  return TextSpan(
    children: [
      TextSpan(text: text.substring(0, span.start)),
      WidgetSpan(
        child: DecoratedBox(
          key: kWideSourceSpanKey,
          decoration: BoxDecoration(
            color: AnsiColors.herbSoft,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            text.substring(span.start, span.end),
            style: ansiSans(
              size: 13,
              color: AnsiColors.herbDeep,
              height: 1.55,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ),
      TextSpan(text: text.substring(span.end)),
    ],
  );
}

/// A photo import's source: the pages as they were handed over.
class _PhotoPages extends HookWidget {
  const _PhotoPages({required this.paths, required this.readingWords});

  final List<String> paths;
  final String? readingWords;

  @override
  Widget build(BuildContext context) {
    final page = useState(0);
    final at = page.value.clamp(0, paths.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          paths.length == 1
              ? 'THE PAGE'
              : 'THE PAGES · ${at + 1} OF ${paths.length}',
          style: ansiLabel(),
        ),
        const SizedBox(height: 10),
        if (paths.isNotEmpty) Expanded(child: _Page(path: paths[at])),
        if (paths.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: paths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => page.value = i,
                child: Container(
                  width: 48,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: i == at ? AnsiColors.herb : AnsiColors.line,
                      width: i == at ? 2 : 1,
                    ),
                  ),
                  child: _Page(path: paths[i], fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ],
        if (readingWords != null && readingWords!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('this line, as the page printed it', style: ansiLabel()),
          const SizedBox(height: 4),
          Text(readingWords!, style: ansiMono(size: 11.5)),
        ],
      ],
    );
  }
}

/// One page image.
///
/// Read through [XFile], not `dart:io`: on a phone the picker's path is a file
/// and in a browser it is a `blob:` URL with no filesystem behind it — the same
/// reason the upload loop reads pages this way.
class _Page extends HookWidget {
  const _Page({required this.path, this.fit = BoxFit.contain});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final bytes = useMemoized(() => XFile(path).readAsBytes(), [path]);
    final snapshot = useFuture(bytes);
    final data = snapshot.data;
    if (data == null) {
      return const ColoredBox(color: AnsiColors.paper, child: SizedBox());
    }
    return Image.memory(data, fit: fit, alignment: Alignment.topCenter);
  }
}

// --- The lines column --------------------------------------------------------

/// The phone's rows, one selected, with the commit bar as this column's own
/// footer — because the number on it is about the lines, and a bar across the
/// source pane would say the page has something to save.
class _LinesColumn extends HookConsumerWidget {
  const _LinesColumn({
    required this.state,
    required this.byLine,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final ImportReconciling state;
  final Map<int, LineValidation>? byLine;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(importControllerProvider.notifier);
    final recipe = buildPreviewRecipe(
      state.payload,
      state.resolutions,
      servingsBase: state.servings,
      sections: state.sections,
      measureByLine: {
        if (byLine != null)
          for (final e in byLine!.entries)
            if (e.value.unitMeasure != null) e.key: e.value.unitMeasure!,
      },
    );
    final rows = reviewRowList(
      state: state,
      byLine: byLine,
      row: (line, resolution, validation, dragIndex) => _WideLineRow(
        key: ValueKey('review-line-${resolution.lineIndex}'),
        line: line,
        resolution: resolution,
        validation: validation,
        dragIndex: dragIndex,
        selected: resolution.lineIndex == selected,
        onSelect: () => onSelect(resolution.lineIndex),
      ),
    );
    final sourceRaw = state.payload.yieldRaw?.trim();
    final sourceStated = sourceRaw != null && sourceRaw.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                sliver: SliverList.list(
                  children: [
                    ImportSourceNotes(payload: state.payload),
                    RecipeHeaderForm(
                      host: controller,
                      timeCaptions: false,
                      notes: RecipeHeaderNotes(
                        besideServes: state.payload.servingsBase == null
                            ? 'not printed — set it'
                            : null,
                        underMakes: sourceStated
                            ? 'from source:  $sourceRaw'
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                  proxyDecorator: liftedRow,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverList.list(
                  children: [
                    ReviewListDoors(recipe: recipe, sections: state.sections),
                    const SizedBox(height: 24),
                    MethodEditor(
                      recipe: recipe,
                      notifier: ImportMethodEditing(
                        controller: controller,
                        state: state,
                        preview: recipe,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DecoratedBox(
          key: kWideCommitBarKey,
          decoration: const BoxDecoration(
            color: AnsiColors.surface,
            border: Border(top: BorderSide(color: AnsiColors.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: ReviewCommitBar(state: state),
          ),
        ),
      ],
    );
  }
}

/// A line as a **row on bare paper** — no card, no box.
///
/// The card's border was the affordance for expanding it, and expanding is what
/// the panel took over. What is left keeps the phone's three parts (the mono
/// amount in its own column, the identity, the note) and its **grip**, since
/// drag was always a collapsed-row gesture and here every row is collapsed —
/// which makes the whole list draggable rather than only the shut part of it.
///
/// A flagged row has no amber box because it has no box at all: the amber is a
/// **2 px rule in its margin**, Cook's own device, carrying the same `⚠` tag
/// and the same words. The selected row takes the Shop's herb wash.
class _WideLineRow extends StatelessWidget {
  const _WideLineRow({
    required this.line,
    required this.resolution,
    required this.validation,
    required this.dragIndex,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final ReconLine line;
  final LineResolution resolution;
  final LineValidation? validation;
  final int dragIndex;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    // A dropped line has no issues by construction; the map handed in can be
    // one recompute behind, so don't let a stale flag survive the drop.
    final effective = resolution.isDropped
        ? const LineValidation(issues: [])
        : (validation ?? LineValidation(issues: lineIssues(resolution)));
    final attention = effective.issues.isNotEmpty;
    return Container(
      key: selected ? kWideSelectedRowKey : null,
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: selected ? AnsiColors.herbSoft : null,
        borderRadius: selected ? BorderRadius.circular(8) : null,
        border: attention
            ? const Border(left: BorderSide(color: AnsiColors.aging, width: 2))
            : null,
      ),
      padding: EdgeInsets.fromLTRB(attention ? 8 : 10, 8, 6, 8),
      child: LineCardGrip(
        dragIndex: dragIndex,
        // The phone's own collapsed row, with the pencil off: nothing here
        // opens, because the form is already standing beside the list.
        child: ReviewLineRow(
          line: line,
          resolution: resolution,
          issues: effective.issues,
          onTap: onSelect,
          pencil: false,
        ),
      ),
    );
  }
}

// --- The panel ---------------------------------------------------------------

/// The selected line's form, or — with nothing selected — the import's own
/// outstanding work.
class _Panel extends ConsumerWidget {
  const _Panel({
    required this.state,
    required this.byLine,
    required this.reading,
    required this.onSelect,
    required this.onClose,
    super.key,
  });

  final ImportReconciling state;
  final Map<int, LineValidation>? byLine;
  final LineResolution? reading;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final line = reading;
    final kept = keptLines(state.resolutions);
    final where = line == null
        ? null
        : kept.indexWhere((r) => r.lineIndex == line.lineIndex);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AnsiColors.surface,
        border: Border(left: BorderSide(color: AnsiColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHead(
              label: line == null ? 'What still needs you' : 'The line',
              trailing: line == null
                  ? '${ref.watch(importOutstandingLinesProvider)}'
                  : where != null && where >= 0
                  ? '${where + 1} of ${kept.length}'
                  : '',
            ),
            const SizedBox(height: 10),
            Expanded(
              child: line == null
                  ? _WorkQueue(
                      state: state,
                      byLine: byLine ?? const {},
                      onSelect: onSelect,
                    )
                  : SingleChildScrollView(
                      // The phone's EXPANDED card, verbatim — the bin, the
                      // optional switch, the amount door, the unit chips and
                      // the notes field are all here because that is where the
                      // phone keeps them. Nothing was dropped and nothing
                      // moved between states; the state stopped being a fold
                      // and became a column.
                      child: ReviewLineForm(
                        line: state.lineAt(line.lineIndex),
                        resolution: line,
                        validation:
                            byLine?[line.lineIndex] ??
                            LineValidation(issues: lineIssues(line)),
                        matched: _matched(line, byLine?[line.lineIndex]),
                        onCollapse: onClose,
                        onDrop: () {
                          ref
                              .read(importControllerProvider.notifier)
                              .updateResolution(
                                line.lineIndex,
                                (r) => r.drop(),
                              );
                          onClose();
                        },
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Text(
              line == null
                  ? 'every item above is a flag already drawn on its row, read '
                        'from the one map the header count and Save read'
                  : 'nothing here is saved until Save, exactly as on the phone',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card's own rule, read here so the panel and the row agree: a match is
/// the VALIDATION's verdict, not a re-derivation from the id the resolution
/// still holds — a line matched to a row retired since the server answered
/// comes back unmatched there, and the form must ask for a pick.
bool _matched(LineResolution line, LineValidation? validation) {
  final issues = validation?.issues ?? lineIssues(line);
  return !issues.contains(LineIssue.unmatched) &&
      (line.chosenIngredientId != null || line.isComponent);
}

class _PanelHead extends StatelessWidget {
  const _PanelHead({required this.label, required this.trailing});

  final String label;
  final String trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label.toUpperCase(),
          style: ansiLabel(color: AnsiColors.ink),
        ),
      ),
      Text(trailing, style: ansiMono(size: 11, color: AnsiColors.muted)),
    ],
  );
}

/// The import's outstanding work, grouped by what each line WANTS.
///
/// A view, not a feature: every item is a flag already on a row, read from the
/// one validation map the header count and the Save gate read, so the queue
/// cannot say four while the bar says five. Tapping an item selects its line
/// and the panel becomes the form.
class _WorkQueue extends StatelessWidget {
  const _WorkQueue({
    required this.state,
    required this.byLine,
    required this.onSelect,
  });

  final ImportReconciling state;
  final Map<int, LineValidation> byLine;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final groups = importWorkQueue(
      resolutions: state.resolutions,
      byLine: byLine,
      lineAt: state.lineAt,
    );
    final created = createdHereItems(
      resolutions: state.resolutions,
      byLine: byLine,
    );
    if (groups.isEmpty && created.isEmpty) {
      return Text(
        'nothing is waiting on you — every line is matched, its amount is '
        'set and its unit is one the row can carry.',
        style: ansiMono(size: 11, color: AnsiColors.muted),
      );
    }
    return ListView(
      children: [
        for (final group in groups) ...[
          _QueueHeading(label: group.work.label, count: group.items.length),
          for (final item in group.items)
            _QueueItem(item: item, onTap: () => onSelect(item.lineIndex)),
        ],
        if (created.isNotEmpty) ...[
          const SizedBox(height: 18),
          _QueueHeading(
            label: 'Created here',
            count: created.length,
            quiet: true,
          ),
          for (final item in created)
            _QueueItem(item: item, onTap: () => onSelect(item.lineIndex)),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'it saves as it stands and is out of the count — a stub is a '
              'real, plannable line with numbers it has not got yet. It '
              'surfaces in the Ingredients manager’s stub band.',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
        ],
      ],
    );
  }
}

class _QueueHeading extends StatelessWidget {
  const _QueueHeading({
    required this.label,
    required this.count,
    this.quiet = false,
  });

  final String label;
  final int count;
  final bool quiet;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Row(
      children: [
        if (!quiet) ...[
          const Icon(
            FLucideIcons.triangleAlert,
            size: 11,
            color: AnsiColors.aging,
          ),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            label,
            style: ansiMono(
              size: 11,
              color: quiet ? AnsiColors.muted : AnsiColors.aging,
            ),
          ),
        ),
        Text('$count', style: ansiMono(size: 11, color: AnsiColors.muted)),
      ],
    ),
  );
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({required this.item, required this.onTap});

  final ImportWorkItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final openRow = item.openIngredientId;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                style: ansiSans(size: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // What one of a thing weighs is the INGREDIENT's property, so the
            // one door for that item is the row's own form — never a weight
            // typed on this line (ADR-0015).
            if (openRow != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.pushOnce(
                  ingredientDetailRoute(openRow, edit: true),
                ),
                child: Text(
                  'open the row ›',
                  style: ansiMono(size: 10.5, color: AnsiColors.herb),
                ),
              )
            else if (item.printed.isNotEmpty)
              Text(
                item.printed,
                style: ansiMono(size: 10.5, color: AnsiColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}
