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
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../books/presentation/text_prompt.dart';
import '../../recipes/presentation/format.dart';
import '../barcode/barcode_add.dart';
import '../data/ingredient_providers.dart';
import '../data/usda_enrichment.dart';
import '../domain/allowed_units.dart';
import '../domain/apply_draft.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/normalize.dart';
import 'density_entry.dart';
import 'draft_card.dart';
import 'measures_editor.dart';

/// The pushed route for one vocab row.
String ingredientDetailRoute(String id) => '/ingredients/$id';

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

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(
          ingredient?.canonicalName ?? 'Ingredient',
          style: ansiHeaderTitle(),
          overflow: TextOverflow.ellipsis,
        ),
        prefixes: [
          FHeaderAction.back(
            onPress: () => context.canPop()
                ? context.pop()
                : context.goOnce('/ingredients'),
          ),
        ],
      ),
      child: switch (async) {
        AsyncError(:final error) => _Centered('Could not open it — $error'),
        AsyncLoading() when ingredient == null => const _Centered('…'),
        _ when ingredient == null => const _Centered(
          'This ingredient is gone — it was deleted on another device.',
        ),
        _ => _DetailForm(
          // Keyed by id so pushing a different ingredient rebuilds the form
          // state instead of inheriting the previous row's typed values.
          key: ValueKey(ingredientId),
          ingredient: ingredient,
          lookup: lookup,
          cameraPane: cameraPane,
        ),
      },
    );
  }
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
    final allowed = useState(allowedUnitsFor(ing).toSet());
    final message = useState<String?>(null);
    // The USDA lookup's status note, owned HERE rather than inside the button
    // (plan 0020 **G3**): one piece of state, stamped with the row it was
    // written about, so a later change to that row retires it instead of
    // leaving a superseded sentence under a banner that has moved on.
    final lookupNote = useState<_LookupNote?>(null);
    final busy = useState(false);
    // Set when the measures editor refused a volume-named label and handed
    // back the resolved spoon — the density entry pre-picks it (F2: one
    // shared editor, so the redirect works here exactly as in the sheet).
    final redirectedSpoon = useState<Unit?>(null);
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

    // The row as the FORM currently reads it: the stored facts with the two
    // draft choices the D4c admission rule turns on — the default unit and
    // the macros basis — folded in. Every "what may this row say" question
    // below asks this rather than the stored row, so flipping the basis chip
    // moves the locks and the flag with it instead of leaving them answering
    // for a row nobody is looking at.
    final draftRow = ingredient.copyWith(
      defaultUnit: defaultUnit.value,
      macrosBasis: basis.value,
    );

    // A density write lands through the repository and re-renders this screen
    // via the watched provider; the local allowed-set follows both ways, so
    // the chips never lag the number they are derived from (D4b). Saving one
    // unions what it unlocks; deleting one strips it again, which is the only
    // place this list shrinks.
    final densityValue = ing.densityGPerMl;
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
      return null;
    }, [rowMacros]);

    // G3's other half: the lookup note is about ONE version of the row, and
    // anything that moves the row on — a confirm, an unconfirm, a density
    // landing, another device's write arriving — makes it a stale sentence.
    // Retiring it here means there is exactly one place that decides, rather
    // than a note the button forgot to clear.
    final stamp = _lookupStamp(ing);
    useEffect(() {
      if (lookupNote.value != null && lookupNote.value!.forStamp != stamp) {
        lookupNote.value = null;
      }
      return null;
    }, [stamp]);

    // A `complete` row is one whose macros the household stands behind — the
    // form's own draft is what the CTA acts on, so the gate reads the draft.
    final draftMacros = macros.value.toMacros();
    final stub = ing.status == IngredientStatus.stub;

    Future<Ingredient?> save() async {
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
      busy.value = true;
      try {
        // The keepAlive repo provider, not a throwaway notifier: this
        // survives the await.
        //
        // Wrapped in a record so the guard's own "it threw" null stays
        // distinct from the repository's "the row is gone" null: a failed
        // write must not be reported as a deleted ingredient.
        final outcome = await ref.write(
          context,
          'save ${ing.canonicalName}',
          () async => (
            row: await ref
                .read(ingredientRepositoryProvider)
                .saveEdit(
                  ing.id,
                  IngredientEdit(
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
                ),
          ),
        );
        if (outcome == null || !context.mounted) return null;
        final saved = outcome.row;
        pendingSource.value = null; // stamped now, or the row is gone
        ref.invalidate(ingredientByIdProvider(ing.id));
        message.value = saved == null ? 'It is no longer here.' : 'Saved.';
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
      }
      if (applied.source != null) pendingSource.value = applied.source;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
      children: [
        // A SLOT, not a conditional child. A lookup that succeeds turns this
        // banner on, and an unkeyed insertion at the top of a ListView shifts
        // every sibling by one — which reconciles each of them against the
        // wrong element and silently resets its hook state, including the
        // note the lookup just wrote. Keeping the position occupied keeps the
        // rest of the form aligned.
        if (stub && isUsdaPrefilled(ing.source))
          const _PrefillBanner()
        else
          const SizedBox.shrink(),

        // Two more slots, for the same reason: the scan door, and the card
        // its draft lands on. Offered on a stub only — a confirmed row has
        // nothing empty for a label to fill, and its numbers are a human's.
        if (stub)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _GhostButton(
              label: 'Scan a barcode to fill this in',
              onTap: busy.value ? null : scan,
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

        const _Label('CATEGORY · DEFAULT UNIT'),
        _CategoryPicker(
          selected: category.value,
          onPick: (c) => category.value = c,
        ),
        const SizedBox(height: 8),
        _UnitChoiceRow(
          // Keyed so a test can ask this row — and only this row — which of
          // its chips D4c has locked.
          key: const ValueKey('default-unit-row'),
          ingredient: draftRow,
          selected: defaultUnit.value,
          onPick: (u) {
            defaultUnit.value = u;
            // Only an admissible unit can be tapped (D4c locks the rest), so
            // admitting the pick can never strand the row.
            allowed.value = {...allowed.value, u};
          },
        ),
        // D4c: a stored default the rules no longer support — a cup default
        // on a per-100 g row with no density. Flagged with its repair rather
        // than rewritten: how a household buys a thing is not ours to edit.
        _StrandedDefaultNote(
          ingredient: draftRow,
          onFix: () async {
            final fix = basisDefaultUnitFix(draftRow);
            defaultUnit.value = fix;
            allowed.value = {...allowed.value, fix};
            await save();
          },
        ),

        const _Label('MACROS — ENTER THEM AS THE LABEL READS'),
        Row(
          children: [
            AnsiModeChip(
              label: 'per 100 g',
              selected: basis.value == MacrosBasis.perG,
              onTap: () => basis.value = MacrosBasis.perG,
            ),
            const SizedBox(width: 6),
            AnsiModeChip(
              label: 'per 100 ml',
              selected: basis.value == MacrosBasis.perMl,
              onTap: () => basis.value = MacrosBasis.perMl,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // The key is the row-version (G1): it changes only when the row's own
        // macros were re-seeded into the draft above, and that is exactly when
        // the four controllers need rebuilding around their new text.
        _MacroFields(
          key: ValueKey('macro-fields-${macroSeed.value}'),
          draft: macros.value,
          onChanged: (d) => macros.value = d,
        ),

        const _Label('DENSITY — OPTIONAL, EITHER WAY, ONE STORED FACT'),
        DensityEntry(
          ingredient: ing,
          redirectedSpoon: redirectedSpoon.value,
          onSaved: (_) {
            redirectedSpoon.value = null;
            ref.invalidate(ingredientByIdProvider(ing.id));
          },
        ),
        _DensityGapNote(ingredient: draftRow),

        const _Label('ALLOWED UNITS — WHAT A LINE MAY SAY'),
        _AdmissionChips(
          ingredient: draftRow,
          selected: allowed.value,
          onToggle: (u) {
            final next = {...allowed.value};
            if (!next.remove(u)) next.add(u);
            allowed.value = next;
          },
        ),

        const _Label('MEASURES — COUNT-LIKE, IN THE BASIS'),
        // Load-bearing emptiness (D6): an errored measures stream rendered as
        // `const []` hides rows that exist, and this form's next Save would
        // then write the narrowed set back. So the error is a state, not a
        // fact about the ingredient.
        if (measuresAsync case AsyncError(:final error, :final stackTrace))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: AnsiErrorState(
              compact: true,
              what: 'the measures',
              error: error,
              stackTrace: stackTrace,
              onRetry: () => ref.invalidate(ingredientMeasuresProvider(ing.id)),
            ),
          )
        else
          MeasuresEditor(
            ingredient: ing,
            measures: measuresAsync.asData?.value ?? const [],
            onDelete: (m) => ref.write(
              context,
              'delete that measure',
              () => ref.read(measureRepositoryProvider).softDeleteMeasure(m.id),
            ),
            // Nothing here selects a measure — the form is not a quantity
            // entry surface; the watched provider re-renders the list.
            onAdded: (_) {},
            // A volume-named label is a density in disguise (ADR-0008 §2); the
            // editor refuses it and the density section above pre-picks that
            // spoon, which is the whole point of sharing one widget.
            onVolumeLabel: (u) => redirectedSpoon.value = u,
            // The piece question wrote `allowed_units` straight through the
            // repository, so the chips above must follow in the same breath —
            // otherwise this form's next Save would put `piece` back from a
            // draft made before the question was asked.
            onIngredientChanged: (updated) {
              allowed.value = allowedUnitsFor(updated).toSet();
              ref.invalidate(ingredientByIdProvider(ing.id));
            },
          ),

        // Seam D1's UI (board frame f): what a bare count of this row MEANS.
        // It sits with the measures because it is a fact ABOUT them, and it
        // is hidden entirely on a row that has none — there is nothing to
        // choose and nothing to ask.
        if ((measuresAsync.asData?.value ?? const []).isNotEmpty) ...[
          const _Label('COUNTS AS — WHAT “2 ONIONS” MEANS'),
          _CountsAsRow(ingredient: ing, measures: measuresAsync.asData!.value),
        ],

        const _Label('IMPRECISE UNITS'),
        _ImpreciseLine(ingredient: ing),

        const SizedBox(height: 20),
        _StatusLine(ingredient: ing),

        // Also a slot, for the same reason the banner above is one: saving
        // sets this message, and a spread that grows from zero children to
        // two would shift everything below it — including the lookup
        // section, whose note would vanish the moment it had something to
        // say.
        _FormMessage(text: message.value),

        const SizedBox(height: 12),
        FButton(onPress: busy.value ? null : save, child: const Text('Save')),

        const SizedBox(height: 10),
        if (stub)
          _ConfirmCta(
            enabled: !busy.value && draftMacros != null,
            onConfirm: () async {
              final saved = await save();
              if (saved == null || !context.mounted) return;
              final confirmed = await ref.writeOk(
                context,
                'confirm ${ing.canonicalName}',
                () =>
                    ref.read(ingredientRepositoryProvider).confirmStub(ing.id),
              );
              if (!confirmed || !context.mounted) return;
              ref.invalidate(ingredientByIdProvider(ing.id));
              message.value = 'Confirmed — it counts from here.';
            },
          )
        else
          _UnconfirmAction(
            onUnconfirm: () async {
              final undone = await ref.writeOk(
                context,
                'unconfirm ${ing.canonicalName}',
                () => ref.read(ingredientRepositoryProvider).unconfirm(ing.id),
              );
              if (!undone || !context.mounted) return;
              ref.invalidate(ingredientByIdProvider(ing.id));
              message.value =
                  'Back to a stub — it stops counting until you '
                  'confirm it again.';
            },
          ),

        const SizedBox(height: 12),
        // F1: the button flushes the form's pending edits before it probes,
        // so a rename typed and not yet saved is the name USDA is asked
        // about — the exact flow that failed on the owner's device. A slot
        // again, so that landing a density (which retires the note above)
        // cannot shift this section and wipe what it just said.
        if (stub)
          _UsdaLookup(
            ingredient: ing,
            flush: save,
            note: lookupNote.value?.text,
            onStatus: (text, about) => lookupNote.value = _LookupNote(
              text,
              _lookupStamp(about ?? ing),
            ),
          )
        else
          const SizedBox.shrink(),

        const SizedBox(height: 24),
        _DeleteAction(ingredient: ing),
      ],
    );
  }
}

// --- Sections ----------------------------------------------------------------

/// Frame (c)'s "Filled in for you — check it" banner. Shown only where the
/// numbers are a machine's guess and nobody has confirmed them yet (D1/D5).
class _PrefillBanner extends StatelessWidget {
  const _PrefillBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
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
              const Icon(
                FLucideIcons.triangleAlert,
                size: 13,
                color: AnsiColors.aging,
              ),
              const SizedBox(width: 6),
              Text(
                'Filled in for you — check it',
                style: ansiSans(size: 13, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '· USDA FoodData Central matched this name on the server.\n'
            '· Nothing counts until you confirm.',
            style: ansiMono(size: 10, color: AnsiColors.muted),
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
              hint: label,
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

/// The ADR-0008 admission section, finally built: selected chips, unselected
/// but admissible chips, and the dashed locked ones a density would open.
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
    final candidates = allowedUnitCandidates(
      ingredient,
    ).where((c) => c.unit.family != UnitFamily.imprecise).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in candidates)
              _UnitChip(
                unit: c.unit,
                selected: selected.contains(c.unit),
                locked: c.locked,
                onTap: () => onToggle(c.unit),
              ),
          ],
        ),
        if (candidates.any((c) => c.locked))
          _Note(
            'dashed chips need a density — the '
            '${_crossFamilyWord(ingredient)} side is the density’s to give',
          ),
      ],
    );
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({
    required this.unit,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final Unit unit;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return DashedBorderBox(
        color: AnsiColors.line,
        child: Text(
          unit.label,
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
      );
    }
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 6,
        children: [
          for (final u in kAllUnits)
            AnsiModeChip(
              label: u.label,
              selected: u == selected,
              // A stranded stored default still renders as the selection —
              // it is the truth about the row, and the note below it is how
              // it gets fixed.
              enabled: unitSayableAsDefault(ingredient, u) || u == selected,
              onTap: () => onPick(u),
            ),
        ],
      ),
    );
  }
}

/// **D4c(c)** — the row whose stored default unit its own rules no longer
/// support: `cup` on a per-100 g row with no density (the renamed-rice shape
/// the owner hit). Never rewritten silently; named, with the one tap that
/// repairs it.
class _StrandedDefaultNote extends StatelessWidget {
  const _StrandedDefaultNote({required this.ingredient, required this.onFix});

  final Ingredient ingredient;
  final Future<void> Function() onFix;

  @override
  Widget build(BuildContext context) {
    if (!defaultUnitNeedsDensity(ingredient)) return const SizedBox.shrink();
    final fix = basisDefaultUnitFix(ingredient);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ingredient.defaultUnit.label} needs a density on this row — '
            'enter one below, or:',
            style: ansiMono(size: 10, color: AnsiColors.gone),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              size: FButtonSizeVariant.sm,
              variant: FButtonVariant.outline,
              onPress: onFix,
              child: Text('switch default to ${fix.label}'),
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

/// Which imprecise words this row admits — gated per word by category
/// (ADR-0008 §5 as tightened by plan 0020 J3: pinch and dash for the
/// spice/seasoning/oil classes, handful for greens). A fact about the
/// category, not a switch on this form, so it is read out rather than offered.
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

class _ImpreciseLine extends StatelessWidget {
  const _ImpreciseLine({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    final words = impreciseUnitsFor(ingredient).map((u) => u.label).join(' · ');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Imprecise units', style: ansiMono(size: 11)),
        // Flexible, never a Spacer: the word list grows and a Row cannot give
        // room it has not got (the G2 lesson).
        Flexible(
          child: Text(
            words.isEmpty ? 'none — category-gated' : words,
            textAlign: TextAlign.right,
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
        ),
      ],
    );
  }
}

/// The frame's status line: what this row is doing to everyone's totals.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    final stub = ingredient.status == IngredientStatus.stub;
    return Row(
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
    );
  }
}

/// "Confirm — it counts from here". Gated on macros (D5): density is not
/// required, and the disabled state says why rather than going quiet.
class _ConfirmCta extends StatelessWidget {
  const _ConfirmCta({required this.enabled, required this.onConfirm});

  final bool enabled;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FButton(
          onPress: enabled ? onConfirm : null,
          child: const Text('Confirm — it counts from here'),
        ),
        if (!enabled) const _Note('needs macros'),
      ],
    );
  }
}

/// Confirm is reversible (D5) — the row's macros stay, it just stops
/// counting.
class _UnconfirmAction extends StatelessWidget {
  const _UnconfirmAction({required this.onUnconfirm});

  final Future<void> Function() onUnconfirm;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onUnconfirm,
      child: Text(
        'return it to a stub',
        style: ansiMono(size: 11, color: AnsiColors.muted),
      ),
    );
  }
}

/// D7's manual half, rebuilt for **D7b**: a real probe, not a re-read.
///
/// `usda_food` still never syncs to a device (ADR-0005), so the app cannot
/// search it — but since migration 0016 it can *ask* the server for one
/// candidate through a read-only RPC and apply the answer locally. The button
/// used to re-read the row and report whether the sync round trip had
/// finished, which is a truthful description of doing nothing.
///
/// **F1 — it flushes first.** The failing flow the owner found was
/// rename-then-lookup on a saved stub: the rename sat unsaved in the form
/// while the button probed the OLD name. So the button saves any pending
/// edits, then probes under the name that is now stored. That is also why the
/// helper copy names what the wait is — an RPC round trip, not a sync one.
class _UsdaLookup extends HookConsumerWidget {
  const _UsdaLookup({
    required this.ingredient,
    required this.flush,
    required this.note,
    required this.onStatus,
  });

  final Ingredient ingredient;

  /// Saves the form's pending edits and returns the stored row (null when the
  /// save was refused or the row is gone). Called before every probe: a
  /// lookup that reads a name the user has already changed is the F1 bug.
  final Future<Ingredient?> Function() flush;

  /// The status to show, or null for none. Held by the form (**G3**) — this
  /// widget reports outcomes and renders what it is given, so there is one
  /// answer to "what does the lookup currently say" and one place that
  /// retires it.
  final String? note;

  /// Reports a new status and the row it is about — the stored row after the
  /// flush, or the enriched row after an apply. The form stamps the note with
  /// that version, so a later change to the row supersedes it.
  final void Function(String text, Ingredient? about) onStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = useState(false);

    Future<void> lookUp() async {
      busy.value = true;
      onStatus('Saving, then asking USDA…', null);
      try {
        final saved = await flush();
        if (!context.mounted) return;
        if (saved == null) {
          onStatus(
            'Save this form first — the lookup asks about the stored name.',
            null,
          );
          return;
        }
        final result = await enrichFromUsda(
          saved,
          probe: ref.read(usdaProbeProvider),
          repository: ref.read(ingredientRepositoryProvider),
        );
        if (!context.mounted) return;
        ref.invalidate(ingredientByIdProvider(ingredient.id));
        // Stamped against the row the outcome is ABOUT: the enriched row when
        // one was written, otherwise the row as the flush left it. Reporting
        // the pre-lookup row would retire the note the instant its own write
        // arrived.
        // G6's trim reaches here too: the banner above already says "check
        // it / nothing counts until you confirm", so the note says what
        // happened and stops. What survives is what only this sentence can
        // tell you — the name that was asked about, and the offline fallback.
        onStatus(switch (result.outcome) {
          UsdaEnrichment.applied => 'USDA FoodData Central filled this in.',
          UsdaEnrichment.nothingToCopy =>
            'USDA has that name but no numbers for it — fill it in by hand.',
          // Offline and "no confident match" are one state on purpose: the
          // user cannot act differently on them, and the server trigger
          // re-runs the same probe when this row uploads either way. Never a
          // dialog for a network miss.
          UsdaEnrichment.noAnswer =>
            'Nothing came back for “${saved.canonicalName}” — if you are '
                'offline, the server runs the same lookup when this row syncs '
                'up.',
          UsdaEnrichment.notBare =>
            'Nothing to fill in — this row already has numbers.',
        }, result.row ?? saved);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GhostButton(
          label: busy.value ? 'Looking up…' : 'Look up in USDA',
          onTap: busy.value ? null : lookUp,
        ),
        if (note != null) _Note(note!),
      ],
    );
  }
}

/// A lookup status and the row version it was written about (**G3**).
///
/// The stamp is deliberately narrow — the facts a lookup status can talk
/// about, and nothing else — so an unrelated edit (a category, a measure)
/// does not wipe a note that is still true.
class _LookupNote {
  const _LookupNote(this.text, this.forStamp);

  final String text;
  final String forStamp;
}

/// The row version a lookup status is pinned to.
String _lookupStamp(Ingredient i) => [
  i.canonicalName,
  i.status.name,
  i.source ?? '',
  i.densityGPerMl?.toString() ?? '',
  i.macros?.toString() ?? '',
].join('|');

/// Delete, guarded. The refusal is the interesting state: it names the count,
/// because "used by 3 recipes" is a thing a user can act on and "failed" is
/// not.
class _DeleteAction extends HookConsumerWidget {
  const _DeleteAction({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refusal = useState<String?>(null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final outcome = await ref.write(
              context,
              'delete ${ingredient.canonicalName}',
              () => ref
                  .read(ingredientRepositoryProvider)
                  .softDelete(ingredient.id),
            );
            if (outcome == null || !context.mounted) return;
            switch (outcome) {
              case Deleted():
                ref.invalidate(ingredientByIdProvider(ingredient.id));
                if (context.mounted) {
                  context.canPop()
                      ? context.pop()
                      : context.goOnce('/ingredients');
                }
              case DeleteRefused(:final recipeCount, :final lineCount):
                refusal.value =
                    'Still used by $recipeCount '
                    '${recipeCount == 1 ? 'recipe' : 'recipes'} '
                    '($lineCount ${lineCount == 1 ? 'line' : 'lines'}). '
                    'Change those lines first.';
              case DeleteMissing():
                refusal.value = 'It is already gone.';
            }
          },
          child: DashedBorderBox(
            color: AnsiColors.gone,
            child: Text(
              'Delete ingredient',
              textAlign: TextAlign.center,
              style: ansiMono(size: 12, color: AnsiColors.gone),
            ),
          ),
        ),
        if (refusal.value != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              refusal.value!,
              style: ansiMono(size: 11, color: AnsiColors.gone),
            ),
          ),
      ],
    );
  }
}

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

/// The form's save/confirm feedback line. Always in the tree so the children
/// below it keep their positions (and their hook state) when it appears.
class _FormMessage extends StatelessWidget {
  const _FormMessage({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text!, style: ansiMono(size: 11, color: AnsiColors.muted)),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(text, style: ansiLabel()),
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

/// The side a stored density admits and a deleted density takes back (D4b) —
/// the opposite of the basis family, which is always sayable (ADR-0008 §1).
String _crossFamilyWord(Ingredient ingredient) =>
    ingredient.macrosBasis == MacrosBasis.perMl ? 'weight' : 'volume';

/// `60` not `60.0`, `0.66` unchanged — seeds a numeric field with what a
/// person would have typed.
String _trimZeros(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
