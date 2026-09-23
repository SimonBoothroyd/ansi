/// The ingredient page (`/ingredients/:id`, and `/ingredients/new`): a fact
/// sheet for a row that exists, a form for one being made or edited.
///
/// Both postures are drawn here and share the sentences in [macrosFact] and its
/// neighbours. The form's state is the [IngredientForm] draft; nothing is
/// written until Save (ADR-0011). Macros gate completion, density does not; a
/// prefill (USDA, barcode via [applyDraft]) never confirms a row. Delete is
/// refused while a live recipe line points at the row.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/text/name_clean.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/picker_shell.dart';
import '../../../shared/was_word_line.dart';
import '../../../shared/write.dart';
import '../../books/presentation/text_prompt.dart';
import '../barcode/barcode_add.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/apply_draft.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/name_namespace.dart';
import '../domain/normalize.dart';
import '../domain/price.dart';
import '../domain/price_repository.dart';
import '../domain/serving_measure.dart';
import '../domain/usda_probe.dart';
import 'density_entry.dart';
import 'draft_card.dart';
import 'ingredient_facts.dart';
import 'ingredient_view_models.dart';
import 'label_photo_door.dart';
import 'label_read_progress.dart';
import 'macro_fields.dart';
import 'macro_line_text.dart';
import 'macros_doubt_line.dart';
import 'measure_delete.dart';
import 'measures_editor.dart';
import 'piece_weight_entry.dart';
import 'price_sheet.dart';
import 'serving_row.dart';
import 'usda_pick_sheet.dart';

/// The pushed route for one vocab row. [edit] opens the form rather than the
/// fact sheet, for doors that exist to change a field.
String ingredientDetailRoute(String id, {bool edit = false}) =>
    edit ? '/ingredients/$id?edit=1' : '/ingredients/$id';

/// The query parameter [ingredientDetailRoute] writes, read back by the
/// router. One name, one place, so a cold deep link and a push agree.
const kEditPostureQueryParam = 'edit';

/// The pushed route for a new row; [name] prefills the name field. Pops with
/// the created [Ingredient], or null when backed out of.
String newIngredientRoute({String name = ''}) => name.trim().isEmpty
    ? '/ingredients/new'
    : '/ingredients/new?name=${Uri.encodeQueryComponent(name.trim())}';

/// The form's own Save in the pinned dock, keyed so tests can name it.
const kFormSaveKey = ValueKey('form-save');

/// The dock's CTA: `Mark complete` on a stored stub. A complete row and a row
/// that does not exist yet each carry one button instead — Save.
const kFormCompleteKey = ValueKey('form-complete');

/// Where back lands with nothing under the page. Not imported from the list
/// view, which imports this file.
const _managerRoute = '/ingredients';

class IngredientDetailView extends HookConsumerWidget {
  const IngredientDetailView({
    this.ingredientId,
    this.name = '',
    this.edit = false,
    this.embedded = false,
    this.lookup,
    this.cameraPane,
    super.key,
  });

  /// The row to edit, or null to create one.
  final String? ingredientId;

  /// What the name field opens with on a create.
  final String name;

  /// Which posture the page opens in; from there the posture is page state.
  final bool edit;

  /// True when drawn beside the vocabulary on a wide window. The page holding
  /// the panes draws the back control, so this header carries the `⋯` alone.
  final bool embedded;

  /// Forwarded to the barcode scan. Test seams; null in app code.
  final OffLookup? lookup;
  final BarcodeCameraPane? cameraPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A row that does not exist has nothing to read, so create is always
    // editing.
    final editing = useState(edit || ingredientId == null);
    if (ingredientId == null) {
      return _DetailForm(
        ingredientId: null,
        initialName: name,
        lookup: lookup,
        cameraPane: cameraPane,
      );
    }
    final async = ref.watch(ingredientByIdProvider(ingredientId!));

    // While the by-id watch is still opening, read the row from the vocabulary
    // the list beside this pane already holds (same projection), which saves a
    // blank frame per pick. Only when embedded, and only while loading: an
    // `AsyncData(null)` means the row is gone.
    final seed = embedded && async.isLoading
        ? _rowIn(ref.watch(vocabularyProvider).asData?.value, ingredientId!)
        : null;

    // Each posture owns its scaffold, because the header menu and the dock act
    // on its state. Built only once the row is here, so the draft seeds from a
    // real row.
    if (async.asData?.value ?? seed case final row?) {
      if (!editing.value) {
        return _ReadPosture(
          ingredient: row,
          embedded: embedded,
          onEdit: () => editing.value = true,
        );
      }
      // Editing is a mode of this page, so the system back gesture leaves the
      // mode exactly as the header chevron does.
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // Unfocus first: a focused field leaving the tree keeps asking for
          // its caret.
          FocusManager.instance.primaryFocus?.unfocus();
          editing.value = false;
        },
        child: _DetailForm(
          // Keyed by id so pushing a different ingredient rebuilds the form
          // state instead of inheriting the previous row's typed values.
          key: ValueKey(ingredientId!),
          ingredientId: ingredientId,
          // Save, Mark complete and back return to the fact sheet; only delete
          // leaves.
          onDone: () => editing.value = false,
          lookup: lookup,
          cameraPane: cameraPane,
        ),
      );
    }
    // The loading and error states wear the same chrome the row will, so an
    // embedded pane does not flash a header for one frame.
    return FScaffold(
      childPad: false,
      header: _header(
        context,
        title: embedded ? null : 'Ingredient',
        showBack: !embedded,
      ),
      child: switch (async) {
        AsyncError(:final error) => _Centered('Could not open it — $error'),
        AsyncLoading() => const _Centered('…'),
        _ => const _Centered(
          'This ingredient is gone — it was deleted on another device.',
        ),
      },
    );
  }
}

/// One row out of the live vocabulary, or null — what the manager's pane reads
/// its first frame from while its own watch is opening.
Ingredient? _rowIn(List<Ingredient>? all, String id) {
  for (final row in all ?? const <Ingredient>[]) {
    if (row.id == id) return row;
  }
  return null;
}

/// The page header, shared by the form and the states with no row yet.
/// [suffixes] holds the `⋯` menu.
FHeader _header(
  BuildContext context, {
  String? title,
  VoidCallback? onBack,
  List<Widget> suffixes = const [],
  bool showBack = true,
}) {
  final back = FHeaderAction.back(
    // A cold deep link has nothing to pop, so fall back to the manager.
    onPress: onBack ?? () => ansiBack(context, home: _managerRoute),
  );
  // The reading posture leads with the name in the body, the way the recipe
  // page does, so it names none here rather than saying it twice.
  if (title == null) {
    return FHeader.nested(prefixes: [if (showBack) back], suffixes: suffixes);
  }
  return FHeader.nested(
    title: Text(
      title,
      style: ansiHeaderTitle(),
      overflow: TextOverflow.ellipsis,
    ),
    // [showBack] holds on the titled header too, not only on the untitled
    // one: a caller that says it draws no chevron means it in both.
    prefixes: [if (showBack) back],
    suffixes: suffixes,
  );
}

class _Centered extends StatelessWidget {
  const _Centered(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: ansiMono(size: 12, color: AnsiColors.muted),
      ),
    ),
  );
}

/// The reading posture's one call to action, on a row that is still a stub —
/// exported so a test names it rather than counting buttons.
const kReadFillItInKey = ValueKey('read-fill-it-in');

/// The fact sheet: the form's groups in the form's order, each value stated
/// through the shared sentences ([macrosFact] and its neighbours). Its one
/// button, `Fill it in`, shows only on an incomplete row.
class _ReadPosture extends ConsumerWidget {
  const _ReadPosture({
    required this.ingredient,
    required this.onEdit,
    this.embedded = false,
  });

  final Ingredient ingredient;
  final VoidCallback onEdit;

  /// See [IngredientDetailView.embedded].

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ing = ingredient;
    final stub = ing.status == IngredientStatus.stub;
    // Decorative emptiness: aliases that did not load cost the reader one line.
    final aliases =
        ref.watch(ingredientAliasesProvider(ing.id)).asData?.value ??
        const <IngredientAlias>[];
    final alsoKnownAs = aliasesFact(aliases);
    final measuresAsync = ref.watch(ingredientMeasuresProvider(ing.id));
    final source = sourceProvenanceLine(ing);
    final pieceWeight = pieceWeightFact(ing);
    // The row's own serving lets the macro line print the label's figures.
    final serving = servingMeasureOf(
      measuresAsync.asData?.value ?? const <Measure>[],
    );
    final macroFigures = macrosFactFigures(ing, serving: serving);
    final per100 = per100Fact(ing, serving: serving);
    final densityAside = densityAsideFact(ing, serving: serving);

    return FScaffold(
      childPad: false,
      header: _header(
        context,
        showBack: !embedded,
        suffixes: [
          FPopoverMenu(
            // `menuBuilder`, not `menu`: an item dismisses the menu it was
            // picked from before it acts (the recipe view's rule).
            menuBuilder: (_, controller, _) => [
              FItemGroup(
                children: [
                  FItem(
                    prefix: const Icon(FLucideIcons.pencil),
                    title: const Text('Edit'),
                    onPress: () {
                      unawaited(controller.hide());
                      onEdit();
                    },
                  ),
                ],
              ),
            ],
            builder: (context, controller, _) => FHeaderAction(
              icon: const Icon(FLucideIcons.ellipsis),
              onPress: controller.toggle,
            ),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            ing.canonicalName,
            style: ansiSerif(size: AnsiType.display, weight: FontWeight.w700),
          ),
          if (alsoKnownAs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'also known as $alsoKnownAs',
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
            ),
          const SizedBox(height: 14),
          _StatusStrip(ingredient: ing),
          if (stub)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FButton(
                key: kReadFillItInKey,
                onPress: onEdit,
                child: const Text('Fill it in'),
              ),
            )
          else
            const SizedBox.shrink(),

          _Group(
            title: 'Identity',
            children: [
              const _Label('CATEGORY'),
              _Fact(categoryFact(ing), muted: ing.category == null),
            ],
          ),

          _Group(
            title: 'Nutrition',
            children: [
              // Which food the numbers came from, as the manager list prints
              // it.
              if (source != null)
                _Fact(source, muted: true)
              else
                const SizedBox.shrink(),
              _Label(
                'MACROS',
                hint: serving == null
                    ? null
                    : 'as the label '
                          'reads',
              ),
              // Never zeros: a row with no panel says what it is short of.
              if (macroFigures case final figures?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: MacroLineText(
                    figures.macros,
                    style: ansiMono(size: 12),
                    suffix: figures.per,
                  ),
                )
              else
                _Fact(macrosFact(ing, serving: serving), muted: true),
              // The derivation under the label's own line, for the reader who
              // wants to see what the totals actually use.
              if (per100 != null) _Fact(per100, muted: true),
            ],
          ),

          _Group(
            title: 'Units & measures',
            children: [
              const _Label('DEFAULT UNIT'),
              _Fact(ing.defaultUnit.label),
              const _Label('ALLOWED UNITS', hint: 'what a line may say'),
              _Fact(allowedUnitsFact(ing)),
              // Drawn only on a count row that states a piece weight.
              if (pieceWeight != null) ...[
                const _Label('PIECE WEIGHT'),
                _Fact(pieceWeight),
              ],
              const _Label('DENSITY'),
              _Fact(
                densityFact(ing, serving: serving),
                muted: ing.densityGPerMl == null,
              ),
              if (densityAside != null) _Fact(densityAside, muted: true),
              const _Label('MEASURES', hint: 'count-like, in the basis'),
              // Load-bearing emptiness: an errored stream is not "no measures".
              if (measuresAsync case AsyncError(
                :final error,
                :final stackTrace,
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: AnsiErrorState(
                    compact: true,
                    what: 'the measures',
                    error: error,
                    stackTrace: stackTrace,
                    onRetry: () =>
                        ref.invalidate(ingredientMeasuresProvider(ing.id)),
                  ),
                )
              else
                _ReadMeasures(
                  measures: measuresAsync.asData?.value ?? const <Measure>[],
                ),
            ],
          ),

          _PriceGroup(ingredient: ing),
          _OnReceiptsGroup(ingredient: ing),
        ],
      ),
    );
  }
}

/// The Price group's door onto the price sheet, exported so a test names it
/// rather than counting buttons.
const kAddPriceKey = ValueKey('add-a-price');

/// The Latest line, which is a tap onto the sheet that entered it.
const kLatestPriceKey = ValueKey('latest-price');

/// The Price group: the latest price on one line with its derived `/100 g`, and
/// the earlier ones under it.
///
/// A row nobody has priced says so and offers the door; it never shows a zero.
/// Every price is a tap to where it is edited: a typed price opens the sheet, a
/// receipt line opens its receipt. Both postures draw this one widget.
class _PriceGroup extends ConsumerWidget {
  const _PriceGroup({
    required this.ingredient,
    this.editing = false,
    this.creating = false,
  });

  /// The row as stored, never the draft: the sheet writes at once and derives
  /// per-100 from this row's basis and density.
  final Ingredient ingredient;

  /// True on the editing posture, where the group says a price does not wait
  /// for the form's Save.
  final bool editing;

  /// True on the create form: there is no row to price, and the group says so.
  final bool creating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (creating) {
      return const _Group(
        title: 'Price',
        suffix: '— after the first save',
        children: [
          _Fact(
            'A price is an event on a row, and this one does not exist yet.',
            muted: true,
          ),
        ],
      );
    }

    final async = ref.watch(ingredientPricesProvider(ingredient.id));
    final prices = async.asData?.value ?? const <PriceObservation>[];
    // A slot, so the reading posture keeps the group's rhythm without the
    // aside.
    final aside = editing
        ? const _Fact(
            'a price is written as you enter it; Save below is for the fields',
            muted: true,
          )
        : const SizedBox.shrink();
    final door = Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DashedAction(
        key: kAddPriceKey,
        icon: FLucideIcons.plus,
        label: 'add a price',
        onTap: () => unawaited(showPriceSheet(context, ingredient: ingredient)),
      ),
    );

    // Load-bearing emptiness: an errored stream is not "never bought".
    if (async case AsyncError(:final error, :final stackTrace)) {
      return _Group(
        title: 'Price',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: AnsiErrorState(
              compact: true,
              what: 'the prices',
              error: error,
              stackTrace: stackTrace,
              onRetry: () =>
                  ref.invalidate(ingredientPricesProvider(ingredient.id)),
            ),
          ),
        ],
      );
    }

    if (prices.isEmpty) {
      return _Group(
        title: 'Price',
        suffix: '— none yet',
        children: [aside, door],
      );
    }

    // A receipt line is corrected on its receipt; the sheet holds typed prices.
    void fix(PriceObservation price) => price.source == ReceiptSource.photo
        ? context.pushOnce('/receipts/${price.receiptId}')
        : unawaited(
            showPriceSheet(context, ingredient: ingredient, editing: price),
          );

    final earlier = prices.skip(1).toList();
    return _Group(
      title: 'Price',
      children: [
        aside,
        const _Label('LATEST', hint: 'what a recipe reads'),
        AnsiTap(
          key: kLatestPriceKey,
          onTap: () => fix(prices.first),
          // A row of words, not a glyph: it needs no square target grown
          // under it, and growing one would move the group's rhythm.
          minTarget: false,
          child: _Fact(latestPriceFact(prices.first)),
        ),
        if (earlier.isNotEmpty) ...[
          const _Label('BEFORE'),
          _EarlierPrices(prices: earlier, onTap: fix),
          const _Fact(
            'a recipe reads the latest; the rest is what you paid, kept as '
            'paid',
            muted: true,
          ),
        ],
        door,
      ],
    );
  }
}

/// The prices before the latest, in the measures list's row shape. Each row
/// taps through to where it is edited.
class _EarlierPrices extends StatelessWidget {
  const _EarlierPrices({required this.prices, required this.onTap});

  final List<PriceObservation> prices;
  final ValueChanged<PriceObservation> onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final price in prices)
        Builder(
          builder: (context) {
            final fact = earlierPriceFact(price);
            return AnsiTap(
              onTap: () => onTap(price),
              minTarget: false,
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fact.paid,
                      style: ansiMono(size: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    fact.seen,
                    style: ansiMono(size: 9, color: AnsiColors.muted),
                  ),
                ],
              ),
            );
          },
        ),
    ],
  );
}

/// The `On receipts` fold's own tap target, exported so a test names it.
const kOnReceiptsFoldKey = ValueKey('on-receipts-fold');

/// One listed name's row, keyed by the name itself so a test taps the one it
/// means rather than the first one drawn.
ValueKey<String> onReceiptsNameKey(String namePrinted) =>
    ValueKey('on-receipts-$namePrinted');

/// Every printed name this row has been matched to on the household's receipts,
/// newest first, folded shut; absent on a row no receipt has carried.
///
/// These are a store's abbreviations, not aliases, and never reach the matcher
/// (see `domain/price_repository.dart`). A wrong entry is fixed on its receipt.
class _OnReceiptsGroup extends HookConsumerWidget {
  const _OnReceiptsGroup({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Called before the empty return, so the hook survives a row whose last
    // receipt is taken back while the page is open.
    final open = useState(false);
    // Decorative emptiness: the Price group above draws the error for this
    // seam.
    final names =
        ref
            .watch(ingredientReceiptNamesProvider(ingredient.id))
            .asData
            ?.value ??
        const <ReceiptName>[];
    if (names.isEmpty) return const SizedBox.shrink();

    return _Group(
      title: 'On receipts',
      children: [
        AnsiTap(
          key: kOnReceiptsFoldKey,
          onTap: () => open.value = !open.value,
          semanticsLabel: open.value
              ? 'Fold the names on receipts'
              : 'Unfold the names on receipts',
          color: AnsiColors.muted,
          padding: const EdgeInsets.only(top: 10, right: 8, bottom: 2),
          child: Row(
            children: [
              // No colour of its own: [AnsiTap] publishes the rest ink through
              // an [IconTheme] so it can take it back on hover.
              Icon(
                open.value
                    ? FLucideIcons.chevronDown
                    : FLucideIcons.chevronRight,
                size: 14,
              ),
              const SizedBox(width: 8),
              Text(
                onReceiptsFact(names),
                style: ansiMono(size: 12, color: AnsiColors.muted),
              ),
            ],
          ),
        ),
        if (open.value) ...[
          for (final name in names)
            AnsiTap(
              key: onReceiptsNameKey(name.namePrinted),
              // A wrong match is answered on the newest receipt that carries
              // the name.
              onTap: () => context.pushOnce('/receipts/${name.receiptId}'),
              // A row of words, not a glyph — the Price group's earlier rows
              // take the same shape for the same reason.
              minTarget: false,
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name.namePrinted,
                      style: ansiMono(size: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    receiptNameFact(name),
                    style: ansiMono(size: 9, color: AnsiColors.muted),
                  ),
                ],
              ),
            ),
          const _Fact(
            'what the receipt door remembers — not words this row is also '
            'known as; fix one on its own receipt, where the latest answer '
            'wins',
            muted: true,
          ),
        ] else
          const SizedBox.shrink(),
      ],
    );
  }
}

/// The measures as a short list — the editor's own three parts (the source
/// dot, the label with its amount, the provenance word) with nothing to tap.
class _ReadMeasures extends StatelessWidget {
  const _ReadMeasures({required this.measures});

  final List<Measure> measures;

  @override
  Widget build(BuildContext context) {
    // Same two exclusions the editor makes: the serving is stated above, in
    // Nutrition, and a volume-named label is a density.
    final listed = [
      for (final m in measures)
        if (!isVolumeUnitLabel(m.label) && !isServingMeasure(m)) m,
    ];
    if (listed.isEmpty) return const _Fact('No measures yet.', muted: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in listed)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(
              children: [
                SourceDot(kind: m.sourceKind),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    measureFact(m),
                    style: ansiMono(size: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  measureSourceWord(m.sourceKind),
                  style: ansiMono(size: 9, color: AnsiColors.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One stated fact under its micro-label. [muted] draws an honest absence
/// ("needs macros") as an aside.
class _Fact extends StatelessWidget {
  const _Fact(this.text, {this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: ansiMono(
        size: 12,
        color: muted ? AnsiColors.muted : AnsiColors.ink,
      ),
    ),
  );
}

class _DetailForm extends ConsumerWidget {
  const _DetailForm({
    required this.ingredientId,
    this.initialName = '',
    this.onDone,
    this.lookup,
    this.cameraPane,
    super.key,
  });

  /// Null while creating. Keys the [IngredientForm] that holds the form's
  /// state.
  final String? ingredientId;

  final String initialName;

  /// Returns to the fact sheet. Null while creating, where the form instead
  /// pops with the row it made.
  final VoidCallback? onDone;

  final OffLookup? lookup;
  final BarcodeCameraPane? cameraPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ingredientFormProvider(
      ingredientId,
      initialName: initialName,
    );
    final draft = ref.watch(provider);
    final form = ref.read(provider.notifier);
    final ing = draft.row;
    final creating = draft.creating;
    final draftRow = draft.editedRow;
    // The row as the form reads its provenance: the draft's pick, else the
    // stored stamp.
    final sourcedRow = draft.sourcedRow;
    final stub = draft.stub;
    final busy = draft.busy;
    // A row that does not exist has no stored children to watch — and asking
    // for them under a blank id would be a query about nothing.
    final measuresAsync = creating
        ? const AsyncValue<List<Measure>>.data([])
        : ref.watch(ingredientMeasuresProvider(ing.id));

    // The barcode door. The sheet needs a context, so it opens here and its
    // result goes back to the ViewModel as an intent.
    Future<void> scan() async {
      final draft = await scanBarcodeForDraft(
        context,
        // An explicit parameter wins (tests); otherwise the app's own client,
        // by provider — the seam `make test-sim` overrides.
        lookup: lookup ?? ref.read(offLookupProvider),
        cameraPane: cameraPane,
      );
      if (draft == null) return;
      form.applyScan(draft);
    }

    // The USDA search, shared by `Look up in USDA` and `Choose another ›`. It
    // asks about the name in the field, and a pick only fills the draft.
    Future<void> pickUsda() async {
      final pick = await showUsdaPickSheet(
        context,
        // The draft's provenance, so the short-list marks the current and
        // declined foods.
        ingredient: draft.sourcedRow,
        name: draft.name.trim().isEmpty ? ing.canonicalName : draft.name,
      );
      if (pick == null) return;
      form.applyUsdaPick(pick);
    }

    // The label door. The sheet needs a context, so the photo is chosen here
    // and the path goes back to the ViewModel, which reads it and says on the
    // form's own line if it could not.
    Future<void> readLabel() async {
      final path = await pickLabelPhoto(context, ref);
      if (path == null) return;
      await form.readLabelFromPhoto(path);
    }

    // Puts the form down: back to the fact sheet on a row that exists. A create
    // pops with the row for the caller awaiting it, or falls back to the
    // manager on a cold deep link.
    void leave([Ingredient? result]) {
      final done = onDone;
      if (done != null) {
        // Unfocus first: a focused field leaving the tree keeps asking for its
        // caret.
        FocusManager.instance.primaryFocus?.unfocus();
        done();
        return;
      }
      ansiBack(context, home: _managerRoute, result: result);
    }

    // Takes a near match instead, after asking. Create form only: on an
    // existing row the near names are information, because taking one would be
    // a merge.
    Future<void> useInstead(NameEntry near) async {
      // Captured before the dialog: the row that opened this form can be gone
      // by the time the question is answered.
      final repo = ref.read(ingredientRepositoryProvider);
      final took = await askAnsi(
        context,
        title: 'Use ${near.ingredientName} instead?',
        body:
            '${near.ingredientName} is already in your ingredients. '
            'Nothing you have typed here is saved.',
        confirm: 'Use ${near.ingredientName}',
        cancel: 'Keep typing',
      );
      if (!took) return;
      final row = await repo.byId(near.ingredientId);
      if (row == null || !context.mounted) return;
      leave(row);
    }

    Future<Ingredient?> save({bool markComplete = false}) =>
        ref.write<Ingredient?>(
          context,
          'save ${ing.canonicalName}',
          () => form.save(markComplete: markComplete),
        );

    // Completing ends the page, because the ingredient picker awaits its pop.
    // Save and mark go in one transaction so a failure cannot leave the row
    // saved but unmarked.
    Future<void> completeRow() async {
      final saved = await save(markComplete: true);
      if (saved == null || !context.mounted) return;
      leave(saved);
    }

    Future<void> unconfirmRow() =>
        ref.writeOk(context, 'unconfirm ${ing.canonicalName}', form.unconfirm);

    // A refused delete names the count of recipes, in the message line.
    Future<void> deleteRow() async {
      final outcome = await ref.write(
        context,
        'delete ${ing.canonicalName}',
        form.delete,
      );
      if (outcome is! Deleted || !context.mounted) return;
      ansiBack(context, home: _managerRoute);
    }

    // The measures as the form holds them: loaded, minus removals, plus
    // additions.
    final loadedMeasures = measuresAsync.asData?.value;
    final measures = [
      for (final m in loadedMeasures ?? const <Measure>[])
        if (!draft.measuresRemoved.contains(m.id)) m,
      ...draft.measuresAdded,
    ];

    final dock = _ActionBar(
      creating: creating,
      stub: stub,
      canComplete: !busy && draft.completable,
      // Why the disabled CTA waits, else what a save said or a delete
      // refused.
      message: draft.dockLine,
      // Only the button leaves; other callers use the save as a flush. On a
      // new row Save is the completion. A taken name disables it.
      onSave: busy || draft.nameCollision != null
          ? null
          : creating
          ? completeRow
          : () async {
              final saved = await save();
              if (saved != null && context.mounted) leave(saved);
            },
      onComplete: completeRow,
    );

    final fields = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        // Slots, not conditional children: an unkeyed insertion in a ListView
        // shifts every sibling and silently resets its state.
        _StatusStrip(ingredient: ing, creating: creating),

        // The three prefill doors. The scan is a stub's door (a draft fills
        // only empty fields); the lookup is every row's, hidden only where
        // the card below already offers `Choose another ›`; the label is
        // every row's and never hides, because a second photo is the fix
        // for a first one that read badly.
        _FillItIn(
          // No scan door on the web: there is no camera or detector.
          scan: stub && !kIsWeb
              ? _GhostButton(label: 'Scan a barcode', onTap: busy ? null : scan)
              : null,
          usda: isUsdaPrefilled(sourcedRow.source)
              ? null
              : _GhostButton(
                  label: 'Look up in USDA',
                  onTap: busy ? null : pickUsda,
                ),
          label: _GhostButton(
            label: 'Read a label',
            onTap: busy ? null : readLabel,
          ),
        ),

        if (draft.scanned != null && draft.scanApplied != null)
          _ScanResult(
            draft: draft.scanned!,
            applied: draft.scanApplied!,
            packAdded: draft.packAdded,
            // The pack size is an offer: tapped, it lands in the draft like
            // any measure.
            onAddPack: () async =>
                form.addPackMeasure(sortOrder: measures.length),
          )
        else
          const SizedBox.shrink(),

        // Field order: name, aliases, category and default unit, macros,
        // density.
        _Group(
          title: 'Identity',
          children: [
            const _Label('CANONICAL NAME'),
            _CanonicalNameField(
              name: draft.name,
              seed: draft.nameSeed,
              onChanged: form.setName,
              onLeave: form.leaveNameField,
            ),
            if (draft.nameWas != null)
              WasWordLine(oldWord: draft.nameWas!, onKeep: form.keepName),
            // The namespace's two answers, never both: taken, or nearly
            // somebody else's.
            if (draft.nameCollision case final taken?)
              _AlreadyAnIngredient(taken)
            else if (draft.nameNearMatches.isNotEmpty)
              _DidYouMean(
                matches: draft.nameNearMatches,
                // On an existing row near names are information only; this
                // form never merges.
                onUse: creating ? useInstead : null,
              ),

            const _Label('ALSO KNOWN AS'),
            _AliasEditor(
              aliases: [
                // Decorative emptiness: an alias that did not load is
                // re-added harmlessly, because `saveForm` is find-or-create
                // on match_text.
                for (final a
                    in (creating
                            ? null
                            : ref
                                  .watch(ingredientAliasesProvider(ing.id))
                                  .asData
                                  ?.value) ??
                        const <IngredientAlias>[])
                  if (!draft.aliasesRemoved.contains(a.id)) a,
                ...draft.aliasesAdded,
              ],
              onAdd: form.addAlias,
              onRemove: form.removeAlias,
            ),

            const _Label('CATEGORY'),
            _CategoryPicker(selected: draft.category, onPick: form.setCategory),
          ],
        ),

        _Group(
          title: 'Nutrition',
          children: [
            // A slot. Reads the draft's provenance so a fresh pick is named
            // at once.
            _UsdaProvenance(
              ingredient: sourcedRow,
              pending: draft.sourcePending,
              onDecline: busy
                  ? null
                  : () => ref.writeOk(
                      context,
                      'undo the USDA fill',
                      form.declineUsda,
                    ),
              onChooseAnother: busy ? null : pickUsda,
            ),
            // The same fact for a scanned row, with no doors to offer.
            _BarcodeProvenance(ingredient: sourcedRow, basis: draft.basis),
            // And for a row read off a photographed label, which offers
            // exactly one: putting the fields back.
            _LabelProvenance(
              ingredient: sourcedRow,
              pending: draft.sourcePending,
              basis: draft.basis,
              notes: draft.labelNotes,
              onUndo: busy || draft.labelUndo == null
                  ? null
                  : form.undoLabelFill,
            ),

            const _Label('MACROS', hint: 'as the label reads · fibre optional'),
            // Per 100 of the basis, or per serving. Each leg unfocuses first,
            // because a mode change rebuilds the four fields around fresh
            // controllers.
            Row(
              children: [
                AnsiModeChip(
                  label: 'per 100 g',
                  selected:
                      !draft.perServing && draft.basis == MacrosBasis.perG,
                  onTap: () => _leaveFields(() {
                    form.setBasis(MacrosBasis.perG);
                  }),
                ),
                const SizedBox(width: 6),
                AnsiModeChip(
                  label: 'per 100 ml',
                  selected:
                      !draft.perServing && draft.basis == MacrosBasis.perMl,
                  onTap: () => _leaveFields(() {
                    form.setBasis(MacrosBasis.perMl);
                  }),
                ),
                const SizedBox(width: 6),
                AnsiModeChip(
                  label: 'per serving',
                  selected: draft.perServing,
                  onTap: () => _leaveFields(form.setPerServing),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Three slots that hold their positions in either mode. The
            // serving unit sets the basis, so the admission chips follow it
            // live.
            if (draft.perServing)
              Padding(
                // Breathing room before the figures: the serving is the
                // sentence's subject, and the four are its predicate.
                padding: const EdgeInsets.only(bottom: 10),
                child: ServingRow(
                  key: ValueKey('serving-row-${draft.servingSeed}'),
                  draft: draft.serving,
                  onAmount: form.setServingAmount,
                  onUnit: form.setServingUnit,
                ),
              )
            else
              const SizedBox.shrink(),
            // Keyed by row-version, which changes only when the macros were
            // re-seeded.
            MacroFields(
              key: ValueKey('macro-fields-${draft.macroSeed}'),
              draft: draft.macros,
              onChanged: form.setMacros,
            ),
            // The derived per-100 line, and on a scanned row the pack's
            // per-serving against its per-100 column; else the nudge that
            // per-serving mode exists.
            if (draft.perServing) ...[
              StoredPer100Line(
                serving: draft.serving,
                printed: draft.printedMacros,
              ),
              ScannedServingLine(
                serving: draft.serving,
                printed: draft.printedMacros,
                per100: draft.scannedPer100,
              ),
            ] else if (draft.scannedPer100NeedsServingHint)
              const ScannedPerServingNudge()
            else
              ScannedServingLine(
                serving: draft.serving,
                printed: draft.serving.packPrinted,
                per100: draft.printedMacros,
              ),
            // The doubt is about what will be stored, so it shows in every
            // mode.
            MacrosDoubtLine(stored: draft.storedMacros),
          ],
        ),

        // Density, piece weight, admission, default unit and measures are one
        // group, so a stranded default is repaired in the section that flags
        // it.
        _Group(
          title: 'Units & measures',
          children: [
            const _Label('DEFAULT UNIT'),
            _UnitChoiceRow(
              // Keyed so a test can ask this row — and only this row —
              // which of its chips are locked.
              key: const ValueKey('default-unit-row'),
              ingredient: draftRow,
              selected: draft.defaultUnit,
              onPick: form.setDefaultUnit,
            ),
            // A stored default the rules no longer support is flagged, never
            // rewritten.
            _StrandedDefaultNote(
              ingredient: draftRow,
              onFix: () => ref.write<Ingredient?>(
                context,
                'save ${ing.canonicalName}',
                form.fixStrandedDefault,
              ),
            ),

            // The piece weight (ADR-0015), only under a count default. It
            // goes in the draft.
            if (draft.defaultUnit.family == UnitFamily.count)
              PieceWeightEntry(
                ingredient: draftRow,
                saveLabel: 'Add',
                onSave: (amount) async {
                  form.draftPieceWeight(amount);
                  return true;
                },
                onRemove: () async {
                  form.removePieceWeight();
                  return true;
                },
              ),

            const _Label('ALLOWED UNITS', hint: 'what a line may say'),
            _AdmissionChips(
              ingredient: draftRow,
              selected: draft.allowed,
              onToggle: form.toggleUnit,
            ),

            // The entry draws its own DENSITY label, so the section does
            // not repeat one above it.
            DensityEntry(
              // `draftRow`, so the headline and the removal warning show the
              // held density.
              ingredient: draftRow,
              // The row's own serving, so the sentence reopens in the unit
              // the fact sheet states this density in.
              serving: servingMeasureOf(measures),
              redirectedSpoon: draft.redirectedSpoon,
              // The serving above is offered as the density's left-hand side.
              servingPrefill: draft.densityPrefill,
              // Goes in the draft; the form's Save lands it.
              saveLabel: 'Add',
              onSave: (gPerMl) async {
                form.draftDensity(gPerMl);
                return true;
              },
              onRemove: () async {
                form.removeDensity();
                return true;
              },
            ),

            const _Label('MEASURES', hint: 'count-like, in the basis'),
            // Load-bearing emptiness: an errored stream drawn as empty would
            // let the next Save write the narrowed set back.
            if (measuresAsync case AsyncError(:final error, :final stackTrace))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AnsiErrorState(
                  compact: true,
                  what: 'the measures',
                  error: error,
                  stackTrace: stackTrace,
                  onRetry: () =>
                      ref.invalidate(ingredientMeasuresProvider(ing.id)),
                ),
              )
            else
              MeasuresEditor(
                ingredient: ing,
                measures: measures,
                // It adds to the draft here; the docked Save lands it.
                addLabel: 'Add',
                // A stored measure a recipe still uses is refused here, not
                // at Save.
                onDelete: (m) async {
                  if (!await mayDeleteMeasure(context, ref, m)) return;
                  form.removeMeasure(m.id);
                },
                // Goes in the draft; the editor has already validated it.
                onAdd: (label, amount) async => MeasureAdded(
                  form.draftMeasure(label, amount, sortOrder: measures.length),
                ),
                // A drafted measure is re-stated in the draft. A stored one
                // is a live row, so its correction writes at once, under the
                // guard.
                onEdit: (m, label, amount) async {
                  final drafted = form.editDraftMeasure(m.id, label, amount);
                  if (drafted != null) return MeasureAdded(drafted);
                  final landed = await ref.write(
                    context,
                    'save that measure',
                    () async {
                      final repo = ref.read(measureRepositoryProvider);
                      try {
                        if (label != m.label) {
                          await repo.renameMeasure(m.id, label);
                        }
                        if (amount != m.amount) {
                          await repo.setMeasureAmount(m.id, amount);
                        }
                        // ArgumentError is renameMeasure's documented
                        // validation contract.
                        // ignore: avoid_catching_errors
                      } on ArgumentError catch (e) {
                        return MeasureRefused('${e.message}');
                      }
                      return MeasureAdded(
                        Measure(
                          id: m.id,
                          label: label,
                          amount: amount,
                          basis: m.basis,
                          sortOrder: m.sortOrder,
                          source: m.source,
                        ),
                      );
                    },
                  );
                  return landed ?? const MeasureNotAdded();
                },
                // Drafted rows carry their position to Save; stored ones are
                // re-stamped now.
                onReorder: (ids) async {
                  form.reorderDraftMeasures(ids);
                  if (creating) return;
                  await ref.write(
                    context,
                    'reorder those measures',
                    () => ref
                        .read(measureRepositoryProvider)
                        .reorderMeasures(ing.id, ids),
                  );
                },
                // The form selects no measure; the watched provider
                // re-renders the list.
                onAdded: (_) {},
                // A volume-named label is a density (ADR-0008 §2): redirect
                // to that section.
                onVolumeLabel: form.redirectSpoon,
              ),
          ],
        ),

        // The stored row, not the draft: the price sheet writes at once.
        _PriceGroup(ingredient: ing, editing: true, creating: creating),
      ],
    );

    return FScaffold(
      childPad: false,
      header: _header(
        context,
        title: ing.canonicalName,
        // Back out of editing returns to the fact sheet and discards the draft.
        onBack: onDone == null ? null : leave,
        suffixes: [
          // Nothing to delete and nothing to un-confirm on a row that does
          // not exist yet.
          if (creating)
            const SizedBox.shrink()
          else
            FPopoverMenu(
              // `menuBuilder`, not `menu`: an item has to dismiss the menu it
              // was picked from before it navigates (the recipe view's rule).
              menuBuilder: (_, controller, _) => [
                FItemGroup(
                  children: [
                    if (!stub)
                      FItem(
                        prefix: const Icon(FLucideIcons.rotateCcw),
                        title: const Text('Return it to a stub'),
                        onPress: () {
                          unawaited(controller.hide());
                          unawaited(unconfirmRow());
                        },
                      ),
                    FItem(
                      prefix: const Icon(FLucideIcons.trash2),
                      title: const Text('Delete ingredient'),
                      onPress: () {
                        unawaited(controller.hide());
                        unawaited(deleteRow());
                      },
                    ),
                  ],
                ),
              ],
              builder: (context, controller, _) => FHeaderAction(
                icon: const Icon(FLucideIcons.ellipsis),
                onPress: controller.toggle,
              ),
            ),
        ],
      ),
      // Pinned, so Save and Delete are reachable from any scroll position. Gone
      // while a label is read: the reading screen is the whole page until the
      // figures land.
      footer: draft.readingLabel ? null : dock,
      // The recipe import's reading screen, over the form rather than in
      // place of it, so the fields and the scroll are where they were left.
      child: Stack(
        children: [
          fields,
          if (draft.readingLabel)
            const Positioned.fill(child: LabelReadProgress()),
        ],
      ),
    );
  }
}

// --- Sections ----------------------------------------------------------------

/// The USDA provenance card: which food filled this row, how well it fits the
/// name, and the `Not this food` / `Choose another` doors.
///
/// Reads the `source_label` / `source_score` the form holds, never a live
/// probe, and names the food rather than its FDC id (the id shows only when the
/// label is empty). Four states: [pending] (picked, not saved), prefilled,
/// edited (muted, with what was overridden) and declined (`Choose another`
/// alone).
class _UsdaProvenance extends StatelessWidget {
  const _UsdaProvenance({
    required this.ingredient,
    required this.pending,
    required this.onDecline,
    required this.onChooseAnother,
  });

  /// The row with the draft's pick folded in
  /// (`IngredientFormDraft.sourcedRow`).
  final Ingredient ingredient;

  /// The stamp is the draft's and no Save has written it yet.
  final bool pending;

  /// *Not this food*. Null disables the door (a write in flight).
  final Future<void> Function()? onDecline;

  /// *Choose another ▸*. Null disables the door.
  final Future<void> Function()? onChooseAnother;

  @override
  Widget build(BuildContext context) {
    final source = ingredient.source;
    if (!isUsdaPrefilled(source) && !isUsdaDeclined(source)) {
      return const SizedBox.shrink();
    }
    final declined = isUsdaDeclined(source);
    final stub = ingredient.status == IngredientStatus.stub;
    final edited = !declined && ingredient.sourceEdited;
    final label = ingredient.sourceLabel;
    final score = ingredient.sourceScore;
    final name = ingredient.canonicalName;

    // The food this card is about, named: the id is the last resort, not a
    // caption, so a row that can name its food says the name and nothing else.
    final food = label != null && label.isNotEmpty
        ? label
        : 'FDC ${usdaFdcId(source) ?? '?'}';
    final fit = score == null ? null : UsdaMatchFit.of(score).phraseFor(name);

    final String header;
    final String line;
    if (declined) {
      header = 'USDA · declined';
      line =
          '${label ?? 'that USDA food'} — not this food · the filled numbers '
          'were cleared';
    } else if (pending) {
      // The tense is the whole point: these numbers are in the fields and
      // nowhere else, and the dock's Save is what makes them the row's.
      header = 'From USDA · not saved';
      line = ['will be filled from $food', ?fit].join(' · ');
    } else {
      // `edited here` replaces the confirm word.
      header = edited
          ? 'Filled from USDA · edited here'
          : 'Filled from USDA · ${stub ? 'not confirmed' : 'confirmed'}';
      line = [food, ?fit].join(' · ');
    }
    // Amber only where there is something to do: an unconfirmed machine fill,
    // or a pick awaiting Save. Confirmed, edited and declined cards stay muted.
    final calm = declined || (!pending && (edited || !stub));
    final tone = calm ? AnsiColors.muted : AnsiColors.aging;

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: calm ? AnsiColors.line : tone),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                declined
                    ? FLucideIcons.circleOff
                    // A pending pick wears the dock's verb, not a warning.
                    : pending
                    ? FLucideIcons.save
                    // A pencil, not a ⚠: the row was written on, not broken.
                    : edited
                    ? FLucideIcons.pencil
                    : stub
                    ? FLucideIcons.triangleAlert
                    : FLucideIcons.database,
                size: 13,
                color: tone,
              ),
              const SizedBox(width: 6),
              Text(header, style: ansiSans(size: 13, weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(line, style: ansiMono(size: 10, color: AnsiColors.muted)),
          if (edited) ...[
            const SizedBox(height: 3),
            Text(
              '${_overriddenNumbers(ingredient)} — the numbers on this row are '
              'no longer the source’s',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            spacing: 8,
            children: [
              if (!declined)
                FButton(
                  size: FButtonSizeVariant.sm,
                  variant: FButtonVariant.outline,
                  onPress: onDecline,
                  child: const Text('Not this food'),
                ),
              FButton(
                size: FButtonSizeVariant.sm,
                variant: FButtonVariant.outline,
                onPress: onChooseAnother,
                child: const Text('Choose another ›'),
              ),
            ],
          ),
          if (declined)
            const _Note(
              'renaming this row will not refill it — you said no once',
            ),
        ],
      ),
    );
  }
}

/// The pack a barcode scan filled this row from, named from `source_label` on
/// one line, led by `edited ·` once a human has overridden the numbers. A row
/// with no label draws nothing rather than printing its barcode.
class _BarcodeProvenance extends StatelessWidget {
  const _BarcodeProvenance({required this.ingredient, required this.basis});

  /// The row with the draft's stamp folded in
  /// (`IngredientFormDraft.sourcedRow`).
  final Ingredient ingredient;

  /// The draft's basis, named in the head so the reader knows which 100 the
  /// figures are per.
  final MacrosBasis basis;

  @override
  Widget build(BuildContext context) {
    final label = ingredient.sourceLabel;
    if (!isBarcodeFilled(ingredient.source) || label == null || label.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        '${ingredient.sourceEdited ? 'edited · ' : ''}Filled from a barcode · '
        'per 100 ${basis.dbValue}\n$label',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    );
  }
}

/// The nutrition label this row was read from. A photo names no food, so
/// there is nothing to print but the fact and which 100 the figures are per.
///
/// While the fill is still only in the fields it wears the pending card's
/// tense and offers the undo; once saved it is one muted line, like a scan's.
class _LabelProvenance extends StatelessWidget {
  const _LabelProvenance({
    required this.ingredient,
    required this.pending,
    required this.basis,
    required this.onUndo,
    this.notes = const [],
  });

  /// The row with the draft's stamp folded in
  /// (`IngredientFormDraft.sourcedRow`).
  final Ingredient ingredient;

  /// The stamp is the draft's and no Save has written it yet.
  final bool pending;

  /// The draft's basis, named so the reader knows which 100 the figures are
  /// per.
  final MacrosBasis basis;

  /// What the read could not make out, said on the card it belongs to.
  final List<String> notes;

  /// Puts the fields back the way the read found them. Null while busy, or
  /// once there is nothing left to undo.
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    if (!isLabelFilled(ingredient.source)) return const SizedBox.shrink();
    // The muted line is the same either way: the figures came off a photograph
    // and the label is the thing to check them against.
    const line = 'read from a photo — check it against the label';
    if (!pending) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          '${ingredient.sourceEdited ? 'edited · ' : ''}Filled from a label · '
          'per 100 ${basis.dbValue}\n$line',
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.aging),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The dock's verb, not a warning: nothing is wrong, it is just
              // not the row's yet.
              const Icon(FLucideIcons.save, size: 13, color: AnsiColors.aging),
              const SizedBox(width: 6),
              Text(
                'From a label · not saved',
                style: ansiSans(size: 13, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(line, style: ansiMono(size: 10, color: AnsiColors.muted)),
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                note,
                style: ansiMono(size: 10, color: AnsiColors.cautionInk),
              ),
            ),
          const SizedBox(height: 8),
          FButton(
            size: FButtonSizeVariant.sm,
            variant: FButtonVariant.outline,
            onPress: onUndo,
            child: const Text('Undo the fill'),
          ),
        ],
      ),
    );
  }
}

/// Which numbers the `edited here` line names. `source_edited` is one boolean,
/// so this reads what the row now carries, not which field was typed; a row
/// carrying neither says the plain thing.
String _overriddenNumbers(Ingredient ingredient) {
  final macros = ingredient.macros != null;
  final density = ingredient.densityGPerMl != null;
  if (macros && density) return 'your macros and your density';
  if (macros) return 'your macros';
  if (density) return 'your density';
  return 'edited here';
}

/// `＋ add “pack” = 400 g as a measure` — the offer's own words. The amount is
/// in the row's basis, so it reads the way a scale reads.
String _packOfferLabel(PackMeasureOffer pack) {
  final basis = pack.basis.baseUnit;
  return '＋ add “pack” = ${formatQuantityIn(pack.amountInBasis, basis)} '
      '${basis.label} as a measure';
}

/// What the form's scan landed: the shared result card, a note that nothing is
/// saved or confirmed, and the pack-size offer.
class _ScanResult extends StatelessWidget {
  const _ScanResult({
    required this.draft,
    required this.applied,
    required this.packAdded,
    required this.onAddPack,
  });

  final IngredientDraft draft;
  final DraftApplication applied;
  final bool packAdded;
  final Future<void> Function() onAddPack;

  @override
  Widget build(BuildContext context) {
    final pack = applied.packMeasure;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DraftCard(draft: draft, skipped: applied.skipped),
          _Note(
            applied.fillsSomething
                ? 'filled in, not saved — Save keeps it, and nothing counts '
                      'until you confirm.'
                : 'nothing to fill in — every field it could answer already '
                      'had an answer.',
          ),
          // The pack size is an offer: a measure lands only because it was
          // tapped.
          if (pack != null && !packAdded)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _GhostButton(
                label: _packOfferLabel(pack),
                onTap: onAddPack,
              ),
            )
          else if (pack != null)
            const _Note('pack added below — rename it or bin it there.'),
        ],
      ),
    );
  }
}

/// The admission section: the units this row says, the ones it could, and after
/// a divider the imprecise words. Locked units are one line naming what unlocks
/// them, not dead chips.
class _AdmissionChips extends StatelessWidget {
  const _AdmissionChips({
    required this.ingredient,
    required this.selected,
    required this.onToggle,
  });

  final Ingredient ingredient;
  final Set<Unit> selected;
  final ValueChanged<Unit> onToggle;

  @override
  Widget build(BuildContext context) {
    final candidates = allowedUnitCandidates(ingredient).toList();
    final fixed = ingredient.defaultUnit;
    final sayable = [
      for (final c in candidates)
        if (!c.locked && c.unit.family != UnitFamily.imprecise) c,
    ];
    final words = [
      for (final c in candidates)
        if (!c.locked && c.unit.family == UnitFamily.imprecise) c,
    ];
    // `piece` waits on a piece weight, which no density ever unlocks — so its
    // line is its own (ADR-0015).
    final pieceLocked = candidates.any((c) => c.locked && c.unit == pieces);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final c in sayable)
              _UnitChip(
                unit: c.unit,
                selected: selected.contains(c.unit),
                locked: c.unit == fixed,
                onTap: () => onToggle(c.unit),
              ),
            // The divider the quantity sheet draws before the same words.
            if (words.isNotEmpty) ...[
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                color: AnsiColors.line,
              ),
              for (final c in words)
                _UnitChip(
                  unit: c.unit,
                  selected: selected.contains(c.unit),
                  locked: c.unit == fixed,
                  onTap: () => onToggle(c.unit),
                ),
            ],
          ],
        ),
        // The default unit cannot be turned off, so a note says why its tap is
        // inert.
        if (candidates.any((c) => !c.locked && c.unit == fixed))
          _Note('${fixed.label} stays on — the row is bought in it'),
        // The density note is printed once, under the default-unit row above.
        if (pieceLocked)
          const _Note('piece unlocks when this row has a piece weight'),
      ],
    );
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({
    required this.unit,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final Unit unit;
  final bool selected;

  /// The row's own default unit: drawn on, but inert.
  final bool locked;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: locked ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herbSoft : AnsiColors.surface,
          border: Border.all(
            color: selected ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          unit.label,
          style: ansiMono(
            size: 11,
            color: selected ? AnsiColors.herbDeep : AnsiColors.muted,
          ),
        ),
      ),
    );
  }
}

/// The category field: a dropdown of the household's own categories plus a door
/// to coin one. Not free text, because the imprecise-unit gate
/// ([kImpreciseCategoryGates]) and the list's grouping match the string
/// exactly.
class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({required this.selected, required this.onPick});

  /// The draft's category — the empty string for "none", which is a real and
  /// honest answer (a row need not have one).
  final String selected;
  final ValueChanged<String> onPick;

  /// A sentinel value: `FSelect` needs a non-null value per item, and the
  /// empty string is a legitimate category-less row.
  static const _none = '\u0000none';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Decorative emptiness: these are suggestions, and the row's own is added
    // below.
    final known = ref.watch(ingredientCategoriesProvider).asData?.value ?? [];
    // A stored category is always offered, even when no other row carries it.
    final options = {...known, if (selected.isNotEmpty) selected}.toList()
      ..sort();

    return Row(
      children: [
        Expanded(
          child: FSelect<String>.rich(
            format: (c) => c == _none ? 'no category' : c,
            control: FSelectControl<String>.lifted(
              value: selected.isEmpty ? _none : selected,
              onChange: (c) => onPick(c == null || c == _none ? '' : c),
            ),
            children: [
              const FSelectItem(title: Text('no category'), value: _none),
              for (final c in options) FSelectItem(title: Text(c), value: c),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FButton(
          size: FButtonSizeVariant.sm,
          variant: FButtonVariant.outline,
          onPress: () async {
            final coined = await promptForText(
              context,
              title: 'New category',
              hint: 'e.g. produce',
              confirm: 'Use it',
            );
            if (coined == null || coined.trim().isEmpty) return;
            onPick(coined.trim());
          },
          child: const Text('New'),
        ),
      ],
    );
  }
}

/// The single-select default-unit row. Draws only the units the row can be
/// counted in ([defaultUnitOfferFor]); the rest are named in one line under it.
class _UnitChoiceRow extends StatelessWidget {
  const _UnitChoiceRow({
    required this.ingredient,
    required this.selected,
    required this.onPick,
    super.key,
  });

  final Ingredient ingredient;
  final Unit selected;
  final ValueChanged<Unit> onPick;

  @override
  Widget build(BuildContext context) {
    final offer = defaultUnitOfferFor(ingredient);
    // Wrapped: the catalog is wider than a phone and a scroller clipped it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final u in offer.choices)
              AnsiModeChip(
                label: u.label,
                // A stranded default is still the selection, repainted in the
                // "gone" colour.
                selected: u == selected,
                stranded: u == selected && defaultUnitStranded(ingredient),
                onTap: () => onPick(u),
              ),
          ],
        ),
        if (offer.needDensity.isNotEmpty)
          _Note(
            '${offer.needDensity.map((u) => u.label).join(' · ')} unlock when '
            'this row has a density',
          ),
      ],
    );
  }
}

/// Flags a default unit the row cannot convert (`cup` with no density, `piece`
/// with no piece weight), naming the missing number with the chip above in
/// [AnsiColors.gone]. The default is never rewritten, and Save refuses while
/// this shows.
class _StrandedDefaultNote extends StatelessWidget {
  const _StrandedDefaultNote({required this.ingredient, required this.onFix});

  final Ingredient ingredient;
  final Future<void> Function() onFix;

  @override
  Widget build(BuildContext context) {
    if (!defaultUnitStranded(ingredient)) return const SizedBox.shrink();
    final fix = basisDefaultUnitFix(ingredient);
    // Two strandings (ADR-0015), each naming the number that repairs it.
    final needs = defaultUnitNeedsPieceWeight(ingredient)
        ? 'needs a weight on this row — enter one below, or'
        : 'needs a density on this row — add one below, or';
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(
            '${ingredient.defaultUnit.label} $needs',
            style: ansiMono(size: 10, color: AnsiColors.gone),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onFix,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AnsiColors.line)),
              ),
              child: Text('switch to ${fix.label}', style: ansiMono(size: 10)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The canonical-name field. Leaving it tidies the name; the host draws the
/// `was “…”` line when a word changed.
///
/// The draft owns the text: when [seed] moves (a scan, a tidy) the new text is
/// pushed into the existing controller. Re-keying would replace a focused field
/// under the gesture that tapped Save.
class _CanonicalNameField extends HookWidget {
  const _CanonicalNameField({
    required this.name,
    required this.seed,
    required this.onChanged,
    required this.onLeave,
  });

  final String name;
  final int seed;
  final ValueChanged<String> onChanged;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: name);
    useEffect(() {
      controller.text = name;
      return null;
    }, [seed]);
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) onLeave();
      },
      child: FTextField(
        control: FTextFieldControl.managed(
          controller: controller,
          onChange: (v) => onChanged(v.text),
        ),
      ),
    );
  }
}

/// "Also known as": the alias chips. Presentational; the host supplies the list
/// and takes the two intents. An alias whose normalized match text is empty is
/// refused here, because the repository throws `ArgumentError` for it.
class _AliasEditor extends HookWidget {
  const _AliasEditor({
    required this.aliases,
    required this.onAdd,
    required this.onRemove,
  });

  final List<IngredientAlias> aliases;

  /// Adds the alias to the draft and answers null, or the entry that already
  /// holds that name.
  final Future<NameEntry?> Function(String text) onAdd;

  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final adding = useState(false);
    final entry = useTextEditingController();
    final error = useState<String?>(null);
    final taken = useState<NameEntry?>(null);

    // An alias is stored lowercase, so its tidy is whitespace and a trailing
    // stop only — silent by construction, and never a word.
    void tidy() => entry.text = cleanName(entry.text, NameKind.alias);

    Future<void> add() async {
      tidy();
      // Same normalizer as the repository, so the two verdicts cannot
      // disagree about what carries an identity word.
      if (normalizeMatchText(entry.text).isEmpty) {
        taken.value = null;
        error.value =
            'That alias carries no identity word — it would match '
            'everything and nothing.';
        return;
      }
      final collision = await onAdd(entry.text);
      if (collision != null) {
        error.value = null;
        taken.value = collision;
        return;
      }
      error.value = null;
      taken.value = null;
      // The field is leaving the tree, so the keyboard goes with it.
      FocusManager.instance.primaryFocus?.unfocus();
      entry.clear();
      adding.value = false;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final a in aliases)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onRemove(a.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AnsiColors.paper,
                    border: Border.all(color: AnsiColors.line),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(a.text, style: ansiMono(size: 11)),
                      const SizedBox(width: 5),
                      const Icon(
                        FLucideIcons.x,
                        size: 10,
                        color: AnsiColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            if (!adding.value)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => adding.value = true,
                child: DashedBorderBox(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        FLucideIcons.plus,
                        size: 11,
                        color: AnsiColors.herb,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'alias',
                        style: ansiMono(size: 11, color: AnsiColors.herb),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (adding.value) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) tidy();
                  },
                  child: FTextField(
                    key: const ValueKey('alias-entry'),
                    hint: 'another name for this',
                    control: FTextFieldControl.managed(controller: entry),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FButton(
                key: const ValueKey('alias-add'),
                size: FButtonSizeVariant.sm,
                onPress: () => unawaited(add()),
                child: const Text('Add'),
              ),
            ],
          ),
        ],
        if (taken.value case final collision?)
          _AlreadyAnIngredient(collision)
        else if (error.value != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error.value!,
              style: ansiMono(size: 10, color: AnsiColors.gone),
            ),
          ),
      ],
    );
  }
}

// --- Small shared pieces -----------------------------------------------------

/// The namespace's refusal under the name field, worded by [nameTakenMessage].
/// The existing name is a door onto that row.
class _AlreadyAnIngredient extends StatelessWidget {
  const _AlreadyAnIngredient(this.taken);

  final NameEntry taken;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          kNameTakenPrefix,
          style: ansiMono(size: 10, color: AnsiColors.gone),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              context.pushOnce(ingredientDetailRoute(taken.ingredientId)),
          child: Text(
            taken.ingredientName,
            style: ansiMono(
              size: 10,
              color: AnsiColors.herbDeep,
            ).copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ],
    ),
  );
}

/// `DID YOU MEAN` under the name field, over the guarded typo tier. [onUse] is
/// the create form's offer to use that row instead; null on an existing row,
/// where taking one would be a merge.
class _DidYouMean extends StatelessWidget {
  const _DidYouMean({required this.matches, this.onUse});

  final List<NameEntry> matches;
  final void Function(NameEntry near)? onUse;

  @override
  Widget build(BuildContext context) {
    final take = onUse;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DidYouMeanHeader(),
          for (final near in matches)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: take == null ? null : () => take(near),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        near.ingredientName,
                        style: ansiSans(size: 13, weight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Which spelling matched, when it was not the row's own
                    // name.
                    if (near.isAlias) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'alias · ${near.text}',
                          style: ansiMono(size: 10, color: AnsiColors.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    if (take != null) ...[
                      const Spacer(),
                      const Icon(
                        FLucideIcons.chevronRight,
                        size: 14,
                        color: AnsiColors.herb,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A secondary action that reads as available without competing with the
/// screen's primary CTA.
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;

  /// Null while in flight or unavailable, which greys the button.
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: ansiMono(
            size: 12,
            color: enabled ? AnsiColors.ink : AnsiColors.muted,
          ),
        ),
      ),
    );
  }
}

/// The shared [AnsiMicroLabel] with this form's spacing.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.hint});

  final String text;

  /// The sentence-case qualifier, or null — the label says what the field is,
  /// this says how to read it.
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: AnsiMicroLabel(text, hint: hint, gap: 6),
  );
}

/// One named group of the form: a serif heading and a hairline over its fields.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.suffix});

  final String title;

  /// A quieter clause beside the heading for the group's state: `Price — none
  /// yet`.
  final String? suffix;

  /// Fixed slots: a section that is off renders `SizedBox.shrink()`, so its
  /// siblings keep their positions and hook state.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: title,
            style: ansiSerif(size: AnsiType.row),
            children: [
              if (suffix case final suffix?)
                TextSpan(
                  text: ' $suffix',
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Container(height: 1, color: AnsiColors.line),
        ...children,
      ],
    ),
  );
}

/// Whether this row counts in totals yet, at the top of the form.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.ingredient, this.creating = false});

  final Ingredient ingredient;

  /// A row that does not exist yet. It says so rather than calling itself a
  /// stub, which only a saved row is.
  final bool creating;

  @override
  Widget build(BuildContext context) {
    final stub = ingredient.status == IngredientStatus.stub;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AnsiColors.surface,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stub ? AnsiColors.muted : AnsiColors.fresh,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              creating
                  ? 'New — nothing is saved until you tap Save.'
                  : stub
                  ? 'Still a stub — left out of macro totals until confirmed.'
                  : 'Complete — counts in conversions and macro totals.',
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The doors that fill a row from a source, side by side. Each is a slot the
/// host fills or leaves empty; with all of them empty the block draws nothing.
class _FillItIn extends StatelessWidget {
  const _FillItIn({
    required this.scan,
    required this.usda,
    required this.label,
  });

  /// The barcode door, or null on a row with nothing empty to fill.
  final Widget? scan;

  /// The USDA door, or null where the provenance card already offers `Choose
  /// another ›`. A declined row keeps it.
  final Widget? usda;

  /// The label-photo door. Every row's: a panel can be read onto a row that
  /// already has its name, its aisle and everything but its figures.
  final Widget? label;

  @override
  Widget build(BuildContext context) {
    final doors = [
      if (scan != null) scan!,
      if (usda != null) usda!,
      if (label != null) label!,
    ];
    if (doors.isEmpty) return const SizedBox.shrink();
    // Two to a row: three of these labels across a phone would each be cut in
    // half. A lone door on the second row takes the width, as a lone door on
    // the first always has.
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text('FILL IT IN FROM', style: ansiLabel()),
          for (var i = 0; i < doors.length; i += 2)
            Row(
              spacing: 8,
              children: [
                for (final door in doors.skip(i).take(2)) Expanded(child: door),
              ],
            ),
        ],
      ),
    );
  }
}

/// The form's two commitments, `Save` and `Mark complete`, pinned under the
/// scroll on one row with [message] above them. A new row gets one button,
/// enabled only once the row would pass the completion gate
/// ([IngredientStatus.complete]).
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.creating,
    required this.stub,
    required this.canComplete,
    required this.message,
    required this.onSave,
    required this.onComplete,
  });

  /// A row that does not exist yet: one button, and [canComplete] gates it.
  final bool creating;

  final bool stub;

  /// The whole completion check: macros on a basis and nothing the form would
  /// refuse. Density is not required.
  final bool canComplete;

  /// The form's one feedback line.
  final String? message;

  final Future<void> Function()? onSave;
  final Future<void> Function() onComplete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Text(
              message!,
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ),
        if (creating)
          FButton(
            // Keyed, because two other small Saves sit earlier in the tree.
            key: kFormSaveKey,
            onPress: canComplete ? onSave : null,
            child: const Text('Save'),
          )
        else if (stub)
          Row(
            spacing: 8,
            children: [
              // Outline and narrow: on a stub, completing is the primary act.
              SizedBox(
                width: 92,
                child: FButton(
                  key: kFormSaveKey,
                  variant: FButtonVariant.outline,
                  onPress: onSave,
                  child: const Text('Save'),
                ),
              ),
              Expanded(
                child: FButton(
                  key: kFormCompleteKey,
                  onPress: canComplete ? onComplete : null,
                  child: const Text('Mark complete'),
                ),
              ),
            ],
          )
        else
          FButton(
            key: kFormSaveKey,
            onPress: onSave,
            child: const Text('Save'),
          ),
      ],
    ),
  );
}

/// Runs [change] after unfocusing, for an intent that rebuilds the fields it
/// came from; a focused field leaving the tree asserts.
void _leaveFields(VoidCallback change) {
  FocusManager.instance.primaryFocus?.unfocus();
  change();
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(text, style: ansiMono(size: 10, color: AnsiColors.muted)),
  );
}
