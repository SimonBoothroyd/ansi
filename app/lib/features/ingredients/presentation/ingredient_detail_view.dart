/// The ingredient form (`/ingredients/:id`, and `/ingredients/new` for a row
/// that does not exist yet) — the app's one door to making or fleshing out a
/// vocabulary entry.
///
/// **This file draws it.** Everything it intends and has not written is the
/// [IngredientForm] ViewModel's draft, and every tap dispatches an intent —
/// so what one Save sends can be asked without a widget tree.
///
/// It is an **editor**, not a one-way queue: a `complete` row opens here too.
/// What it owns, in order — canonical name (a rename rewrites `match_text`),
/// aliases, category + default unit, macros with their basis, density (the
/// shared [DensityEntry]), the piece weight on a count-default row (the shared
/// [PieceWeightEntry], ADR-0015), and the explicit ADR-0008 `allowed_units`
/// list.
///
/// Three rules the screen exists to enforce:
/// - **Nothing is written until Save** (ADR-0011). Everything the form intends
///   sits in a draft, so a form with no row behind it is coherent and backing
///   out of one leaves nothing to clean up.
/// - **Macros gate completion, density does not.** Confirming is a human act; a
///   USDA or barcode prefill fills fields and stops.
/// - **Delete is refused while a live recipe line points here**, with the
///   count — a line's ingredient is never allowed to dangle.
///
/// The form scans a barcode into itself, through the same [applyDraft] rule
/// every draft lands by: fields that are EMPTY fill, a value the human already
/// typed stays (and the card says which), provenance becomes `off:<barcode>`
/// only where the row had none, and nothing confirms the row.
///
/// The macros section has a **per serving** mode: the four fields take a
/// label's figures as printed, a serving row says what they describe, and the
/// row still stores per 100 of the basis — derived unrounded
/// ([Macros.per100From]) and previewed live. The serving's "1 tbsp = 14 g" is
/// offered, opt-in, as this row's density (or a measure when it names a thing)
/// in the same save. A barcode draft whose panel came per serving lands on that
/// mode.
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

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../books/presentation/text_prompt.dart';
import '../barcode/barcode_add.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/apply_draft.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/normalize.dart';
import '../domain/serving_offer.dart';
import '../domain/usda_probe.dart';
import 'density_entry.dart';
import 'draft_card.dart';
import 'ingredient_view_models.dart';
import 'measures_editor.dart';
import 'piece_weight_entry.dart';
import 'serving_row.dart';
import 'usda_pick_sheet.dart';

/// The pushed route for one vocab row.
String ingredientDetailRoute(String id) => '/ingredients/$id';

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

/// The dock's CTA: `Mark complete` on a stub, absent on a complete row.
const kFormCompleteKey = ValueKey('form-complete');

class IngredientDetailView extends ConsumerWidget {
  const IngredientDetailView({
    this.ingredientId,
    this.name = '',
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

  /// Forwarded to the form's barcode scan. Both exist for tests and are null
  /// in app code — the router builds this page with neither, and the scan
  /// then takes the real Open Food Facts client from its provider and the
  /// real camera preview.
  final OffLookup? lookup;
  final BarcodeCameraPane? cameraPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    // reach that state through callbacks threaded back up.
    //
    // It is built only once the row is HERE, so the ViewModel seeds its draft
    // from a real row rather than from a blank it would have to reconcile.
    if (async.asData?.value != null) {
      return _DetailForm(
        // Keyed by id so pushing a different ingredient rebuilds the form
        // state instead of inheriting the previous row's typed values.
        key: ValueKey(ingredientId!),
        ingredientId: ingredientId,
        lookup: lookup,
        cameraPane: cameraPane,
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
  required String title,
  List<Widget> suffixes = const [],
}) => FHeader.nested(
  title: Text(title, style: ansiHeaderTitle(), overflow: TextOverflow.ellipsis),
  prefixes: [
    FHeaderAction.back(
      onPress: () =>
          context.canPop() ? context.pop() : context.goOnce('/ingredients'),
    ),
  ],
  suffixes: suffixes,
);

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

class _DetailForm extends ConsumerWidget {
  const _DetailForm({
    required this.ingredientId,
    this.initialName = '',
    this.lookup,
    this.cameraPane,
    super.key,
  });

  /// Null while creating. The form's own state lives in [IngredientForm],
  /// keyed by this — so the draft and the rules that shape it are testable
  /// without a widget tree, and this file only draws.
  final String? ingredientId;

  final String initialName;
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
        ingredient: ing,
        name: draft.name.trim().isEmpty ? ing.canonicalName : draft.name,
      );
      if (pick == null) return;
      form.applyUsdaPick(pick);
    }

    // Leaving the form. A cold deep link lands here with no page beneath, so
    // there is nothing to pop: fall back to the manager, exactly as the back
    // chevron and the delete both do.
    // Pops with the row when there is one, so a caller waiting on this form
    // — the editor's picker, which pushes it and then opens the quantity
    // sheet on the units it just set — gets what it was waiting for.
    void leave([Ingredient? result]) =>
        context.canPop() ? context.pop(result) : context.goOnce('/ingredients');

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
      context.canPop() ? context.pop() : context.goOnce('/ingredients');
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
        stub: stub,
        canComplete: !busy && draft.storedMacros != null,
        // The line the CTA's promise moved into: what a save said, what a
        // delete refused, or — while the CTA is disabled — what it is waiting
        // for.
        message:
            draft.message ??
            (stub
                ? (draft.storedMacros == null
                      ? 'needs macros'
                      : 'completing it counts it in conversions and macro '
                            'totals')
                : null),
        // Only the button leaves: three other callers use the save as a FLUSH
        // and none of those may navigate.
        onSave: busy
            ? null
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

          // The two prefill doors, in one place: they are the same offer, and
          // both are mutually exclusive with the provenance card that replaces
          // them.
          if (stub)
            _FillItIn(
              onScan: busy ? null : scan,
              usda: isUsdaPrefilled(ing.source) || isUsdaDeclined(ing.source)
                  ? null
                  : _GhostButton(
                      label: 'Look up in USDA',
                      onTap: busy ? null : pickUsda,
                    ),
            )
          else
            const SizedBox.shrink(),

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
              FTextField(
                // Keyed on the seed: `initial` seeds the controller once, so a
                // scan that lands a product name needs a new field to seed it
                // into.
                key: ValueKey('canonical-name-${draft.nameSeed}'),
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(text: draft.name),
                  onChange: (v) => form.setName(v.text),
                ),
              ),
              const _Note('renaming rewrites the match text'),

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
              // never touched), and the two doors are the only place the
              // prefill can be refused or re-chosen.
              _UsdaProvenance(
                ingredient: ing,
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
              _BarcodeProvenance(ingredient: ing),

              const _Label('MACROS', hint: 'enter them as the label reads'),
              // One segment, in the section it changes. Per 100 of the basis is
              // the default; per serving reveals the row below and reads the
              // same four fields as the label prints them.
              Row(
                children: [
                  AnsiModeChip(
                    label: 'per 100 g',
                    selected:
                        !draft.perServing && draft.basis == MacrosBasis.perG,
                    onTap: () => form.setBasis(MacrosBasis.perG),
                  ),
                  const SizedBox(width: 6),
                  AnsiModeChip(
                    label: 'per 100 ml',
                    selected:
                        !draft.perServing && draft.basis == MacrosBasis.perMl,
                    onTap: () => form.setBasis(MacrosBasis.perMl),
                  ),
                  const SizedBox(width: 6),
                  AnsiModeChip(
                    label: 'per serving',
                    selected: draft.perServing,
                    onTap: form.setPerServing,
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
                ServingRow(
                  key: ValueKey('serving-row-${draft.servingSeed}'),
                  draft: draft.serving,
                  basis: draft.basis,
                  onAmount: form.setServingAmount,
                  onName: form.setServingName,
                  onBasis: form.setServingBasis,
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
              if (draft.perServing)
                StoredPer100Line(
                  basis: draft.basis,
                  serving: draft.serving,
                  printed: draft.printedMacros,
                )
              else
                const SizedBox.shrink(),
              if (draft.offer case final offer?)
                _ServingOfferLine(
                  offer: offer,
                  taken: draft.servingOfferTaken,
                  onToggle: (v) => form.takeServingOffer(taken: v),
                )
              else
                const SizedBox.shrink(),
            ],
          ),

          // Density, the piece weight, admission, the default unit and the
          // measures are ONE subject — what a line of a recipe may say about
          // this row, and how much of it that is. The default unit sits here
          // rather than beside the category because it obeys the same rule as
          // the chips:
          // `unitSayableAsDefault` and the chips' own candidate list are one
          // predicate wearing two hats, so a greyed selector option and a
          // locked chip explain each other. It also puts the stranded
          // default's repair — "enter a density below" — one section above the
          // density, rather than two groups away.
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
              _DensityGapNote(ingredient: draftRow),

              // The entry draws its own DENSITY label, so the section does
              // not repeat one above it.
              DensityEntry(
                // `draftRow`, not the stored row: the headline shows the
                // density the form is HOLDING, and "Remove it? tsp · tbsp …
                // lock again" names the units the draft would strip. Reading
                // the row here would show a number the person has already
                // replaced, or none where they have just typed one.
                ingredient: draftRow,
                redirectedSpoon: draft.redirectedSpoon,
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
                  onDelete: (m) async => form.removeMeasure(m.id),
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
/// Read off the row's own `source_label` / `source_score`, never off a live
/// probe — the form is offline-first, and after a rename a fresh probe would
/// name a different food than the one that actually filled the row. Nothing
/// here confirms: the header says *not confirmed* until a human taps Confirm
/// below.
///
/// Three states, one widget, because they are the same fact at three moments:
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
class _UsdaProvenance extends StatelessWidget {
  const _UsdaProvenance({
    required this.ingredient,
    required this.onDecline,
    required this.onChooseAnother,
  });

  final Ingredient ingredient;

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

    final String header;
    final String line;
    if (declined) {
      header = 'USDA · declined';
      line =
          '${label ?? 'that USDA food'} — not this food · the filled numbers '
          'were cleared';
    } else {
      // B-D2: *edited here* replaces the confirm word, because it is the more
      // interesting fact about the row — a confirmed row whose numbers you
      // typed is not "confirmed from USDA" in any sense a reader would mean.
      header = edited
          ? 'Filled from USDA · edited here'
          : 'Filled from USDA · ${stub ? 'not confirmed' : 'confirmed'}';
      line = [
        // The id is the last resort, not a caption: a row that can name its
        // food says the name and nothing else.
        if (label != null && label.isNotEmpty)
          label
        else
          'FDC ${usdaFdcId(source) ?? '?'}',
        if (score != null) UsdaMatchFit.of(score).phraseFor(name),
      ].join(' · ');
    }
    // Amber is a call to action, so it is spent only where there is one: an
    // unconfirmed machine fill. A CONFIRMED row's card is provenance — a
    // statement of where the numbers came from — and it drew a ⚠ over the
    // word "confirmed", which reads as an error about a row that is fine.
    //
    // An EDITED row is the same argument (B-D2): you typed those numbers on
    // purpose, and nothing is wrong with the row. It stays muted even while it
    // is still a stub, because the thing amber would be asking for — look at
    // these machine numbers — is exactly what already happened.
    final tone = declined || edited || !stub
        ? AnsiColors.muted
        : AnsiColors.aging;

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(
          color: declined || edited || !stub ? AnsiColors.line : tone,
        ),
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
  const _BarcodeProvenance({required this.ingredient});

  final Ingredient ingredient;

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
        '$label',
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

/// The four macro inputs. All four or none — a partial panel would compute
/// totals out of numbers nobody supplied (invariant 3).
class _MacroFields extends StatelessWidget {
  const _MacroFields({required this.draft, required this.onChanged, super.key});

  /// Seeds the four controllers when this widget is (re)built under a new key —
  /// so it is the DRAFT, not the row: the form re-keys exactly when it has put
  /// something new in the draft, whether that came from the row (G1) or from a
  /// barcode scan.
  final MacroDraft draft;
  final ValueChanged<MacroDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget field(String label, String seed, MacroDraft Function(String) put) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FTextField(
              // Keyed: the four read alike, and a test that targets them by
              // position breaks the moment a field moves.
              key: ValueKey('macro-$label'),
              // No hint: the caption below already names the field, and the
              // hint said the same word a second time — badly, since "protein"
              // did not fit a quarter of a phone and rendered as "prot…".
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              control: FTextFieldControl.managed(
                initial: TextEditingValue(text: seed),
                onChange: (v) => onChanged(put(v.text)),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: ansiMono(size: 9, color: AnsiColors.muted)),
          ],
        ),
      );
    }

    return Row(
      spacing: 6,
      children: [
        field('kcal', draft.kcal, (t) => draft.copyWith(kcal: t)),
        field('protein', draft.protein, (t) => draft.copyWith(protein: t)),
        field('carb', draft.carb, (t) => draft.copyWith(carb: t)),
        field('fat', draft.fat, (t) => draft.copyWith(fat: t)),
      ],
    );
  }
}

/// M-D2's line — "This serving also says": the serving's "1 tbsp = 14 g"
/// offered as this row's density, or "1 slice = 28 g" as a measure. Off by
/// default: a pack's "about 1 tbsp" is sometimes a guess, and a density
/// minted from a guess would decide what units the row admits.
class _ServingOfferLine extends StatelessWidget {
  const _ServingOfferLine({
    required this.offer,
    required this.taken,
    required this.onToggle,
  });

  final ServingOffer offer;
  final bool taken;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('THIS SERVING ALSO SAYS'),
        FCheckbox(
          key: const ValueKey('serving-offer'),
          value: taken,
          onChange: onToggle,
          label: Text(offer.sentence, style: ansiMono(size: 11)),
        ),
        _Note(
          taken
              ? offer.whenTaken
              : 'not taken — the serving is stored as macros only; tick it '
                    'and Save writes this too',
        ),
      ],
    );
  }
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
                label:
                    '＋ add “pack” = ${formatQuantity(pack.amountInBasis)} '
                    '${pack.basis.baseUnit.label} as a measure',
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
    final sayable = [
      for (final c in candidates)
        if (!c.locked && c.unit.family != UnitFamily.imprecise) c,
    ];
    final words = [
      for (final c in candidates)
        if (!c.locked && c.unit.family == UnitFamily.imprecise) c,
    ];
    // Two locks, two lines (ADR-0015): the other family waits on a density,
    // `piece` waits on a piece weight. One line for both would tell the user
    // a density unlocks `piece`, which nothing ever will.
    final lockedByDensity = [
      for (final c in candidates)
        if (c.locked && c.unit != pieces) c.unit.label,
    ];
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
                  onTap: () => onToggle(c.unit),
                ),
            ],
          ],
        ),
        if (lockedByDensity.isNotEmpty)
          _Note(
            '${lockedByDensity.join(' · ')} unlock when this row has a density',
          ),
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
  });

  final Unit unit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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
/// **D4c** locks the options the row could not honestly say: with no density
/// the other mass/volume family is not pickable as a default any more than it
/// is sayable on a line. The chips are drawn disabled rather than hidden —
/// the same rule the admission section follows, so "why can't I pick cup" has
/// a visible answer one section down.
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
    // Wrapped, not a horizontal scroller. The catalog is wider than a phone,
    // and the scroller clipped the last chip mid-glyph with nothing to say it
    // continued — a row of greyed pills running off the edge reads as broken
    // rather than as "these are locked". D4c's rule is that the unsayable
    // options stay VISIBLE, so "why can't I pick cup" has an answer; a chip
    // you cannot see cannot answer anything.
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final u in kIngredientUnits)
          AnsiModeChip(
            label: u.label,
            // A stranded stored default is still THE selection — that is the
            // truth about the row — but not a healthy one: `stranded` repaints
            // it in the "gone" colour, which is what the line under this row
            // is about. Selection and health are two facts, not one.
            selected: u == selected,
            stranded:
                u == selected &&
                (!unitSayableAsDefault(ingredient, u) ||
                    (u == pieces && ingredient.pieceBasisAmount == null)),
            // `piece` stays tappable with no weight: picking it is what makes
            // the weight sentence appear (ADR-0015); the flag and the Save
            // refusal hold the line, not the chip.
            enabled: unitSayableAsDefault(ingredient, u) || u == selected,
            onTap: () => onPick(u),
          ),
      ],
    );
  }
}

/// **D4c(c)** — the row whose stored default unit its own rules no longer
/// support: `cup` on a per-100 g row with no density (the renamed-rice shape
/// the owner hit). Never rewritten silently; named, with the one tap that
/// repairs it.
///
/// **It stays, and it stops shouting.** This is not the "these units would
/// unlock" advisory beside the admission chips — it names a unit the row is
/// *already using*, so hiding it until a density arrives would hide a broken
/// row from the only person who can fix it, and they would have no reason to
/// add the density because nobody told them anything was wrong. But **D4d**
/// already ruled *keep D4c strict, fix the data* — nineteen stranded rows got
/// a real density — so this is now a rare state, and a rare state should not
/// own a bordered card with a heading, a body and a button. One line with the
/// fix in it; the chip above renders in [AnsiColors.gone] to say which unit.
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
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final adding = useState(false);
    final draft = useState('');
    final error = useState<String?>(null);

    void add() {
      // Same normalizer as the repository, so the two verdicts cannot
      // disagree about what carries an identity word.
      if (normalizeMatchText(draft.value).isEmpty) {
        error.value =
            'That alias carries no identity word — it would match '
            'everything and nothing.';
        return;
      }
      onAdd(draft.value);
      error.value = null;
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
                child: FTextField(
                  hint: 'another name for this',
                  control: FTextFieldControl.managed(
                    onChange: (v) => draft.value = v.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FButton(
                size: FButtonSizeVariant.sm,
                onPress: add,
                child: const Text('Add'),
              ),
            ],
          ),
        ],
        if (error.value != null)
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

/// The advisory under the density entry. A slot rather than a conditional
/// child: it retires the moment a density lands, and in a [ListView] a child
/// that disappears shifts every sibling below it onto the wrong element —
/// silently resetting their hook state, which is how the lookup's own note
/// vanished exactly when it had good news.
///
/// **One line, computed.** It reads the same candidate list the chips do and
/// names those units, or says nothing at all when nothing is locked — never a
/// family inferred from the basis alone, which is wrong for a volume-default
/// row.
class _DensityGapNote extends StatelessWidget {
  const _DensityGapNote({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    if (ingredient.densityGPerMl != null) return const SizedBox.shrink();
    // `piece` is the piece weight's lock, not the density's (ADR-0015).
    final locked = [
      for (final c in allowedUnitCandidates(ingredient))
        if (c.locked && c.unit != pieces) c.unit.label,
    ];
    if (locked.isEmpty) return const SizedBox.shrink();
    return _Note('no density — ${locked.join(' · ')} locked');
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

/// The two doors that fill a stub in from a source, side by side.
///
/// They were fifteen blocks apart — the scanner above the name field, "Look
/// up in USDA" below the confirm CTA — although they answer the same question
/// and both stop being offered once the row has a USDA provenance card.
class _FillItIn extends StatelessWidget {
  const _FillItIn({required this.onScan, required this.usda});

  final Future<void> Function()? onScan;

  /// The USDA door, or null on a row USDA has already filled or a person has
  /// already refused — there the provenance card's own `Choose another ›` is
  /// the way to change the match (U-D2), and it opens this same search.
  final Widget? usda;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('FILL IT IN FROM', style: ansiLabel()),
        const SizedBox(height: 6),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: _GhostButton(label: 'Scan a barcode', onTap: onScan),
            ),
            if (usda != null) Expanded(child: usda!),
          ],
        ),
      ],
    ),
  );
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
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.stub,
    required this.canComplete,
    required this.message,
    required this.onSave,
    required this.onComplete,
  });

  final bool stub;

  /// Gated on macros (D5): density is not required, and the line above says
  /// why rather than the button going quiet.
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
        if (stub)
          Row(
            spacing: 8,
            children: [
              // Outline and narrow, so the two greens stop competing: on a
              // stub the act that matters is completing it, and Save is the
              // way to put the form down without doing that.
              SizedBox(
                width: 92,
                child: FButton(
                  // Keyed: the density entry and the measures editor each
                  // carry their own small green Save earlier in the tree, and
                  // a test reaching for "the form's Save" by text is picking
                  // between three of them by position.
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

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(text, style: ansiMono(size: 10, color: AnsiColors.muted)),
  );
}

/// How the offer reads on screen. The arithmetic is
/// [servingOfferFor]'s; these are the only two sentences it needs, and they
/// stay here because a domain rule does not own words.
extension ServingOfferSentences on ServingOffer {
  /// The tick's label: "1 tbsp weighs 14 g — set as density".
  String get sentence => switch (this) {
    DensityOffer(:final unit, :final gramsPerUnit) =>
      '1 ${unit.label} weighs ${formatQuantity(gramsPerUnit)} g — set as '
          'density',
    MeasureOffer(:final label, :final amount, :final basis) =>
      '1 $label = ${formatQuantity(amount)} ${basis.baseUnit.label} — add as '
          'a measure',
  };

  /// The note under a taken tick: what Save will do with it.
  String get whenTaken => switch (this) {
    DensityOffer(:final gPerMl) =>
      '= ${formatDensity(gPerMl)} g/ml, written with this Save through the '
          'density entry — the volume chips unlock as they do when a density '
          'is typed by hand',
    MeasureOffer() =>
      'lands in the measures below with this Save — rename it or bin it '
          'there',
  };
}
