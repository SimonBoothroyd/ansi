/// The ingredient detail / flesh-out form (`/ingredients/:id`) — design board
/// "Ingredients manager · v1" frames (b) and (c), which fold the original
/// "New ingredient" frame together with 7.7's macros-basis frame and 7.8's
/// allowed-units frame into one scroll.
///
/// It is an **editor**, not a one-way queue: a `complete` row opens here too
/// (plan 0020 D5). What it owns, in the frame's order — canonical name (a
/// rename rewrites `match_text`, D6), aliases, category + default unit,
/// macros with their basis, density (the shared 7.8 [DensityEntry]), and the
/// explicit ADR-0008 `allowed_units` list.
///
/// Two rules the screen exists to enforce:
/// - **Macros gate completion, density does not** (D5). Confirming is a
///   human act; a USDA or barcode prefill fills fields and stops.
/// - **Delete is refused while a live recipe line points here**, with the
///   count — a line's ingredient is never allowed to dangle.
///
/// Since plan 0025 #8 the form scans a barcode into itself: the same
/// `scanBarcodeForDraft` door the add sheet uses, landed through the same
/// `applyDraft` rule — fields that are EMPTY fill, a value the human already
/// typed stays (and the card says which), provenance becomes `off:<barcode>`
/// only where the row had none, and nothing confirms the row. Since the form
/// and the add sheet are one form, a row created by name and then scanned
/// ends up exactly where a row created by scan would.
///
/// Since plan 0027 (front M) the macros section has a **per serving** mode:
/// the four fields take a label's figures as printed, a serving row says what
/// they describe, and the row still stores per 100 of the basis — derived
/// unrounded ([Macros.per100From], M-D3) and previewed live. The serving's
/// "1 tbsp = 14 g" is offered, opt-in, as this row's density (or a measure
/// when it names a thing) in the same save (M-D2). A barcode draft whose
/// panel came per serving lands on that mode (M-D5).
/// Since plan 0027 (front U) the form **names the USDA match** at the head of
/// its macros section — the food's description, its FDC id and a band word,
/// read off the row's own `source_label` / `source_score` so it is true
/// offline — with two doors beside it: *Not this food* (one write: the
/// prefilled density and macros come out, `source` becomes `usda_declined`,
/// and the rename trigger leaves the row alone from then on) and *Choose
/// another ▸* (the next five candidates, a pick applied through the same
/// `applyUsdaProbe`). Neither confirms anything (U-D4).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../books/presentation/text_prompt.dart';
import '../../recipes/presentation/format.dart';
import '../barcode/barcode_add.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/apply_draft.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/normalize.dart';
import '../domain/usda_probe.dart';
import 'density_entry.dart';
import 'draft_card.dart';
import 'measures_editor.dart';
import 'serving_row.dart';
import 'usda_pick_sheet.dart';

/// The pushed route for one vocab row.
String ingredientDetailRoute(String id) => '/ingredients/$id';

/// The form's own Save, in the pinned dock — as distinct from the small
/// Saves the density entry and the measures editor carry for their own
/// immediate writes. Exported so tests name it rather than counting FButtons.
const kFormSaveKey = ValueKey('form-save');

/// The dock's CTA: `Mark complete` on a stub, absent on a complete row.
const kFormCompleteKey = ValueKey('form-complete');

class IngredientDetailView extends ConsumerWidget {
  const IngredientDetailView({
    required this.ingredientId,
    this.lookup,
    this.cameraPane,
    super.key,
  });

  final String ingredientId;

  /// Forwarded to the form's barcode scan. Both exist for tests and are null
  /// in app code — the router builds this page with neither, and the scan
  /// then takes the real Open Food Facts client from its provider and the
  /// real camera preview, exactly as the add sheet does.
  final OffLookup? lookup;
  final BarcodeCameraPane? cameraPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ingredientByIdProvider(ingredientId));
    final ingredient = async.asData?.value;

    // The form owns its own scaffold: the header's `⋯` menu and the pinned
    // action bar both act on form state (the pending edits, the busy flag,
    // the one message line), and a scaffold built above them could only
    // reach that state through callbacks threaded back up.
    if (ingredient != null) {
      return _DetailForm(
        // Keyed by id so pushing a different ingredient rebuilds the form
        // state instead of inheriting the previous row's typed values.
        key: ValueKey(ingredientId),
        ingredient: ingredient,
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

class _DetailForm extends HookConsumerWidget {
  const _DetailForm({
    required this.ingredient,
    this.lookup,
    this.cameraPane,
    super.key,
  });

  final Ingredient ingredient;
  final OffLookup? lookup;
  final BarcodeCameraPane? cameraPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ing = ingredient;
    final name = useState(ing.canonicalName);
    final category = useState(ing.category ?? '');
    final defaultUnit = useState(ing.defaultUnit);
    final basis = useState(ing.macrosBasis);
    final macros = useState<_MacroDraft>(_MacroDraft.from(ing.macros));
    // What the row last handed the macro draft. "Untouched" is defined against
    // this rather than against blankness, so a row that arrives with numbers
    // is as re-seedable as an empty one (G1, below).
    final seededMacros = useState<_MacroDraft>(_MacroDraft.from(ing.macros));
    // Bumped on every re-seed, and used as the macro fields' key. See G1.
    final macroSeed = useState(0);
    // Plan 0027 M-D1: the macros section's per-serving mode. The four fields
    // then hold the label's figures AS PRINTED and the serving row says what
    // they describe; what is stored is still per 100 of the basis (M-D3).
    final perServing = useState(false);
    final serving = useState(const ServingDraft());
    // Bumped when a scan seeds the serving row, and used as its key — the
    // same mechanism the macro fields use (G1).
    final servingSeed = useState(0);
    // M-D2: the serving's "1 tbsp = 14 g" as this row's density (or a
    // measure) — off by default, one tap, the same save.
    final servingOffer = useState(false);
    final allowed = useState(allowedUnitsFor(ing).toSet());
    final message = useState<String?>(null);
    final busy = useState(false);
    // Set when the measures editor refused a volume-named label and handed
    // back the resolved spoon — the density entry pre-picks it (F2: one
    // shared editor, so the redirect works here exactly as in the sheet).
    final redirectedSpoon = useState<Unit?>(null);
    // **The draft (plan 0029 W5).** Everything the form intends and has not
    // written. Held as DELTAS rather than as replacement lists, which is what
    // answers D6's hazard structurally: a save that only inserts its adds and
    // tombstones its named removes never needs the whole list, so a measures
    // stream that failed to load cannot become a narrowed set written back.
    // The one place emptiness is still load-bearing — the `piece` question —
    // checks that the list actually loaded before it reads it as empty.
    final densityChange = useState<DensityChange>(const DensityUnchanged());
    final measuresAdded = useState<List<Measure>>(const []);
    final measuresRemoved = useState<Set<String>>(const {});
    final defaultMeasure = useState<DefaultMeasureChange>(
      const DefaultMeasureUnchanged(),
    );
    // The last barcode scan (plan 0025 #8): the draft the card shows, what
    // `applyDraft` decided about it, and whether its pack offer was taken.
    final scanned = useState<IngredientDraft?>(null);
    final scanApplied = useState<DraftApplication?>(null);
    final packAdded = useState(false);
    // A provenance the scan stamped and the next Save writes — held with the
    // macros it explains rather than written on its own, so backing out of
    // the form leaves the row exactly as it was found.
    final pendingSource = useState<String?>(null);
    final measuresAsync = ref.watch(ingredientMeasuresProvider(ing.id));

    // The density AS THE FORM HOLDS IT. Nothing has been written, so the
    // chips, the gap note and the entry's own headline all read the draft —
    // and `allowed_units` follows it here, in the form, which is why
    // `saveForm` writes the set as given instead of re-deriving it (W3).
    final densityValue = switch (densityChange.value) {
      DensitySet(:final gPerMl) => gPerMl,
      DensityCleared() => null,
      DensityUnchanged() => ing.densityGPerMl,
    };
    // The row as the FORM currently reads it: the stored facts with the two
    // draft choices the D4c admission rule turns on — the default unit and
    // the macros basis — folded in. Every "what may this row say" question
    // below asks this rather than the stored row, so flipping the basis chip
    // moves the locks and the flag with it instead of leaving them answering
    // for a row nobody is looking at.
    // `copyWith` reads a null as "unchanged" (freezed), so a CLEARED density
    // has to be built field-by-field — the same reason the repository's own
    // clear does not go through copyWith.
    final draftRow = densityValue == null
        ? Ingredient(
            id: ingredient.id,
            canonicalName: ingredient.canonicalName,
            defaultUnit: defaultUnit.value,
            status: ingredient.status,
            category: ingredient.category,
            macros: ingredient.macros,
            macrosBasis: basis.value,
            allowedUnits: ingredient.allowedUnits,
            measureCount: ingredient.measureCount,
            source: ingredient.source,
            sourceLabel: ingredient.sourceLabel,
            sourceScore: ingredient.sourceScore,
            defaultMeasureId: ingredient.defaultMeasureId,
          )
        : ingredient.copyWith(
            defaultUnit: defaultUnit.value,
            macrosBasis: basis.value,
            densityGPerMl: densityValue,
          );

    useEffect(() {
      final next = {...allowed.value};
      if (densityValue != null) {
        next.addAll(densityUnlockedUnits(draftRow));
      } else {
        next.removeAll(densityStrippedUnits(draftRow));
      }
      allowed.value = next;
      return null;
    }, [densityValue]);

    // **G1 — a lookup's numbers reach the fields, not just the row.**
    //
    // The macro inputs are seeded once, when their controllers are built: a
    // successful "Look up in USDA" wrote macros into the row and re-rendered
    // everything *derived* from it (the banner, the chips, the status line)
    // while the four fields went on showing the blanks they were born with.
    //
    // Re-seeding the draft is half the fix; the other half is making the
    // framework rebuild the controllers, which it will only do for a child
    // whose key changed. Keying is the approach that survives this file's
    // stable-slot rule — the ListView index does not move, so no sibling is
    // reconciled against the wrong element; only the keyed subtree at that
    // fixed index is replaced.
    //
    // The guard is what keeps a pending edit safe: the draft is re-seeded only
    // while it still says exactly what the row last put there. Type into any
    // macro field and the row's own changes stop overwriting you.
    final rowMacros = ing.macros;
    useEffect(() {
      final fresh = _MacroDraft.from(rowMacros);
      if (fresh == seededMacros.value) return null; // the row didn't move
      if (macros.value != seededMacros.value) return null; // yours wins
      seededMacros.value = fresh;
      macros.value = fresh;
      macroSeed.value++;
      // A row's own macros are per 100 by definition — the fields now hold
      // them, so the mode must say so.
      perServing.value = false;
      return null;
    }, [rowMacros]);

    // A `complete` row is one whose macros the household stands behind — the
    // form's own draft is what the CTA acts on, so the gate reads the draft.
    // In per-serving mode the fields hold the printed four and the draft is
    // their per-100 derivation (M-D1/M-D3) — null until the serving weight
    // is in, so nothing is stored that was divided by a blank.
    final printed = macros.value.toMacros();
    final servingAmount = serving.value.amount;
    final draftMacros = !perServing.value
        ? printed
        : (printed == null || servingAmount == null)
        ? null
        : Macros.per100From(
            serving: servingAmount,
            basis: basis.value,
            printed: printed,
          );
    final offer = perServing.value
        ? servingOfferFor(serving.value, basis.value)
        : null;
    final stub = ing.status == IngredientStatus.stub;

    Future<Ingredient?> save({bool markComplete = false}) async {
      if (name.value.trim().isEmpty) {
        message.value =
            'A name is the one field an ingredient can’t go '
            'without.';
        return null;
      }
      if (!macros.value.isCoherent) {
        message.value =
            'Enter all four macros, or leave them all blank — a '
            'part of a panel isn’t a panel.';
        return null;
      }
      if (perServing.value && printed != null && servingAmount == null) {
        message.value =
            'One serving is how much? The label’s figures become per 100 '
            'only once the serving weight is typed.';
        return null;
      }
      busy.value = true;
      try {
        // M-D2: the opt-in, taken. It rides the same one write as everything
        // else now — it used to be the exception that already deferred to
        // Save, which is why the plan named it the model to copy.
        final taken = servingOffer.value ? offer : null;
        final offeredDensity = taken is DensityOffer ? taken.gPerMl : null;
        final offeredMeasure = taken is MeasureOffer ? taken : null;
        final density = offeredDensity != null
            ? DensitySet(offeredDensity)
            : densityChange.value;
        // **One call.** The row's fields, the density, every measure added
        // and removed, "Counts as" and — when the CTA asked — the status
        // flip, in a single transaction (W3/W5b). Nothing here can half-land.
        final outcome = await ref.write(
          context,
          'save ${ing.canonicalName}',
          () async => (
            row: await ref
                .read(ingredientRepositoryProvider)
                .saveForm(
                  ing.id,
                  IngredientFormEdit(
                    row: IngredientEdit(
                      canonicalName: name.value,
                      defaultUnit: defaultUnit.value,
                      macrosBasis: basis.value,
                      allowedUnits: allowed.value,
                      category: category.value.trim().isEmpty
                          ? null
                          : category.value.trim(),
                      macros: draftMacros,
                      source: pendingSource.value,
                    ),
                    density: density,
                    measuresAdded: [
                      for (final m in measuresAdded.value)
                        PendingMeasure(
                          id: m.id,
                          label: m.label,
                          amount: m.amount,
                        ),
                      if (offeredMeasure != null)
                        PendingMeasure(
                          id: const Uuid().v4(),
                          label: offeredMeasure.label,
                          amount: offeredMeasure.amount,
                        ),
                    ],
                    measuresRemoved: measuresRemoved.value,
                    defaultMeasure: defaultMeasure.value,
                    markComplete: markComplete,
                  ),
                ),
            measureAdded: offeredMeasure != null,
          ),
        );
        if (outcome == null || !context.mounted) return null;
        final saved = outcome.row;
        if (saved == null) {
          message.value = 'It is no longer here.';
          return null;
        }
        // Landed, so the draft empties: a second Save must not write any of
        // it twice. This is the one place the draft is discarded on purpose.
        pendingSource.value = null;
        servingOffer.value = false;
        densityChange.value = const DensityUnchanged();
        measuresAdded.value = const [];
        measuresRemoved.value = const {};
        defaultMeasure.value = const DefaultMeasureUnchanged();
        ref
          ..invalidate(ingredientByIdProvider(ing.id))
          ..invalidate(ingredientMeasuresProvider(ing.id));
        message.value = 'Saved.';
        return saved;
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    // Item 8: the barcode door, from the form. What lands is decided by the
    // shared rule, against the form's OWN draft — a panel typed and not yet
    // saved is as much the human's as a saved one.
    Future<void> scan() async {
      final draft = await scanBarcodeForDraft(
        context,
        // An explicit parameter wins (tests); otherwise the app's own client,
        // by provider — the seam `make test-sim` overrides.
        lookup: lookup ?? ref.read(offLookupProvider),
        cameraPane: cameraPane,
      );
      if (draft == null || !context.mounted) return;
      final applied = applyDraft(
        draft,
        target: DraftTarget(
          name: name.value,
          hasMacros: !macros.value._allBlank,
          macrosBasis: basis.value,
          source: pendingSource.value ?? ing.source,
        ),
      );
      scanned.value = draft;
      scanApplied.value = applied;
      packAdded.value = false;
      if (applied.macros != null) {
        basis.value = applied.macrosBasis!;
        // Into the fields, not just the state: re-keying the inputs is how
        // the controllers pick the new text up (G1's mechanism).
        macros.value = _MacroDraft.from(applied.macros);
        macroSeed.value++;
        perServing.value = false;
      }
      final panel = applied.servingPanel;
      if (panel != null) {
        // M-D5: a per-serving panel lands on the per-serving mode — the four
        // as printed, the serving amount prefilled when OFF had a number and
        // otherwise left for the person, never parsed out of the free text.
        perServing.value = true;
        if (panel.servingBasis != null) basis.value = panel.servingBasis!;
        macros.value = _MacroDraft.from(panel.printed);
        macroSeed.value++;
        serving.value = ServingDraft.fromPanel(panel);
        servingSeed.value++;
        servingOffer.value = false;
      }
      if (applied.source != null) pendingSource.value = applied.source;
    }

    // **The USDA search — one door, two entry points.**
    //
    // `Fill it in from ▸ Look up in USDA` and the provenance card's
    // `Choose another ›` are the same act: ask USDA about this row and let a
    // human pick. It used to be two different things — the fill button ran
    // `probe.probe`, applied the single best hit sight-unseen and reported it
    // in a status sentence, while only `Choose another` showed the five.
    //
    // It asks about **the name in the field**, not the stored row, which is
    // what retires **F1**: the lookup no longer has to save the form first to
    // avoid probing a stale name, because a query taken from the field cannot
    // be stale. Nothing is written until a candidate is picked.
    Future<void> pickUsda() async {
      // Captured BEFORE the sheet: the write after it goes through these,
      // never the widget's ref (app/AGENTS.md — the row can be unmounted by
      // the time the person picks).
      final repo = ref.read(ingredientRepositoryProvider);
      final container = ProviderScope.containerOf(context, listen: false);
      final host = hostContextOf(context);
      busy.value = true;
      try {
        final pick = await showUsdaPickSheet(
          context,
          ingredient: ing,
          name: name.value.trim().isEmpty ? ing.canonicalName : name.value,
        );
        if (pick == null) return;
        // U-D3: the same apply path as every other fill, with the declined
        // guard lifted for a person's own choice — the stamp, the label and
        // the score move to the chosen food. Still a stub (U-D4).
        final applied = await container.write(
          host,
          'use that USDA match',
          () => repo.applyUsdaProbe(
            ing.id,
            source: pick.source,
            sourceLabel: pick.description,
            sourceScore: pick.score,
            densityGPerMl: pick.densityGPerMl,
            macros: pick.macros,
            explicitPick: true,
          ),
        );
        if (applied == null) return;
        container.invalidate(ingredientByIdProvider(ing.id));
        if (!context.mounted) return;
        // **An explicit pick outranks a half-typed panel.**
        //
        // G1's guard — "the row re-seeds the draft only while the draft still
        // says exactly what the row last put there" — was written for the
        // AUTOMATIC fill, where the row moving underneath a person who is
        // typing must not steal their keystrokes. A pick is not that: it is
        // someone choosing this food's numbers on purpose, and leaving the
        // fields showing what they had typed would both look like the pick
        // did nothing AND let the next Save write the stale draft back over
        // the fill.
        //
        // So the draft is set from the applied row and re-seeded in the same
        // breath — `seededMacros` moves with it, so G1's effect sees a draft
        // that already matches the row and stands down. This is exactly what
        // the barcode scan does with `applyDraft`; the two explicit fills now
        // behave alike.
        if (applied.macros != null) {
          basis.value = applied.macrosBasis;
          final filled = _MacroDraft.from(applied.macros);
          macros.value = filled;
          seededMacros.value = filled;
          macroSeed.value++;
          perServing.value = false;
        }
        message.value =
            'Filled from “${pick.description}” — still a stub until you '
            'mark it complete.';
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    // Leaving the form. A cold deep link lands here with no page beneath, so
    // there is nothing to pop: fall back to the manager, exactly as the back
    // chevron and the delete both do.
    void leave() =>
        context.canPop() ? context.pop() : context.goOnce('/ingredients');

    // The `⋯` actions and the CTA, so the header and the pinned bar can both
    // reach them. They live here rather than inside their own widgets because
    // every one of them reports through this form's single message line.
    // Completing is the page's terminal act, so it ENDS the page. Nothing
    // popped before, although `ingredient_picker` pushes this form and
    // *awaits its pop* before opening the quantity sheet on the units the
    // form just set — so finishing a row from a recipe line left the person
    // on a screen that had told them it counts and given them nothing to do,
    // with a caller waiting behind it.
    // **W5b — one transaction, not two writes.** "A 1-2 combo of save and
    // mark" (owner) is what it always read like, but it WAS two: `save()`
    // then `confirmStub()`, so a failure between them left the row saved and
    // not marked, under an error implying neither happened.
    Future<void> completeRow() async {
      final saved = await save(markComplete: true);
      if (saved == null || !context.mounted) return;
      leave();
    }

    Future<void> unconfirmRow() async {
      final undone = await ref.writeOk(
        context,
        'unconfirm ${ing.canonicalName}',
        () => ref.read(ingredientRepositoryProvider).unconfirm(ing.id),
      );
      if (!undone || !context.mounted) return;
      ref.invalidate(ingredientByIdProvider(ing.id));
      message.value =
          'Back to a stub — it stops counting until you complete it again.';
    }

    // The refusal is the interesting state: it names the count, because "used
    // by 3 recipes" is a thing a user can act on and "failed" is not. It
    // lands in the message line above the action bar, which is on screen
    // whatever the scroll position — the old inline refusal could be written
    // to a part of the page the person had already scrolled past.
    Future<void> deleteRow() async {
      final outcome = await ref.write(
        context,
        'delete ${ing.canonicalName}',
        () => ref.read(ingredientRepositoryProvider).softDelete(ing.id),
      );
      if (outcome == null || !context.mounted) return;
      switch (outcome) {
        case Deleted():
          ref.invalidate(ingredientByIdProvider(ing.id));
          if (context.mounted) {
            context.canPop() ? context.pop() : context.goOnce('/ingredients');
          }
        case DeleteRefused(:final recipeCount, :final lineCount):
          message.value =
              'Still used by $recipeCount '
              '${recipeCount == 1 ? 'recipe' : 'recipes'} '
              '($lineCount ${lineCount == 1 ? 'line' : 'lines'}). '
              'Change those lines first.';
        case DeleteMissing():
          message.value = 'It is already gone.';
      }
    }

    // What the row's measures ARE, as the form holds them: the loaded ones
    // minus what it intends to remove, plus what it intends to add. A pending
    // one is indistinguishable from a stored one on screen, and carries the
    // id it will keep — which is what lets "Counts as" and the `piece`
    // question point at a measure that does not exist yet.
    final loadedMeasures = measuresAsync.asData?.value;
    final measures = [
      for (final m in loadedMeasures ?? const <Measure>[])
        if (!measuresRemoved.value.contains(m.id)) m,
      ...measuresAdded.value,
    ];

    return FScaffold(
      childPad: false,
      header: _header(
        context,
        title: ing.canonicalName,
        suffixes: [
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
        canComplete: !busy.value && draftMacros != null,
        // The line the CTA's promise moved into: what a save said, what a
        // delete refused, or — while the CTA is disabled — what it is waiting
        // for.
        message:
            message.value ??
            (stub
                ? (draftMacros == null
                      ? 'needs macros'
                      : 'completing it counts it in conversions and macro '
                            'totals')
                : null),
        // `save()` itself stays pure: three callers use it as a FLUSH (the
        // USDA lookup's F1 rule, Choose another, and the stranded-default
        // fix) and none of those may navigate. Only the button leaves.
        onSave: busy.value
            ? null
            : () async {
                final saved = await save();
                if (saved != null && context.mounted) leave();
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
          // resets its hook state.
          _StatusStrip(ingredient: ing),

          // The two prefill doors, in one place. They used to sit fifteen
          // blocks apart — the scanner at the top, "Look up in USDA" below
          // the CTA — although they are the same offer and are mutually
          // exclusive with the provenance card that replaces them.
          if (stub)
            _FillItIn(
              onScan: busy.value ? null : scan,
              usda: isUsdaPrefilled(ing.source) || isUsdaDeclined(ing.source)
                  ? null
                  : _GhostButton(
                      label: 'Look up in USDA',
                      onTap: busy.value ? null : pickUsda,
                    ),
            )
          else
            const SizedBox.shrink(),

          if (scanned.value != null && scanApplied.value != null)
            _ScanResult(
              draft: scanned.value!,
              applied: scanApplied.value!,
              packAdded: packAdded.value,
              onAddPack: () async {
                final pack = scanApplied.value!.packMeasure!;
                final added = await ref.writeOk(
                  context,
                  'add that measure',
                  () => ref
                      .read(measureRepositoryProvider)
                      .addMeasure(
                        ingredientId: ing.id,
                        label: 'pack',
                        amount: pack.amountInBasis,
                      ),
                );
                if (!added || !context.mounted) return;
                packAdded.value = true;
                ref.invalidate(ingredientMeasuresProvider(ing.id));
              },
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
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(text: ing.canonicalName),
                  onChange: (v) => name.value = v.text,
                ),
              ),
              const _Note('renaming rewrites the match text'),

              const _Label('ALSO KNOWN AS'),
              _AliasEditor(ingredientId: ing.id),

              const _Label('CATEGORY'),
              _CategoryPicker(
                selected: category.value,
                onPick: (c) => category.value = c,
              ),
            ],
          ),

          _Group(
            title: 'Nutrition',
            children: [
              // U-D1: where the numbers came from, at the head of the section
              // that holds them. A slot again (it renders nothing on a row
              // USDA never touched), and the two doors are the only place the
              // prefill can be refused or re-chosen.
              _UsdaProvenance(
                ingredient: ing,
                onDecline: busy.value
                    ? null
                    : () async {
                        busy.value = true;
                        try {
                          // One write (U-D2): the prefilled density and macros
                          // come out and the row is marked declined. The macro
                          // fields follow through G1's re-seed (the row's
                          // macros moved and the draft was theirs), the chips
                          // through the density effect above.
                          final cleared = await ref.write(
                            context,
                            'undo the USDA fill',
                            () => ref
                                .read(ingredientRepositoryProvider)
                                .declineUsdaPrefill(ing.id),
                          );
                          if (cleared == null || !context.mounted) return;
                          ref.invalidate(ingredientByIdProvider(ing.id));
                          message.value =
                              'Cleared — the USDA numbers are gone, and a '
                              'rename will not bring them back.';
                        } finally {
                          if (context.mounted) busy.value = false;
                        }
                      },
                onChooseAnother: busy.value ? null : pickUsda,
              ),

              const _Label('MACROS', hint: 'enter them as the label reads'),
              // M-D1: one segment, in the section it changes. Per 100 of the
              // basis is the default; per serving reveals the row below and
              // reads the same four fields as the label prints them.
              Row(
                children: [
                  AnsiModeChip(
                    label: 'per 100 g',
                    selected:
                        !perServing.value && basis.value == MacrosBasis.perG,
                    onTap: () {
                      perServing.value = false;
                      basis.value = MacrosBasis.perG;
                    },
                  ),
                  const SizedBox(width: 6),
                  AnsiModeChip(
                    label: 'per 100 ml',
                    selected:
                        !perServing.value && basis.value == MacrosBasis.perMl,
                    onTap: () {
                      perServing.value = false;
                      basis.value = MacrosBasis.perMl;
                    },
                  ),
                  const SizedBox(width: 6),
                  AnsiModeChip(
                    label: 'per serving',
                    selected: perServing.value,
                    onTap: () => perServing.value = true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Three slots: the serving row, the stored line and the M-D2
              // offer hold their positions whether or not the mode is on, so
              // toggling it cannot shift the fields below onto the wrong
              // element. The serving unit sets the BASIS — a 14 g serving
              // reads per 100 g — so the admission chips follow it live.
              if (perServing.value)
                ServingRow(
                  key: ValueKey('serving-row-${servingSeed.value}'),
                  draft: serving.value,
                  basis: basis.value,
                  onAmount: (t) =>
                      serving.value = serving.value.copyWith(amountText: t),
                  onName: (t) =>
                      serving.value = serving.value.copyWith(name: t),
                  onBasis: (b) => basis.value = b,
                )
              else
                const SizedBox.shrink(),
              // The key is the row-version (G1): it changes only when the
              // row's own macros were re-seeded into the draft above, and that
              // is exactly when the four controllers need rebuilding around
              // their new text.
              _MacroFields(
                key: ValueKey('macro-fields-${macroSeed.value}'),
                draft: macros.value,
                onChanged: (d) => macros.value = d,
              ),
              if (perServing.value)
                StoredPer100Line(
                  basis: basis.value,
                  serving: serving.value,
                  printed: printed,
                )
              else
                const SizedBox.shrink(),
              if (offer != null)
                _ServingOfferLine(
                  offer: offer,
                  taken: servingOffer.value,
                  onToggle: (v) => servingOffer.value = v,
                )
              else
                const SizedBox.shrink(),
            ],
          ),

          // Density, admission, measures, "Counts as" and the imprecise words
          // are ONE subject — what a line of a recipe may say about this row,
          // and how much of it that is. They were five top-level sections
          // reading as five unrelated decisions, although a density unlocks
          // the chips, a volume-named measure label redirects into the density
          // entry, and "Counts as" picks one of the measures.
          // Density, admission, the default unit, measures and "Counts as"
          // are ONE subject — what a line of a recipe may say about this row,
          // and how much of it that is. The default unit is here rather than
          // beside the category because **D4c** makes it the same rule as the
          // chips: `unitSayableAsDefault` and the chips' own candidate list
          // are one predicate wearing two hats, and a greyed selector option
          // and a locked chip explain each other. It also puts the stranded
          // default's repair — "enter a density below" — one section above the
          // density, rather than two groups away.
          _Group(
            title: 'Units & measures',
            children: [
              const _Label('DEFAULT UNIT'),
              _UnitChoiceRow(
                // Keyed so a test can ask this row — and only this row —
                // which of its chips D4c has locked.
                key: const ValueKey('default-unit-row'),
                ingredient: draftRow,
                selected: defaultUnit.value,
                onPick: (u) {
                  defaultUnit.value = u;
                  // Only an admissible unit can be tapped (D4c locks the
                  // rest), so admitting the pick can never strand the row.
                  allowed.value = {...allowed.value, u};
                },
              ),
              // D4c: a stored default the rules no longer support — a cup
              // default on a per-100 g row with no density. Flagged with its
              // repair rather than rewritten: how a household buys a thing is
              // not ours to edit.
              _StrandedDefaultNote(
                ingredient: draftRow,
                onFix: () async {
                  final fix = basisDefaultUnitFix(draftRow);
                  defaultUnit.value = fix;
                  allowed.value = {...allowed.value, fix};
                  await save();
                },
              ),

              const _Label('ALLOWED UNITS', hint: 'what a line may say'),
              _AdmissionChips(
                ingredient: draftRow,
                selected: allowed.value,
                onToggle: (u) {
                  final next = {...allowed.value};
                  if (!next.remove(u)) next.add(u);
                  allowed.value = next;
                },
              ),
              _DensityGapNote(ingredient: draftRow),

              // The entry draws its own DENSITY label; the section used to
              // carry a second, longer one directly above it.
              DensityEntry(
                ingredient: ing,
                redirectedSpoon: redirectedSpoon.value,
                // Lane A moves the write OUT of the widget; this host still
                // commits on tap, exactly as before. Lane B is where the form
                // starts holding it in a draft until its own Save — at which
                // point only this function and `saveLabel` change, and the
                // quantity sheet's copy stays as it is.
                // Nothing is written here any more: it goes in the draft and
                // the form's Save lands it (W5). The chips follow it because
                // `draftRow` carries the draft density and the admission
                // effect keys on it.
                saveLabel: 'Add',
                onSave: (gPerMl) async {
                  densityChange.value = DensitySet(gPerMl);
                  redirectedSpoon.value = null;
                  return true;
                },
                onRemove: () async {
                  densityChange.value = const DensityCleared();
                  redirectedSpoon.value = null;
                  return true;
                },
              ),

              const _Label('MEASURES', hint: 'count-like, in the basis'),
              // Load-bearing emptiness (D6): an errored measures stream
              // rendered as `const []` hides rows that exist, and this form's
              // next Save would then write the narrowed set back. So the error
              // is a state, not a fact about the ingredient.
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
                  // It adds to the draft here; the docked Save lands it (R3).
                  addLabel: 'Add',
                  onDelete: (m) async {
                    // A pending add is simply dropped; a stored one is named
                    // for tombstoning. Either way nothing is written yet.
                    if (measuresAdded.value.any((p) => p.id == m.id)) {
                      measuresAdded.value = [
                        for (final p in measuresAdded.value)
                          if (p.id != m.id) p,
                      ];
                    } else {
                      measuresRemoved.value = {...measuresRemoved.value, m.id};
                    }
                    // "Counts as" cannot point at a measure that is going.
                    if (defaultMeasure.value case DefaultMeasureSet(
                      :final measureId,
                    ) when measureId == m.id) {
                      defaultMeasure.value = const DefaultMeasureSet(null);
                    } else if (ing.defaultMeasureId == m.id) {
                      defaultMeasure.value = const DefaultMeasureSet(null);
                    }
                  },
                  // Lane A moves the write out of the editor; this host still
                  // commits on tap. Lane B swaps only this function and the
                  // label for "add it to the draft".
                  onAdd: (label, amount) async {
                    // Minted here, kept forever: `saveForm` inserts under this
                    // id, so the measure the person is looking at is already
                    // the measure the database will hold. The editor has
                    // already refused a blank label, a volume-named one and a
                    // non-positive amount — the same three the repository
                    // refuses — so there is nothing left to be refused by.
                    final pending = Measure(
                      id: const Uuid().v4(),
                      label: label.trim(),
                      amount: amount,
                      basis: basis.value,
                      sortOrder: measures.length,
                    );
                    measuresAdded.value = [...measuresAdded.value, pending];
                    return MeasureAdded(pending);
                  },
                  onStopOfferingPiece: (added) async {
                    // **The lane B trap, answered.** This used to write
                    // `allowed_units` behind the form's back and hand the row
                    // back so the chips could follow. Now the answer IS the
                    // draft: `piece` leaves the admission set the form holds,
                    // and the same act says what a bare "1 tomato" means
                    // (seam D1). Both land on Save, together.
                    allowed.value = {...allowed.value}..remove(pieces);
                    defaultMeasure.value = DefaultMeasureSet(added.id);
                    return null;
                  },
                  // Nothing here selects a measure — the form is not a
                  // quantity entry surface; the watched provider re-renders
                  // the list.
                  onAdded: (_) {},
                  // A volume-named label is a density in disguise (ADR-0008
                  // §2); the editor refuses it and the density section above
                  // pre-picks that spoon, which is the whole point of sharing
                  // one widget.
                  onVolumeLabel: (u) => redirectedSpoon.value = u,
                ),

              // Seam D1's UI (board frame f): what a bare count of this row
              // MEANS. It sits with the measures because it is a fact ABOUT
              // them, and it says nothing on a row that has none — there is
              // nothing to choose and nothing to ask.
              //
              // ONE slot, not a two-child spread: the spread this replaces
              // grew from zero children to two the moment a first measure
              // landed, shifting every sibling below it — the exact failure
              // the note at the head of this list warns about.
              _CountsAsSection(ingredient: ing, measures: measures),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Sections ----------------------------------------------------------------

/// The USDA provenance line (plan 0027 **U-D1**, board frames a and b): which
/// food filled this row, how sure the match was, and the two doors.
///
/// Read off the row's own `source_label` / `source_score`, never off a live
/// probe — the form is offline-first, and after a rename a fresh probe would
/// name a different food than the one that actually filled the row. A row
/// filled before 0027 carries a stamp and no label; it reads as the FDC id
/// alone rather than inventing a name. Nothing here confirms (U-D4): the
/// header says *not confirmed* until a human taps Confirm below.
///
/// Two states, one widget, because they are the same fact at two moments:
/// - **prefilled** (`usda_fdc:<id>`): the name, the id, the band word, and
///   both doors;
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
      header = 'Filled from USDA · ${stub ? 'not confirmed' : 'confirmed'}';
      line = [
        ?label,
        'FDC ${usdaFdcId(source) ?? '?'}',
        if (score != null) '${UsdaBand.of(score).word} for “$name”',
      ].join(' · ');
    }
    // Amber is a call to action, so it is spent only where there is one: an
    // unconfirmed machine fill. A CONFIRMED row's card is provenance — a
    // statement of where the numbers came from — and it drew a ⚠ over the
    // word "confirmed", which reads as an error about a row that is fine.
    final tone = declined || !stub ? AnsiColors.muted : AnsiColors.aging;

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: declined || !stub ? AnsiColors.line : tone),
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

/// The four macro inputs. All four or none — a partial panel would compute
/// totals out of numbers nobody supplied (invariant 3).
class _MacroFields extends StatelessWidget {
  const _MacroFields({required this.draft, required this.onChanged, super.key});

  /// Seeds the four controllers when this widget is (re)built under a new
  /// key — so it is the DRAFT, not the row: the form re-keys exactly when it
  /// has put something new in the draft, whether that came from the row (G1)
  /// or from a barcode scan (plan 0025 #8).
  final _MacroDraft draft;
  final ValueChanged<_MacroDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget field(String label, String seed, _MacroDraft Function(String) put) {
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

/// What the form's own scan landed (plan 0025 #8): the shared result card,
/// naming what it left alone, then what it did NOT do — nothing here saves
/// or confirms — and the pack-size offer as a one-tap measure.
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

/// The ADR-0008 admission section: the units this row admits, the ones it
/// could admit, and — after a divider — the imprecise words its category
/// earns it.
///
/// **The locked units are a line, not chips.** They used to be drawn as
/// dashed grey pills with a note under them, which is a row of screen to say
/// what a sentence says better: "cup · tbsp · ml unlock when this row has a
/// density." D4c's reason for drawing them rather than hiding them was that
/// *"why can't I pick cup" must have a visible answer* — and a named line
/// answers it more completely than a dashed chip, because it also says what
/// to do about it.
///
/// **The imprecise words are folded in** (they were a labelled section of
/// their own, over one read-only string that on most rows said "none"). They
/// are a fact about the *category* (J3), never about this row, so they are
/// drawn after a divider, dotted and untappable — the same idiom the quantity
/// sheet has used for its own chip row since 7.7.
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
    final locked = [
      for (final c in candidates)
        if (c.locked) c.unit.label,
    ];
    final imprecise = impreciseUnitsFor(ingredient).toList();
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
            if (imprecise.isNotEmpty) ...[
              Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                color: AnsiColors.line,
              ),
              for (final u in imprecise) _ImpreciseChip(unit: u),
            ],
          ],
        ),
        if (locked.isNotEmpty)
          _Note('${locked.join(' · ')} unlock when this row has a density'),
        if (imprecise.isNotEmpty)
          const _Note('dotted words come from the category, not from here'),
      ],
    );
  }
}

/// An imprecise word: read out, never toggled. The category decides these
/// (J3), so a tap here would be a promise the form cannot keep.
class _ImpreciseChip extends StatelessWidget {
  const _ImpreciseChip({required this.unit});

  final Unit unit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: AnsiColors.surface,
      border: Border.all(color: AnsiColors.line),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(unit.label, style: ansiMono(size: 11, color: AnsiColors.muted)),
  );
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
/// door to coin a new one (plan 0020 **F3**).
///
/// Free text is gone. A typed category is only useful if it is the *same*
/// string every other row uses — the imprecise-unit gate reads it by exact
/// match (`kImpreciseGatedCategories`), and so does the list's grouping — and
/// free text guaranteed "Produce", "produce" and "produce " would coexist.
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
  static const _none = ' none';

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
        for (final u in kAllUnits)
          AnsiModeChip(
            label: u.label,
            // A stranded stored default is still THE selection — that is the
            // truth about the row — but not a healthy one: `stranded` repaints
            // it in the "gone" colour, which is what the line under this row
            // is about. Selection and health are two facts, not one.
            selected: u == selected,
            stranded: u == selected && !unitSayableAsDefault(ingredient, u),
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
class _StrandedDefaultNote extends StatelessWidget {
  const _StrandedDefaultNote({required this.ingredient, required this.onFix});

  final Ingredient ingredient;
  final Future<void> Function() onFix;

  @override
  Widget build(BuildContext context) {
    if (!defaultUnitNeedsDensity(ingredient)) return const SizedBox.shrink();
    final fix = basisDefaultUnitFix(ingredient);
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          Text(
            '${ingredient.defaultUnit.label} needs a density on this row — '
            'add one below, or',
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
class _AliasEditor extends HookConsumerWidget {
  const _AliasEditor({required this.ingredientId});

  final String ingredientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliases = ref.watch(ingredientAliasesProvider(ingredientId));
    final adding = useState(false);
    final draft = useState('');
    final error = useState<String?>(null);

    Future<void> add() async {
      // Checked here rather than caught: the repository throws for this, and
      // an `ArgumentError` is a programming error to a linter, not a user
      // message. Same normalizer, so the two verdicts can't disagree.
      if (normalizeMatchText(draft.value).isEmpty) {
        error.value =
            'That alias carries no identity word — it would match '
            'everything and nothing.';
        return;
      }
      final added = await ref.writeOk(
        context,
        'add that alias',
        () => ref
            .read(ingredientRepositoryProvider)
            .addAlias(ingredientId, draft.value),
      );
      if (!added || !context.mounted) return;
      error.value = null;
      adding.value = false;
      ref.invalidate(ingredientAliasesProvider(ingredientId));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // Decorative emptiness, weighed (D6): the add field below is the
            // point of this section and works with no list at all; an alias
            // that exists but did not load is re-added harmlessly (the
            // repository is idempotent on match_text).
            for (final a in aliases.asData?.value ?? const <IngredientAlias>[])
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final removed = await ref.writeOk(
                    context,
                    'remove that alias',
                    () => ref
                        .read(ingredientRepositoryProvider)
                        .removeAlias(a.id),
                  );
                  if (removed && context.mounted) {
                    ref.invalidate(ingredientAliasesProvider(ingredientId));
                  }
                },
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

/// "Counts as" — what a bare count of this row MEANS (seam **D1**, board
/// frame f).
///
/// The picker's first entry is **"Ask me each time"** (null), and that is the
/// honest state for a row whose measures are three different things
/// (broccoli: whole · spear · crown). Clearing a default is one tap and never
/// destroys a measure: the row keeps every label it had and only stops having
/// a preferred one.
///
/// It is a **stated fact**, so it saves the moment it is picked — like the
/// measures editor's own writes, not on this form's Save. A household owns
/// this from the moment its vocabulary is cloned; the seeded value is a
/// starting point, not a rule.
class _CountsAsRow extends ConsumerWidget {
  const _CountsAsRow({required this.ingredient, required this.measures});

  final Ingredient ingredient;
  final List<Measure> measures;

  /// The sentinel for "Ask me each time" — `FSelect`'s own null means "no
  /// selection", which is a different thing from "the household chose none".
  static const _ask = '';

  /// Writes the pick and re-reads the row. `ingredientById` is a one-shot
  /// Future, so nothing re-fires on its own — the same reason the measures
  /// editor's `piece` answer invalidates it.
  Future<void> _pick(BuildContext context, WidgetRef ref, String? id) async {
    final repo = ref.read(ingredientRepositoryProvider);
    await ref.write(
      context,
      'set what a count of this means',
      () => repo.setDefaultMeasure(
        ingredient.id,
        (id == null || id == _ask) ? null : id,
      ),
    );
    if (context.mounted) ref.invalidate(ingredientByIdProvider(ingredient.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byId = {for (final m in measures) m.id: m};
    final current = ingredient.defaultMeasureId;
    // A default whose measure this device has not synced (or that was
    // tombstoned elsewhere) reads as unset rather than as a phantom row.
    final selected = current != null && byId.containsKey(current)
        ? current
        : _ask;
    final one = ingredient.canonicalName.toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(child: Text('One $one is', style: ansiMono(size: 11))),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FSelect<String>.rich(
                format: (id) => id == _ask
                    ? '— not set'
                    : '${byId[id]?.label ?? '—'} · '
                          '${formatQuantity(byId[id]?.amount)} '
                          '${byId[id]?.basis.baseUnit.label ?? ''}',
                control: FSelectControl<String>.lifted(
                  value: selected,
                  onChange: (id) => unawaited(_pick(context, ref, id)),
                ),
                children: [
                  const FSelectItem(
                    title: Text('Ask me each time'),
                    value: _ask,
                  ),
                  for (final m in measures)
                    FSelectItem(
                      title: Text(
                        '${m.label} · ${formatQuantity(m.amount)} '
                        '${m.basis.baseUnit.label}',
                      ),
                      value: m.id,
                    ),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'used when a line says a number and no unit. A line that names '
            'something — “2 large onions” — always wins.',
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
        ),
      ],
    );
  }
}

// **Retired here: `_UsdaLookup`, `_LookupNote` and `_lookupStamp`.**
//
// The button ran `probe.probe` — ONE best candidate, applied sight-unseen —
// and reported the outcome in a status sentence, which is why **G3** had to
// own that sentence and stamp it with the row version so a later edit could
// retire it. `Fill it in from ▸ Look up in USDA` now opens the same
// five-candidate search that `Choose another ›` opens, so there is no
// automatic guess to narrate and no stale sentence to retire.
//
// **F1 goes with it.** The flush existed because the probe asked about the
// row's STORED name, so a rename sitting unsaved meant it asked about the old
// one. The search asks about the name in the FIELD, which cannot be stale —
// so nothing has to be written before you may look something up.
//
// `probe.probe` itself stays where an automatic best guess belongs: D7b's
// probe-at-birth and the server-side trigger. It is no longer a button.

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
/// child: it retires the moment a density lands, and in a `ListView` a child
/// that disappears shifts every sibling below it onto the wrong element —
/// silently resetting their hook state, which is how the lookup's own note
/// vanished exactly when it had good news.
///
/// **G6 — one line, computed.** It used to be three sentences, and the middle
/// one was wrong for a volume-default row: it named a family as locked from
/// the basis alone rather than from what is actually dashed below. It now
/// reads the same candidate list the chips do and names those units, or says
/// nothing at all when nothing is locked.
class _DensityGapNote extends StatelessWidget {
  const _DensityGapNote({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    if (ingredient.densityGPerMl != null) return const SizedBox.shrink();
    final locked = [
      for (final c in allowedUnitCandidates(ingredient))
        if (c.locked) c.unit.label,
    ];
    if (locked.isEmpty) return const SizedBox.shrink();
    return _Note('no density — ${locked.join(' · ')} locked');
  }
}

/// A field's micro-label, with the qualifier that used to be shouted beside
/// it demoted to [hint].
///
/// `ansiLabel` is letter-spaced uppercase mono — a style for a short noun.
/// Four of this form's labels had grown into whole sentences in it
/// ("MACROS — ENTER THEM AS THE LABEL READS"), one of which wrapped onto two
/// lines on a phone, and every one of them read at the same weight as the
/// group headings above them. The board already ruled this once, on the
/// density warning: *"why is the message an essay"*.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.hint});

  final String text;

  /// The sentence-case qualifier, or null. Same words as before, one weight
  /// down — the label says what the field is, this says how to read it.
  final String? hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: ansiLabel()),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              hint!,
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
      ],
    ),
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
  const _StatusStrip({required this.ingredient});

  final Ingredient ingredient;

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
              stub
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
/// Save, Confirm, "return it to a stub", "Look up in USDA" and Delete used to
/// be five affordances stacked in a column at the end of a very long page —
/// so the destructive one sat a flick below the confirm CTA, and neither of
/// the two that actually commit anything was reachable without scrolling to
/// the bottom. Two of the five moved to the header's `⋯`, one to the top of
/// the form, and these two stay where a CTA belongs.
///
/// **One row, not a stack.** Two full-width buttons is a wall, and
/// `Confirm — it counts from here` was a sentence pretending to be a label.
/// The promise moves up into [message] — which is the form's existing feedback
/// line, the same one that says "Saved.", "Still used by 3 recipes (4 lines)."
/// and "Filled from …" — leaving `Save` and `Mark complete` to share a row and
/// be ranked by width and colour instead of by stacking order.
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

/// "Counts as", as one slot (seam **D1**, board frame f) — the label and the
/// row together, or nothing at all on a row with no measures.
class _CountsAsSection extends StatelessWidget {
  const _CountsAsSection({required this.ingredient, required this.measures});

  final Ingredient ingredient;
  final List<Measure> measures;

  @override
  Widget build(BuildContext context) {
    if (measures.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('COUNTS AS', hint: 'what “2 onions” means'),
        _CountsAsRow(ingredient: ingredient, measures: measures),
      ],
    );
  }
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

/// The four macro inputs as typed text, so "half filled in" is a state the
/// form can name rather than a silent zero.
@immutable
class _MacroDraft {
  const _MacroDraft({
    required this.kcal,
    required this.protein,
    required this.carb,
    required this.fat,
  });

  factory _MacroDraft.from(Macros? m) => _MacroDraft(
    kcal: m == null ? '' : _trimZeros(m.kcal),
    protein: m == null ? '' : _trimZeros(m.protein),
    carb: m == null ? '' : _trimZeros(m.carb),
    fat: m == null ? '' : _trimZeros(m.fat),
  );

  final String kcal;
  final String protein;
  final String carb;
  final String fat;

  _MacroDraft copyWith({
    String? kcal,
    String? protein,
    String? carb,
    String? fat,
  }) => _MacroDraft(
    kcal: kcal ?? this.kcal,
    protein: protein ?? this.protein,
    carb: carb ?? this.carb,
    fat: fat ?? this.fat,
  );

  List<String> get _fields => [kcal, protein, carb, fat];

  // Value equality is load-bearing for G1: "the user has not touched these"
  // is the comparison between the live draft and the one the row last seeded.
  @override
  bool operator ==(Object other) =>
      other is _MacroDraft &&
      other.kcal == kcal &&
      other.protein == protein &&
      other.carb == carb &&
      other.fat == fat;

  @override
  int get hashCode => Object.hash(kcal, protein, carb, fat);

  bool get _allBlank => _fields.every((f) => f.trim().isEmpty);

  /// All four parse, or all four are blank. Anything between is a panel with
  /// a hole in it, which the form refuses rather than zero-filling.
  bool get isCoherent =>
      _allBlank ||
      _fields.every((f) => double.tryParse(f.trim())?.isFinite ?? false);

  /// The macros this draft asserts, or null for "none" — the D5 clear.
  Macros? toMacros() {
    if (_allBlank || !isCoherent) return null;
    return Macros(
      kcal: double.parse(kcal.trim()),
      protein: double.parse(protein.trim()),
      carb: double.parse(carb.trim()),
      fat: double.parse(fat.trim()),
    );
  }
}

// --- The M-D2 offer ----------------------------------------------------------

/// What a serving's name and weight also say about the row (plan 0027
/// M-D2): a density when the pack measured a spoon, a measure when it named
/// a thing. Computed, never written — the form writes it only when ticked.
sealed class ServingOffer {
  const ServingOffer();

  /// The tick's label: "1 tbsp weighs 14 g — set as density".
  String get sentence;

  /// The note under a taken tick: what Save will do with it.
  String get whenTaken;
}

/// "1 tbsp = 14 g" — a volume-named weight IS a density (ADR-0008 §2), so
/// it lands through the same `setDensity` the density entry's spoon phrasing
/// uses, and the volume chips unlock exactly as they would there (ADR-0009).
class DensityOffer extends ServingOffer {
  const DensityOffer({
    required this.unit,
    required this.gramsPerUnit,
    required this.gPerMl,
  });

  final Unit unit;
  final double gramsPerUnit;
  final double gPerMl;

  @override
  String get sentence =>
      '1 ${unit.label} weighs ${formatQuantity(gramsPerUnit)} g — set as '
      'density';

  @override
  String get whenTaken =>
      '= ${formatDensity(gPerMl)} g/ml, written with this Save through the '
      'density entry — the volume chips unlock as they do when a density is '
      'typed by hand';
}

/// "1 slice = 28 g" — a count-like human unit mapped into the basis
/// (ADR-0008 §3), added through the measures editor's own write.
class MeasureOffer extends ServingOffer {
  const MeasureOffer({
    required this.label,
    required this.amount,
    required this.basis,
  });

  final String label;

  /// In [basis]'s base unit — what `addMeasure` stores.
  final double amount;
  final MacrosBasis basis;

  @override
  String get sentence =>
      '1 $label = ${formatQuantity(amount)} ${basis.baseUnit.label} — add as '
      'a measure';

  @override
  String get whenTaken =>
      'lands in the measures below with this Save — rename it or bin it '
      'there';
}

/// The offer a serving row makes, or null when it makes none.
///
/// The name is read as an optional count and a word ("2 Tbsp", "slice").
/// A spoon word with a **mass** serving is a density — per spoon, so "2 Tbsp
/// = 32 g" offers 16 g a tablespoon; a spoon with an ml serving is a volume
/// of itself and offers nothing. Any other word is a measure of one — a
/// count above one would need a singular nobody typed ("2 slices"), so it
/// is not offered rather than guessed at.
ServingOffer? servingOfferFor(ServingDraft serving, MacrosBasis basis) {
  final amount = serving.amount;
  final name = serving.name.trim();
  if (amount == null || name.isEmpty) return null;
  final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s+(.+)$').firstMatch(name);
  final count = m == null
      ? 1.0
      : double.tryParse(m.group(1)!.replaceAll(',', '.'));
  final word = (m == null ? name : m.group(2)!).trim();
  if (count == null || !(count > 0) || word.isEmpty) return null;
  final volume = volumeUnitFromLabel(word);
  if (volume != null) {
    if (basis != MacrosBasis.perG) return null;
    final perUnit = amount / count;
    final gPerMl = densityFromVolumeWeight(volume, perUnit);
    if (gPerMl == null) return null;
    return DensityOffer(unit: volume, gramsPerUnit: perUnit, gPerMl: gPerMl);
  }
  if (count != 1) return null;
  return MeasureOffer(label: word, amount: amount, basis: basis);
}

/// `60` not `60.0`, `0.66` unchanged — seeds a numeric field with what a
/// person would have typed.
String _trimZeros(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
