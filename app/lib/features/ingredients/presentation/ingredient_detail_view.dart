/// The ingredient page (`/ingredients/:id`, and `/ingredients/new` for a row
/// that does not exist yet) — the app's one door to reading, making or
/// fleshing out a vocabulary entry.
///
/// **One route, two postures**, the split the recipe page already has. A row
/// that exists opens as a **fact sheet**: the same groups in the same order,
/// each field's value stated in the words the field itself uses, with no
/// controls and no dock. `Edit` is an item in the header's `⋯`, exactly where
/// the recipe page keeps it. `/ingredients/new` opens editing — there is
/// nothing yet to read — and so does every door that exists to CHANGE a
/// field: the recipe page's macro-panel fix markers, the import review's
/// piece-weight door, and the manager's "needs fleshing out" band. The
/// sentences the reading posture states live in [macrosFact] and its
/// neighbours, so the two postures cannot drift into two accounts of one row.
///
/// **This file draws both.** Everything the editing posture intends and has
/// not written is the [IngredientForm] ViewModel's draft, and every tap
/// dispatches an intent — so what one Save sends can be asked without a widget
/// tree.
///
/// It is an **editor**, not a one-way queue: a `complete` row edits here too.
/// What it owns, in order — canonical name (its save rewrites the row's
/// `match_text` with it, which is nothing a person acts on and nothing this
/// screen says out loud), aliases, category + default unit, macros with their
/// basis, density (the shared [DensityEntry]), the piece weight on a
/// count-default row (the shared [PieceWeightEntry], ADR-0015), and the
/// explicit ADR-0008 `allowed_units` list.
///
/// Three rules the screen exists to enforce:
/// - **Nothing is written until Save** (ADR-0011). Everything the form intends
///   sits in a draft, so a form with no row behind it is coherent and backing
///   out of one leaves nothing to clean up.
/// - **Macros gate completion, density does not.** Confirming is a human act; a
///   USDA or barcode prefill fills fields and stops. On an EXISTING stub that
///   act is `Mark complete`; on `/ingredients/new` it is the only act there is
///   — one `Save`, live only once the row would pass the same gate, writing
///   the row `complete`. This form does not mint stubs; the seed's are the
///   ones there are, and they are meant to run out.
/// - **Delete is refused while a live recipe line points here**, with the
///   count — a line's ingredient is never allowed to dangle.
///
/// The form scans a barcode into itself, through the same [applyDraft] rule
/// every draft lands by: fields that are EMPTY fill, a value the human already
/// typed stays (and the card says which), provenance becomes `off:<barcode>`
/// unless the row already names its food, and nothing confirms the row.
///
/// The macros section holds four required figures and an optional fibre
/// ([Macros.fiber]), and has a **per serving** mode: the fields take a
/// label's figures as printed, a serving row says what they describe, and the
/// row still stores per 100 of the basis — derived unrounded
/// ([Macros.per100From]) and previewed live. The serving's "1 tbsp = 14 g" is
/// offered, opt-in, as this row's density (or a measure when it names a thing)
/// in the same save. A barcode draft lands on that mode whenever the label it
/// came from printed figures for one serving — whether that was the only
/// column the pack carried or the one it printed beside its per-100 one.
///
/// The form **names the food behind the numbers** at the head of that section,
/// read off the row's own `source_label` / `source_score` so it is true
/// offline. A USDA pick gets a card — the food's description and how much of
/// the typed name it answers, with two doors beside it: *Not this food* (the
/// prefilled density and macros come out and `source` becomes `usda_declined`)
/// and *Choose another ▸* (the next candidates, a pick landing in the draft
/// like any other edit). Neither confirms anything. A barcode scan gets the
/// name alone, on one line: there is no match to refuse or re-choose.
///
/// Neither says the id inside the stamp. An FDC number and a GTIN are keys into
/// databases the person holding the phone does not have; the card falls back to
/// the FDC id only on a row that carries no label at all, where it is the one
/// true thing left to say.
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
import '../../../shared/dashed_border_box.dart';
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/inline_amount_field.dart';
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
import '../domain/serving_measure.dart';
import '../domain/usda_probe.dart';
import 'density_entry.dart';
import 'draft_card.dart';
import 'ingredient_facts.dart';
import 'ingredient_view_models.dart';
import 'macro_line_text.dart';
import 'macros_doubt_line.dart';
import 'macros_format.dart';
import 'measure_delete.dart';
import 'measures_editor.dart';
import 'piece_weight_entry.dart';
import 'serving_row.dart';
import 'usda_pick_sheet.dart';

/// The pushed route for one vocab row.
///
/// [edit] opens it in the editing posture instead of the reading one. It is
/// for a door that exists to CHANGE a field — a recipe's macro-panel fix
/// marker, the import review's piece-weight door, the manager's stub band —
/// where landing on a fact sheet would make the person tap `⋯ ▸ Edit` to do
/// the thing the door already named. Every other door reads.
String ingredientDetailRoute(String id, {bool edit = false}) =>
    edit ? '/ingredients/$id?edit=1' : '/ingredients/$id';

/// The query parameter [ingredientDetailRoute] writes, read back by the
/// router. One name, one place, so a cold deep link and a push agree.
const kEditPostureQueryParam = 'edit';

/// The pushed route for a row that does not exist yet — the one door to making
/// an ingredient. [name] prefills the field, which is what a picker hands over
/// so the words already typed into its search become the row.
///
/// It pops with the created [Ingredient], or null if the person backed out —
/// so a caller that is waiting on the row (the editor's picker) gets it.
String newIngredientRoute({String name = ''}) => name.trim().isEmpty
    ? '/ingredients/new'
    : '/ingredients/new?name=${Uri.encodeQueryComponent(name.trim())}';

/// The form's own Save, in the pinned dock — as distinct from the small
/// Saves the density entry and the measures editor carry for their own
/// immediate writes. Exported so tests name it rather than counting FButtons.
const kFormSaveKey = ValueKey('form-save');

/// The dock's CTA: `Mark complete` on a stored stub. A complete row and a row
/// that does not exist yet each carry one button instead — Save.
const kFormCompleteKey = ValueKey('form-complete');

/// The manager this page is a row of — where back lands when there is
/// nothing under it. Spelled here rather than imported from the list view,
/// which imports this file.
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

  /// The row to edit, or **null to create one**.
  ///
  /// This form is the only door to making an ingredient. Under ADR-0011 it
  /// writes once, on Save, so a form with no row behind it is coherent —
  /// dismiss it and nothing exists — and `saveForm(null, …)` makes the row and
  /// its children in one transaction.
  final String? ingredientId;

  /// What the name field opens with on a create — the picker passes what was
  /// typed into its search, so "curry leaves" becomes the row without
  /// retyping it.
  final String name;

  /// Which posture the page OPENS in. The posture itself is page state from
  /// there on: `⋯ ▸ Edit` switches into editing, Save and back switch out of
  /// it, and neither navigates — one page, two faces.
  final bool edit;

  /// True when the sheet is drawn BESIDE the vocabulary rather than pushed over
  /// it — the manager's two panes on a window wide enough for both. The page
  /// that holds the panes draws the one back control above them, so the fact
  /// sheet's own header then carries the `⋯` alone. Nothing else about the
  /// sheet changes with it.
  final bool embedded;

  /// Forwarded to the form's barcode scan. Both exist for tests and are null
  /// in app code — the router builds this page with neither, and the scan
  /// then takes the real Open Food Facts client from its provider and the
  /// real camera preview.
  final OffLookup? lookup;
  final BarcodeCameraPane? cameraPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A row that does not exist has nothing to read, so the create form is
    // always the editing posture — and it is not a posture that can be left,
    // which is why it keeps the pop-with-the-row exit the picker awaits.
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

    // The form owns its own scaffold: the header's `⋯` menu and the pinned
    // action bar both act on form state (the pending edits, the busy flag,
    // the one message line), and a scaffold built above them could only
    // reach that state through callbacks threaded back up. The reading
    // posture owns its own for the same reason, one level simpler.
    //
    // Either is built only once the row is HERE, so the ViewModel seeds its
    // draft from a real row rather than from a blank it would have to
    // reconcile.
    if (async.asData?.value case final row?) {
      if (!editing.value) {
        return _ReadPosture(
          ingredient: row,
          embedded: embedded,
          onEdit: () => editing.value = true,
        );
      }
      // **Back means one thing.** Editing is a MODE of this page, not a page
      // of its own, so the system gesture has to leave the mode exactly as the
      // header chevron does — otherwise one act pops a route on Android and
      // steps back a posture in the header. The cost is the iOS edge swipe
      // while the form is open; it is whole again one tap away, on the fact
      // sheet, which is the page that swipe is really about.
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // The fields go with the form, and a field that still holds focus
          // when its render object leaves the tree goes on asking the
          // framework where its caret is.
          FocusManager.instance.primaryFocus?.unfocus();
          editing.value = false;
        },
        child: _DetailForm(
          // Keyed by id so pushing a different ingredient rebuilds the form
          // state instead of inheriting the previous row's typed values.
          key: ValueKey(ingredientId!),
          ingredientId: ingredientId,
          // Finishing here is not leaving the page: Save, Mark complete and
          // back all put the form down and show what the row now says.
          // Deleting still leaves — there is nothing left to read.
          onDone: () => editing.value = false,
          lookup: lookup,
          cameraPane: cameraPane,
        ),
      );
    }
    return FScaffold(
      childPad: false,
      header: _header(context, title: 'Ingredient'),
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

/// The page header, shared by the form and the states that have no row yet.
///
/// [suffixes] is where the board frame's `⋯` goes — drawn on the frame since
/// the section was locked, and built here for the first time: the actions
/// that are not part of filling the form in (delete, and un-confirming a
/// complete row) belong behind it rather than stacked under the CTA.
FHeader _header(
  BuildContext context, {
  String? title,
  VoidCallback? onBack,
  List<Widget> suffixes = const [],
  bool showBack = true,
}) {
  final back = FHeaderAction.back(
    // A cold deep link lands here with no page beneath, so there is nothing
    // to pop: fall back to the manager, exactly as the delete does. A row is
    // a detail OF the vocabulary, which is why its home is the manager and
    // not the Library.
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
    prefixes: [back],
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

/// The page as it OPENS on a row that exists: the same groups in the same
/// order, each field's value stated instead of offered.
///
/// **It states nothing the form does not.** Every line comes from the shared
/// sentences ([macrosFact] and its neighbours), which restate stored facts in
/// the words the form's own fields and entries use — so the two postures
/// cannot tell two stories about one row, and there is no second place to fix
/// when a wording changes. Nothing is added either: no "used in" list, no
/// derived figure the form does not already compute.
///
/// **One button, and only on an incomplete row.** A complete row is finished:
/// reading it is the whole act, and `⋯ ▸ Edit` is where changing it lives. A
/// stub keeps the door it has always had — the strip says it is left out of
/// totals, and `Fill it in` opens the editing posture at the fields that
/// would end that.
class _ReadPosture extends ConsumerWidget {
  const _ReadPosture({
    required this.ingredient,
    required this.onEdit,
    this.embedded = false,
  });

  final Ingredient ingredient;
  final VoidCallback onEdit;

  /// Drawn beside the vocabulary rather than pushed over it — see
  /// [IngredientDetailView.embedded]. The page above the panes owns the back.
  ///

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ing = ingredient;
    final stub = ing.status == IngredientStatus.stub;
    // Decorative emptiness, weighed: an alias that did not load costs the
    // reader a line they were not looking for, and the row's own name — the
    // thing they came for — is right above it.
    final aliases =
        ref.watch(ingredientAliasesProvider(ing.id)).asData?.value ??
        const <IngredientAlias>[];
    final alsoKnownAs = aliasesFact(aliases);
    final measuresAsync = ref.watch(ingredientMeasuresProvider(ing.id));
    final source = sourceProvenanceLine(ing);
    final pieceWeight = pieceWeightFact(ing);
    // The row's own serving, when it states one: it is what lets the macro
    // line print the label's own figures instead of a per-100 reading nobody
    // holding the jar can check.
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
            style: ansiSerif(size: 33, weight: FontWeight.w700),
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
              // Which food the numbers came from, over the numbers — the one
              // line the manager list and the import review already print, so
              // a row names its food the same way wherever it is met.
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
              // Never zeros: a row with no panel says what it is short of, in
              // the dock's own words (invariant 3). A row that HAS one is a
              // dense line and draws its energy as a glyph, the way the
              // picker row it restates does.
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
              // The piece weight is drawn only where it means something — a
              // count row that states one — exactly as the form draws its
              // entry only under a count default.
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
              // Load-bearing emptiness: an errored stream rendered as "none"
              // would say this row carries no measures, which is a different
              // thing from not knowing.
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
        ],
      ),
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

/// One stated fact under its micro-label — the reading posture's counterpart
/// to a field, and the same mono the field's own text is set in.
///
/// [muted] is for an honest absence ("needs macros", "none yet — unlocks
/// volume⇄weight"): the sentence is still there, drawn as the aside it is
/// rather than as a value the row carries.
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

  /// Null while creating. The form's own state lives in [IngredientForm],
  /// keyed by this — so the draft and the rules that shape it are testable
  /// without a widget tree, and this file only draws.
  final String? ingredientId;

  final String initialName;

  /// Where the form goes when it is put down — back to the reading posture on
  /// a row that exists. **Null while creating**, and that is the whole
  /// difference: a create form has no fact sheet behind it, so it ends the
  /// page and pops with the row it made, which is what the picker that pushed
  /// it awaits.
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
    // The row as the form reads WHERE ITS NUMBERS CAME FROM — the pick or
    // scan in the draft, or the stored stamp. Every door and card in this
    // build reads it, so a pick is on the card the moment it is made instead
    // of only after a Save.
    final sourcedRow = draft.sourcedRow;
    final stub = draft.stub;
    final busy = draft.busy;
    // A row that does not exist has no stored children to watch — and asking
    // for them under a blank id would be a query about nothing.
    final measuresAsync = creating
        ? const AsyncValue<List<Measure>>.data([])
        : ref.watch(ingredientMeasuresProvider(ing.id));

    // The barcode door. The scanner needs a context, so the sheet opens here
    // and what it returns is handed straight back as an intent — the rule for
    // what a draft may land on is the ViewModel's, against the form's OWN
    // draft, because a panel typed and not yet saved is as much the human's as
    // a saved one.
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

    // **The USDA search — one door, two entry points.**
    //
    // `Fill it in from ▸ Look up in USDA` and the provenance card's
    // `Choose another ›` are the same act: ask USDA about this row and let a
    // human pick. It asks about **the name in the field**, not the stored row,
    // so the lookup never has to save the form first to avoid probing a stale
    // name. And a pick writes nothing — it fills the draft, and the form's own
    // Save lands the lot, which is also what lets it work on a row that does
    // not exist yet.
    Future<void> pickUsda() async {
      final pick = await showUsdaPickSheet(
        context,
        // The DRAFT's provenance: the short-list marks the row's own match
        // *current* and its refused food *declined*, and a pick made a moment
        // ago is as much this row's match as one that has been saved.
        ingredient: draft.sourcedRow,
        name: draft.name.trim().isEmpty ? ing.canonicalName : draft.name,
      );
      if (pick == null) return;
      form.applyUsdaPick(pick);
    }

    // Putting the form down. On a row that exists that means the reading
    // posture — the page stays, and shows what the row now says.
    //
    // Creating has no such posture, so it LEAVES: a cold deep link lands here
    // with no page beneath, so there is nothing to pop and it falls back to
    // the manager, exactly as the delete does. It pops with the row, so a
    // caller waiting on this form — the editor's picker, which pushes it and
    // then opens the quantity sheet on the units it just set — gets what it
    // was waiting for.
    void leave([Ingredient? result]) {
      final done = onDone;
      if (done != null) {
        // The fields go with the form, and a field that still holds focus
        // when its render object leaves the tree keeps asking the framework
        // where its caret is. Put the keyboard down first, exactly as a route
        // transition would.
        FocusManager.instance.primaryFocus?.unfocus();
        done();
        return;
      }
      ansiBack(context, home: _managerRoute, result: result);
    }

    // **A near match, taken.** Only the create form offers this: there the
    // words in the field are a name nobody has committed to, and the picker
    // that pushed this form is waiting for a row either way — so handing back
    // the one that already exists is the whole point. It asks first; swapping
    // what somebody typed for another row unasked is not the form's call.
    //
    // On a row that already exists the near names are shown and nothing more.
    // Renaming this row onto that one would be a merge, and merging two rows
    // is a different feature with a different question to answer (what happens
    // to the lines pointing at each).
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

    // Completing is the page's terminal act, so it ENDS the page: the
    // ingredient picker pushes this form and *awaits its pop* before opening
    // the quantity sheet on the units the form just set, so finishing a row
    // from a recipe line must not leave the person on a screen that has told
    // them it counts and given them nothing to do.
    // Save and mark go in ONE transaction: split across two writes, a failure
    // between them leaves the row saved and not marked, under an error
    // implying neither happened.
    Future<void> completeRow() async {
      final saved = await save(markComplete: true);
      if (saved == null || !context.mounted) return;
      leave(saved);
    }

    Future<void> unconfirmRow() =>
        ref.writeOk(context, 'unconfirm ${ing.canonicalName}', form.unconfirm);

    // The refusal is the interesting state: it names the count, because "used
    // by 3 recipes" is a thing a user can act on and "failed" is not. It lands
    // in the message line above the action bar, which is on screen whatever
    // the scroll position.
    Future<void> deleteRow() async {
      final outcome = await ref.write(
        context,
        'delete ${ing.canonicalName}',
        form.delete,
      );
      if (outcome is! Deleted || !context.mounted) return;
      ansiBack(context, home: _managerRoute);
    }

    // What the row's measures ARE, as the form holds them: the loaded ones
    // minus what it intends to remove, plus what it intends to add. A pending
    // one is indistinguishable from a stored one on screen, and carries the
    // id it will keep.
    final loadedMeasures = measuresAsync.asData?.value;
    final measures = [
      for (final m in loadedMeasures ?? const <Measure>[])
        if (!draft.measuresRemoved.contains(m.id)) m,
      ...draft.measuresAdded,
    ];

    return FScaffold(
      childPad: false,
      header: _header(
        context,
        title: ing.canonicalName,
        // Back out of editing is back to the fact sheet, not off the page:
        // the form discards what it holds exactly as it always has (nothing
        // is written until Save, ADR-0011), and what is left is the row.
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
      // Pinned, so the two commitments this page can make are reachable from
      // any scroll position — and so the destructive action is no longer one
      // flick below the confirm CTA.
      footer: _ActionBar(
        creating: creating,
        stub: stub,
        canComplete: !busy && draft.completable,
        // The line the CTA's promise moved into: what a save said, what a
        // delete refused, or — while the CTA is disabled — what it is waiting
        // for. A new row is waiting on the same things a stub's `Mark
        // complete` waits on, so it borrows the same words.
        message:
            draft.message ??
            (creating
                ? draft.refusal ??
                      (draft.storedMacros == null
                          ? 'needs macros'
                          : 'saving it counts it in conversions and macro '
                                'totals')
                : stub
                ? (draft.storedMacros == null
                      ? 'needs macros'
                      : 'completing it counts it in conversions and macro '
                            'totals')
                : null),
        // Only the button leaves: three other callers use the save as a FLUSH
        // and none of those may navigate.
        //
        // On a new row Save IS the completion (C-B): there is no stub to come
        // back to, so it writes `complete` and the dock only offers it once
        // the row would pass that gate.
        // A taken name is refused by the write, so the button stops offering
        // it — on every posture, not only the create form's completion gate.
        onSave: busy || draft.nameCollision != null
            ? null
            : creating
            ? completeRow
            : () async {
                final saved = await save();
                if (saved != null && context.mounted) leave(saved);
              },
        onComplete: completeRow,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          // SLOTS, not conditional children — the rule this file has always
          // kept, now applied one level up: each GROUP is a fixed position,
          // and a section that turns on turns on inside its group. An unkeyed
          // insertion in a ListView shifts every sibling by one, which
          // reconciles each of them against the wrong element and silently
          // resets its state.
          _StatusStrip(ingredient: ing, creating: creating),

          // The two prefill doors, in one place — each drawn where it has
          // something to offer, and the block itself gone when neither does.
          //
          // The **scan** is a stub's door: a draft fills what is EMPTY, and
          // nothing on a complete row is. The **lookup** is every row's, and
          // closes only where the card below already carries `Choose another
          // ›` for the food that filled it. That is the state a barcode row
          // stamped after a decline fell through: complete, so no block at
          // all, and not `usda_fdc:`, so no card either — USDA cleared, with
          // no way back to it.
          _FillItIn(
            // Not in a browser: the scan needs a camera and a detector the tab
            // has not got, and a door that opens on "no camera is available
            // here" is a door that should not have been drawn. The typed
            // barcode field on the sheet is the path that always works — but
            // it is reached through this door, so on the web the whole row is
            // simply the form, filled by hand.
            scan: stub && !kIsWeb
                ? _GhostButton(
                    label: 'Scan a barcode',
                    onTap: busy ? null : scan,
                  )
                : null,
            usda: isUsdaPrefilled(sourcedRow.source)
                ? null
                : _GhostButton(
                    label: 'Look up in USDA',
                    onTap: busy ? null : pickUsda,
                  ),
          ),

          if (draft.scanned != null && draft.scanApplied != null)
            _ScanResult(
              draft: draft.scanned!,
              applied: draft.scanApplied!,
              packAdded: draft.packAdded,
              // The pack size is an OFFER: a measure lands only because it was
              // tapped — and it lands in the draft, so it rides the form's one
              // Save like every other measure. That is also what lets a
              // barcode-created row carry its pack size before the row exists.
              onAddPack: () async =>
                  form.addPackMeasure(sortOrder: measures.length),
            )
          else
            const SizedBox.shrink(),

          // The board's field order is kept exactly (name · aliases ·
          // category + default unit · macros · density); what changes is that
          // it is now three named groups instead of twelve equal shouts.
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
              // The namespace's two answers, in the field's own note voice and
              // never both at once: this name is taken, or it was nearly
              // somebody else's.
              if (draft.nameCollision case final taken?)
                _AlreadyAnIngredient(taken)
              else if (draft.nameNearMatches.isNotEmpty)
                _DidYouMean(
                  matches: draft.nameNearMatches,
                  // On a row that already exists this is information, not an
                  // offer: renaming Sauerkroutt to something near Sauerkraut
                  // is a decision only the person can make, and merging two
                  // rows is not a thing this form does.
                  onUse: creating ? useInstead : null,
                ),

              const _Label('ALSO KNOWN AS'),
              _AliasEditor(
                aliases: [
                  // Decorative emptiness, weighed: the add field is the point
                  // of this section and works with no list at all, and an
                  // alias that exists but did not load is re-added harmlessly
                  // — `saveForm` is find-or-create on match_text.
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
              _CategoryPicker(
                selected: draft.category,
                onPick: form.setCategory,
              ),
            ],
          ),

          _Group(
            title: 'Nutrition',
            children: [
              // Where the numbers came from, at the head of the section that
              // holds them. A slot again (it renders nothing on a row USDA
              // never touched), and it reads the DRAFT's provenance so a pick
              // made a moment ago is named by the card that explains it.
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

              const _Label(
                'MACROS',
                hint: 'as the label reads · fibre optional',
              ),
              // One segment, in the section it changes. Per 100 of the basis is
              // the default; per serving reveals the row below and reads the
              // same four fields as the label prints them.
              //
              // **Every leg puts the keyboard down first.** A mode change
              // re-seeds the four fields around fresh controllers — that is
              // what clearing and restoring them means — and a field that
              // still holds focus when its render object leaves the tree goes
              // on asking the framework where its caret is. Leaving the field
              // is what tapping one of these IS.
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
              // Three slots: the serving row, the stored line and the offer
              // hold their positions whether or not the mode is on, so
              // toggling it cannot shift the fields below onto the wrong
              // element. The serving unit sets the BASIS — a 14 g serving
              // reads per 100 g — so the admission chips follow it live.
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
              // The key is the row-version: it changes only when the row's own
              // macros were re-seeded into the draft, and that is exactly when
              // the four controllers need rebuilding around their new text.
              _MacroFields(
                key: ValueKey('macro-fields-${draft.macroSeed}'),
                draft: draft.macros,
                onChanged: form.setMacros,
              ),
              // The derivation, in the person's sight before Save — one muted
              // line, never in the fields' place. On a scanned row the
              // comparison sits under it: what the pack printed per serving
              // against what its own per-100 column says, whichever of the two
              // the fields happen to hold. On a scan that named no serving at
              // all there is no comparison to draw, and the slot carries the
              // one nudge that per-serving mode is there.
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
              // Once, under all of it, whatever mode the section is in: the
              // doubt is about what will be STORED, and a panel that argues
              // with itself does so in every mode.
              MacrosDoubtLine(stored: draft.storedMacros),
            ],
          ),

          // Density, the piece weight, admission, the default unit and the
          // measures are ONE subject — what a line of a recipe may say about
          // this row, and how much of it that is. The default unit sits here
          // rather than beside the category because its repair does: a default
          // the row cannot convert is flagged on the line under its own chips
          // and fixed by a number in this same section, rather than two groups
          // away.
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
              // A stored default the rules no longer support — a cup default
              // on a per-100 g row with no density. Flagged with its repair
              // rather than rewritten: how a household buys a thing is not
              // ours to edit.
              _StrandedDefaultNote(
                ingredient: draftRow,
                onFix: () => ref.write<Ingredient?>(
                  context,
                  'save ${ing.canonicalName}',
                  form.fixStrandedDefault,
                ),
              ),

              // The piece weight (ADR-0015) — drawn only where it means
              // something: a count default. It sits directly under the chip
              // that made it appear, before the admission chips it unlocks,
              // so the stranded flag above and its repair read as one line.
              // Nothing is written here: the number goes in the draft and the
              // form's Save lands it, exactly as the density below does.
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
                // `draftRow`, not the stored row: the headline shows the
                // density the form is HOLDING, and "Remove it? tsp · tbsp …
                // lock again" names the units the draft would strip. Reading
                // the row here would show a number the person has already
                // replaced, or none where they have just typed one.
                ingredient: draftRow,
                // The row's own serving, so the sentence reopens in the unit
                // the fact sheet states this density in.
                serving: servingMeasureOf(measures),
                redirectedSpoon: draft.redirectedSpoon,
                // The one place a density is stated (the serving row does
                // none), and the serving above is offered as its left-hand
                // side so the pack's "2 tbsp (32 g)" is typed as it reads.
                servingPrefill: draft.densityPrefill,
                // Nothing is written here: the density goes in the draft and
                // the form's Save lands it. The chips follow it because
                // `draftRow` carries the draft density and the admission rule
                // is applied with it.
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
              // Load-bearing emptiness: an errored measures stream rendered as
              // `const []` hides rows that exist, and this form's next Save
              // would then write the narrowed set back. So the error is a
              // state, not a fact about the ingredient.
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
                MeasuresEditor(
                  ingredient: ing,
                  measures: measures,
                  // It adds to the draft here; the docked Save lands it.
                  addLabel: 'Add',
                  // A stored measure a recipe still uses cannot go, and the
                  // refusal happens HERE rather than at Save: a draft that
                  // quietly kept a row it said it had removed would be lying
                  // about what the docked Save is going to do.
                  onDelete: (m) async {
                    if (!await mayDeleteMeasure(context, ref, m)) return;
                    form.removeMeasure(m.id);
                  },
                  // Nothing is written here: the measure goes in the draft and
                  // the form's Save inserts it. The editor has already refused
                  // a blank label, a volume-named one and a non-positive
                  // amount — the same three the repository refuses — so there
                  // is nothing left to be refused by.
                  onAdd: (label, amount) async => MeasureAdded(
                    form.draftMeasure(
                      label,
                      amount,
                      sortOrder: measures.length,
                    ),
                  ),
                  // A measure the draft holds is re-stated in the draft. A
                  // STORED one is a live row — lines already point at it — so
                  // its correction is a write of its own, under the guard,
                  // rather than something the form's Save could still undo.
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
                          // The repository's validation contract IS
                          // ArgumentError (documented on renameMeasure), so
                          // catching it is the point.
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
                  // Both halves of the list land on the one order: the drafted
                  // rows carry their new position to Save, and the stored ones
                  // are re-stamped now — they are live rows, and the chip row
                  // and the shop's hint read the first of them.
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
                  // Nothing here selects a measure — the form is not a
                  // quantity entry surface; the watched provider re-renders
                  // the list.
                  onAdded: (_) {},
                  // A volume-named label is a density in disguise (ADR-0008
                  // §2); the editor refuses it and the density section above
                  // pre-picks that spoon, which is the whole point of sharing
                  // one widget.
                  onVolumeLabel: form.redirectSpoon,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Sections ----------------------------------------------------------------

/// The USDA provenance card: which food filled this row, how well it fits the
/// name, and the two doors.
///
/// **It names the food, never its number.** A person recognises "Curry leaves,
/// raw"; `FDC 11216` is a key into a database they are not holding, and a card
/// that leads with it asks them to be a lookup table. The id appears in exactly
/// one place — a row whose `source_label` is empty, filled before the label was
/// written down — because there is then nothing else true to say about which
/// food this was.
///
/// Read off the `source_label` / `source_score` the FORM holds — the pick in
/// the draft, or the row's own stamp where the draft holds none — and never
/// off a live probe: the form is offline-first, and after a rename a fresh
/// probe would name a different food than the one that actually filled the
/// row. Nothing here confirms: the header says *not confirmed* until a human
/// taps Confirm below.
///
/// Four states, one widget, because they are the same fact at four moments:
/// - **pending** ([pending]): a pick that is in the fields and not yet in the
///   row — the food's name and *not saved*, with both doors, because refusing
///   it and re-choosing are exactly as available before a Save as after one;
/// - **prefilled** (`usda_fdc:<id>`): the food's name, how much of the typed
///   name it answers, and both doors;
/// - **edited** (`source_edited`, migration 0034): the same food, still named
///   — plus one line saying WHAT was overridden (your macros / your density /
///   both). It is **provenance, not a warning**: muted, never amber. Amber is
///   spent on an unconfirmed machine fill, where there is something to do; here
///   there is nothing to fix, only something to know;
/// - **declined** (`usda_declined`, after *Not this food*): the refused
///   name, what the undo did, and *Choose another* alone — plus the one
///   sentence a person needs to hear once, that a rename will not refill it.
///   The plain `Look up in USDA` door is drawn above it too: the card is a
///   record of what was refused, and a refusal is not a dead end.
class _UsdaProvenance extends StatelessWidget {
  const _UsdaProvenance({
    required this.ingredient,
    required this.pending,
    required this.onDecline,
    required this.onChooseAnother,
  });

  /// The row as the form reads its provenance — the draft's pick folded in
  /// (`IngredientFormDraft.sourcedRow`), so this card names the food whose
  /// numbers are in the fields.
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
      // B-D2: *edited here* replaces the confirm word, because it is the more
      // interesting fact about the row — a confirmed row whose numbers you
      // typed is not "confirmed from USDA" in any sense a reader would mean.
      header = edited
          ? 'Filled from USDA · edited here'
          : 'Filled from USDA · ${stub ? 'not confirmed' : 'confirmed'}';
      line = [food, ?fit].join(' · ');
    }
    // Amber is a call to action, so it is spent only where there is one: an
    // unconfirmed machine fill, or a pick waiting on the Save that would make
    // it the row's. A CONFIRMED row's card is provenance — a statement of
    // where the numbers came from — and it drew a ⚠ over the word
    // "confirmed", which reads as an error about a row that is fine.
    //
    // An EDITED row is the same argument (B-D2): you typed those numbers on
    // purpose, and nothing is wrong with the row. It stays muted even while it
    // is still a stub, because the thing amber would be asking for — look at
    // these machine numbers — is exactly what already happened.
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
                    // A pick in the fields and not in the row: the card is
                    // about what a Save would write, so it wears the dock's
                    // own verb rather than a warning.
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

/// What a barcode scan filled this row from, in one line and nothing more.
///
/// A stored `off:<barcode>` row is otherwise mute about its own provenance: the
/// scan's result card belongs to the scan, and reopening the form a week later
/// showed no trace of which pack the numbers came off. The code itself is not
/// an answer — it is a key, and the person who scanned it cannot read it back.
/// So the pack gets **named**, from the row's own `source_label`.
///
/// A line, not a card: the USDA doors have no counterpart here. There is no
/// short-list to choose again from, and *Not this food* undoes a match — a
/// barcode is not a match, it is the thing itself. What is left is the one fact
/// worth carrying, and `edited ·` leads it on a row whose numbers a human has
/// since overridden, exactly as it leads the list's line.
///
/// **No label, no line.** A row stamped before the label was written says
/// nothing rather than printing its barcode at somebody.
class _BarcodeProvenance extends StatelessWidget {
  const _BarcodeProvenance({required this.ingredient, required this.basis});

  /// The row as the form reads its provenance — the scan's stamp is on the
  /// form before it is on the row, and this line is about the panel in the
  /// fields (`IngredientFormDraft.sourcedRow`).
  final Ingredient ingredient;

  /// **The head names the basis**, so nobody has to work out which 100 the
  /// four figures are per — the whole trap the mapper exists to avoid, said
  /// out loud on the row it landed on. It is the DRAFT's basis: flipping the
  /// chip moves it.
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

/// Which numbers the *edited here* line names — "your macros", "your density",
/// or "your macros and your density" (B-D2).
///
/// **Read off what the row now carries, not off which field was typed.** The
/// flag is one boolean by ruling (B-D1: encoding it in `source` breaks every
/// parser, and diffing means keeping a second copy of the source's own
/// figures), so the row records that its numbers were overridden and not which
/// of them. Naming what is on the row is the reading that ruling supports: the
/// claim is made at row granularity, which is the granularity the fact has.
///
/// A row carrying neither — the flag survived a later clear of both — says the
/// plain thing rather than an empty list.
String _overriddenNumbers(Ingredient ingredient) {
  final macros = ingredient.macros != null;
  final density = ingredient.densityGPerMl != null;
  if (macros && density) return 'your macros and your density';
  if (macros) return 'your macros';
  if (density) return 'your density';
  return 'edited here';
}

/// The macro inputs, as one **sentence**: `[285.7] kcal · [0] protein ·
/// [21.4] carb · [21.4] fat · [ ] fibre`.
///
/// They were five tall boxes with a caption under each, which is a form's
/// height for a line a person reads off a label in one breath. The slots are
/// the density sentence's own [InlineAmountField] — stripped chrome, a width
/// that fits the widest plausible reading — with the name after the number the
/// way a panel prints it, so the five sit on one or two runs instead of five.
///
/// The first four are all-or-none — a partial panel would compute totals out
/// of numbers nobody supplied (invariant 3). **Fibre is optional**
/// ([Macros.fiber]): a label that prints it fills the fifth slot, one that
/// does not leaves it blank and the row is complete regardless.
class _MacroFields extends StatelessWidget {
  const _MacroFields({required this.draft, required this.onChanged, super.key});

  /// Seeds the controllers when this widget is (re)built under a new key —
  /// so it is the DRAFT, not the row: the form re-keys exactly when it has put
  /// something new in the draft, whether that came from the row (G1) or from a
  /// barcode scan.
  final MacroDraft draft;
  final ValueChanged<MacroDraft> onChanged;

  /// Wide enough for a kcal reading of four digits and a decimal (`1234.5`,
  /// `285.7`); the gram slots take three and a decimal (`21.4`, `100`), which
  /// is the density sentence's own slot width. A slot sized for a number
  /// somebody types into it rather than for one they leave alone — a field
  /// scrolls, and a run lost to a width nobody fills is a run lost.
  static const _kcalWidth = 60.0;
  static const _gramsWidth = 46.0;

  @override
  Widget build(BuildContext context) {
    Widget slot(
      String label,
      String seed,
      MacroDraft Function(String) put, {
      required bool last,
    }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineAmountField(
          // Keyed: they read alike, and a test that targets them by
          // position breaks the moment a slot moves.
          fieldKey: ValueKey('macro-$label'),
          width: label == 'kcal' ? _kcalWidth : _gramsWidth,
          // Seeded through the display rule, and only seeded: the draft goes
          // on holding the full figure, so a field nobody touches saves what
          // it was given rather than what it was showing.
          initial: macroFieldText(seed, energy: label == 'kcal'),
          onChange: (t) => onChanged(put(t)),
          onSubmit: () {},
        ),
        const SizedBox(width: 4),
        Text(label, style: ansiMono(size: 9, color: AnsiColors.muted)),
        // The separator travels with the slot it follows, so a run that breaks
        // can never leave a number on one line and its name on the next.
        if (!last) ...[
          const SizedBox(width: 5),
          Text('·', style: ansiMono(size: 10, color: AnsiColors.muted)),
        ],
      ],
    );

    // One Wrap, exactly as the density sentence is: the five read as a list and
    // fold onto a second run at 402 pt rather than shrinking to fit.
    return Wrap(
      key: const ValueKey('macro-sentence'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 5,
      runSpacing: 6,
      children: [
        slot('kcal', draft.kcal, (t) => draft.copyWith(kcal: t), last: false),
        slot(
          'protein',
          draft.protein,
          (t) => draft.copyWith(protein: t),
          last: false,
        ),
        slot('carb', draft.carb, (t) => draft.copyWith(carb: t), last: false),
        slot('fat', draft.fat, (t) => draft.copyWith(fat: t), last: false),
        slot('fibre', draft.fiber, (t) => draft.copyWith(fiber: t), last: true),
      ],
    );
  }
}

/// `＋ add “pack” = 400 g as a measure` — the offer's own words. The amount is
/// in the row's basis, so it reads the way a scale reads.
String _packOfferLabel(PackMeasureOffer pack) {
  final basis = pack.basis.baseUnit;
  return '＋ add “pack” = ${formatQuantityIn(pack.amountInBasis, basis)} '
      '${basis.label} as a measure';
}

/// What the form's own scan landed: the shared result card, naming what it left
/// alone, then what it did NOT do — nothing here saves or confirms — and the
/// pack-size offer as a one-tap measure.
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
          // The pack size is an OFFER (F2's ruling, kept on the form): a
          // measure lands only because it was tapped.
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

/// The admission section: the units this row says today, the ones it could
/// say, and — after a divider — the imprecise words.
///
/// **The locked units are a line, not chips**: "cup · tbsp · ml unlock when
/// this row has a density." *"Why can't I pick cup"* must have a visible
/// answer, and a named line answers it more completely than a row of dashed
/// pills, because it also says what to do about it. Nothing else locks: every
/// other chip is the household's to turn on or off.
///
/// **The imprecise words are folded in**, behind a divider because they are
/// words rather than measures — the same idiom the quantity sheet uses. The
/// category decides which of them arrive pre-picked; the row decides what it
/// keeps.
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
        // The one chip that is not the household's to turn off, named for
        // the same reason the locked ones are: a tap that does nothing needs
        // a visible answer.
        if (candidates.any((c) => !c.locked && c.unit == fixed))
          _Note('${fixed.label} stays on — the row is bought in it'),
        // The density note is printed ONCE, under the default-unit row above:
        // the same family is dashed here for the same reason, and saying it
        // twice on one screen is what the owner asked to have removed.
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

  /// The row's own default unit: drawn ON like any other sayable chip — it is
  /// on, and stays on — but inert, because a row has to be able to say the
  /// word it is bought in. The note under the chips is where that is said.
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

/// The category field: a dropdown of the household's own categories, plus one
/// door to coin a new one.
///
/// Free text is gone. A typed category is only useful if it is the *same*
/// string every other row uses — the imprecise-unit gate reads it by exact
/// match ([kImpreciseCategoryGates]), and so does the list's grouping — and
/// free text guarantees "Produce", "produce" and "produce " will coexist.
/// The options come from the vocabulary itself, so there is no second place
/// that has an opinion about which categories exist.
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
    // Decorative emptiness, weighed (D6): these are typing SUGGESTIONS, and
    // the row's own category is added below regardless — so "we don't know the
    // others" and "there are no others" cost the user the same nothing.
    final known = ref.watch(ingredientCategoriesProvider).asData?.value ?? [];
    // The row's own category is always offered even when nothing else carries
    // it any more — the same rule the unit pickers follow for a stored
    // selection: an existing value must never render as an orphan.
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

/// The single-select default-unit row.
///
/// **Only the units this row can be counted in are drawn**
/// ([defaultUnitOfferFor]): with no density the other mass/volume family is not
/// sayable as a default, so it is named in one line under the row instead of
/// being offered and then refused at Save. Every chip that IS drawn can be
/// pressed — a row full of live pills and one advisory sentence beats a row of
/// dead pills the person learns about only by tapping them.
///
/// The note speaks in the admission section's voice, because it is the same
/// promise about the same number: *tsp · tbsp · … unlock when this row has a
/// density*.
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
    // Wrapped, not a horizontal scroller. The catalog is wider than a phone,
    // and the scroller clipped the last chip mid-glyph with nothing to say it
    // continued.
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
                // A stranded default is still THE selection — that is the
                // truth about the row — but not a healthy one: `stranded`
                // repaints it in the "gone" colour, which is what the line
                // under this row is about. Selection and health are two
                // facts, not one.
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

/// The row whose default unit its own rules cannot convert: `cup` on a
/// per-100 g row with no density, or `piece` on a row with no piece weight.
/// Never rewritten silently; named, with the one tap that repairs it.
///
/// **A default goes stranded behind the chip row's back**, which is why this
/// line exists at all: `piece` is pickable before the row says what one
/// weighs (it is picking it that opens the weight field), a basis flipped to
/// per 100 ml strands the `g` the chips did offer, and a density deleted
/// strands the `cup` it once bought. Each lands here, on one line naming the
/// missing number, with the chip above in [AnsiColors.gone] to say which unit
/// it is about. Hiding it until the number arrives would hide a broken row
/// from the only person who can fix it, and they would have no reason to add
/// the number because nobody told them anything was wrong.
///
/// It is not the "these units would unlock" advisory the chip rows carry: that
/// one is about words the row *could* say, this one about the word it is
/// *already using*.
///
/// **Save refuses while this line is showing.** The line names the state and
/// offers one of the two fixes; the form's own refusal names both and blocks
/// the write, because advice a Save can walk past is not a rule.
class _StrandedDefaultNote extends StatelessWidget {
  const _StrandedDefaultNote({required this.ingredient, required this.onFix});

  final Ingredient ingredient;
  final Future<void> Function() onFix;

  @override
  Widget build(BuildContext context) {
    if (!defaultUnitStranded(ingredient)) return const SizedBox.shrink();
    final fix = basisDefaultUnitFix(ingredient);
    // Two strandings, one line (ADR-0015): a `cup` default with no density,
    // or a `piece` default with no piece weight — each names the number that
    // would repair it, which is entered directly below.
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

/// The canonical-name field, and the moment its name is tidied.
///
/// Leaving the field is when the tidy runs: a stray space or a missing capital
/// goes silently, and a WORD that changed says so in the `was “…”` line the
/// host draws underneath. The form's Save is the backstop for a field that was
/// typed in and never left.
///
/// **The draft owns the text, and the controller follows it.** [seed] moves
/// whenever something other than typing changed the name — a barcode scan, or
/// a tidy — and this pushes the new text into the controller it already has.
/// The alternative, re-keying the field so a fresh controller seeds from
/// `initial`, replaces a focused text field: a Save tapped straight from the
/// keyboard then tears the field's render object out from under the gesture
/// that tapped it.
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

/// "Also known as" — the alias chips, addable and removable.
///
/// **Presentational.** The host hands it the list it should draw — the stored
/// aliases minus what the form intends to remove, plus what it intends to add —
/// and takes the two intents back. Nothing here writes.
///
/// The one rule that stays inside is the refusal: an alias whose normalized
/// match text is empty carries no identity word, and would match everything
/// and nothing. It is checked here rather than caught, because the repository
/// throws `ArgumentError` for it and that is a programming error to a linter,
/// not a sentence for a person.
class _AliasEditor extends HookWidget {
  const _AliasEditor({
    required this.aliases,
    required this.onAdd,
    required this.onRemove,
  });

  final List<IngredientAlias> aliases;

  /// Takes the alias into the draft and answers null, or hands back the entry
  /// it would have landed on top of — an alias is a name, and the namespace
  /// refuses a second one exactly as it refuses a second canonical name.
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
      // The field is about to leave the tree, so the keyboard goes with it —
      // and the next `＋ alias` opens on an empty one rather than on the text
      // that was just turned into a chip.
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

// `Fill it in from ▸ Look up in USDA` opens the same candidate search that
// `Choose another ›` opens: a person picks, so there is no automatic guess to
// narrate and no status sentence to keep from going stale. The search asks
// about the name in the FIELD rather than the stored one, so nothing has to be
// written before you may look something up.

// --- Small shared pieces -----------------------------------------------------

/// `Already an ingredient: Sauerkraut` — the name namespace's refusal, under
/// the field it is about.
///
/// The existing name is a **door onto that row**, which is the idiom the
/// recipe page already keeps for an ingredient's name: "what is this" is one
/// tap from the line that raised the question, and here the question is "then
/// which one is the Sauerkraut I already have?".
///
/// The wording is [nameTakenMessage]'s, so the note under the field and the
/// refusal the write returns are one sentence rather than two that drift.
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

/// `DID YOU MEAN` under the name field — the pickers' band, over the same
/// guarded typo tier, asked of the names this household already has.
///
/// [onUse] is the create form's offer: tapping a row asks whether to use that
/// ingredient instead, and the form pops with it. Null on a row that already
/// exists, where these are names to read and decide about — renaming onto one
/// of them would be a merge, and this form does not merge rows.
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
                    // Which spelling it was found under, when that was not the
                    // row's own name — otherwise the row looks like it does
                    // not resemble what was typed.
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

/// The board's `ghostbtn`: a secondary action that reads as available
/// without competing with the screen's primary CTA.
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;

  /// Null while the action is in flight or unavailable — the button greys
  /// rather than accepting a tap it will drop (F1: "save first" is a state,
  /// not a silent no-op).
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

/// A field's micro-label in this form's own rhythm: the shared
/// [AnsiMicroLabel], with the breathing room that separates one field of a
/// long scroll from the last one.
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

/// One named group of the form: a serif heading and a hairline over a run of
/// related fields.
///
/// The form was eighteen sibling blocks in a flat list, every one of them a
/// peer of every other. Three groups is the whole hierarchy — the board's
/// field order is unchanged inside them.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;

  /// Fixed slots, exactly like the list that holds the groups: a section that
  /// turns on renders `SizedBox.shrink()` when it is off rather than leaving
  /// the column, so its siblings keep their positions and their hook state.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: ansiSerif(size: 17)),
        const SizedBox(height: 7),
        Container(height: 1, color: AnsiColors.line),
        ...children,
      ],
    ),
  );
}

/// What this row is doing to everyone's totals — at the TOP of the form.
///
/// It was the last thing on the page: you had to scroll the whole scroll to
/// learn that the row you are editing does not count yet, which is the first
/// thing you want to know and the reason the Confirm button exists.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.ingredient, this.creating = false});

  final Ingredient ingredient;

  /// A row that does not exist yet (C2). It says so plainly rather than
  /// calling itself a stub, which is a thing a SAVED row is.
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

/// The doors that fill a row in from a source, side by side.
///
/// They were fifteen blocks apart — the scanner above the name field, "Look
/// up in USDA" below the confirm CTA — although they answer the same question.
///
/// **Each leg is a slot the host fills or leaves empty**, and an empty block
/// draws nothing at all: the two doors are offered on different rows (a scan
/// fills what is empty; a lookup re-sources anything), so a label over a row
/// with one button in it, or over none, is the ordinary case rather than a
/// shape to avoid.
class _FillItIn extends StatelessWidget {
  const _FillItIn({required this.scan, required this.usda});

  /// The barcode door, or null on a row with nothing empty to fill.
  final Widget? scan;

  /// The USDA door, or null where the row's provenance card already carries
  /// `Choose another ›` for the food that filled it (U-D2) — that door opens
  /// this same search, and two of them side by side is one door too many. A
  /// row whose match was REFUSED keeps this one: the card is then a record of
  /// what was said no to, not an offer.
  final Widget? usda;

  @override
  Widget build(BuildContext context) {
    if (scan == null && usda == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('FILL IT IN FROM', style: ansiLabel()),
          const SizedBox(height: 6),
          Row(
            spacing: 8,
            children: [
              if (scan != null) Expanded(child: scan!),
              if (usda != null) Expanded(child: usda!),
            ],
          ),
        ],
      ),
    );
  }
}

/// The form's two commitments, pinned under the scroll.
///
/// Only the two acts that commit anything are pinned here; everything else the
/// form can do — returning a row to a stub, looking it up, deleting it — lives
/// in the header's `⋯` or at the top of the form. Stacked in a column at the
/// end of a very long page, a destructive affordance sits a flick below the
/// confirm CTA and neither commitment is reachable without scrolling.
///
/// **One row, not a stack.** Two full-width buttons is a wall, and a label like
/// `Confirm — it counts from here` is a sentence pretending to be one. The
/// promise goes in [message] — the form's existing feedback line, the same one
/// that says "Saved.", "Still used by 3 recipes (4 lines)." and "Filled from …"
/// — leaving `Save` and `Mark complete` to share a row and be ranked by width
/// and colour instead of by stacking order.
///
/// **`Mark complete`, not `Confirm`.** The state is literally called
/// `complete` ([IngredientStatus.complete]) and the strip at the top of the
/// form already reads "Complete — counts in conversions and macro totals";
/// the app was using three words for two states. Not `Finalize`: D5 makes this
/// reversible, and the `⋯` un-does it.
///
/// **A row that does not exist yet gets ONE button.** `Save` and `Mark
/// complete` are the same act there — a new ingredient is saved complete or
/// not at all, because a stub is a thing the seed leaves behind for a person
/// to finish, not a thing this form should be able to mint. So the button is
/// enabled only while the row would pass the completion gate, and the line
/// above it says what is still missing.
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

  /// Gated on the whole completion check — macros on a basis (D5: a density is
  /// not required) and nothing the form would refuse. The line above says what
  /// is missing rather than the button going quiet.
  final bool canComplete;

  /// The form's one feedback line — a save, a delete refusal with its count,
  /// a USDA fill, or what completion is still waiting for. On screen at any
  /// scroll position now that it rides here.
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
            // Keyed: the density entry and the measures editor each carry
            // their own small green Save earlier in the tree, and a test
            // reaching for "the form's Save" by text is picking between three
            // of them by position.
            key: kFormSaveKey,
            onPress: canComplete ? onSave : null,
            child: const Text('Save'),
          )
        else if (stub)
          Row(
            spacing: 8,
            children: [
              // Outline and narrow, so the two greens stop competing: on a
              // stub the act that matters is completing it, and Save is the
              // way to put the form down without doing that.
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

/// Runs [change] with the keyboard put down — for an intent that rebuilds the
/// fields it is dispatched from. The same reason the form's own `leave` does
/// it: a focused field whose render object goes keeps asking the framework
/// where its caret is, and the framework asserts.
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
