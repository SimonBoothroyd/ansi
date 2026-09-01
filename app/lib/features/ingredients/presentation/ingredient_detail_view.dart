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
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../../../shared/dashed_border_box.dart';
import '../../books/presentation/text_prompt.dart';
import '../data/ingredient_providers.dart';
import '../data/usda_enrichment.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/normalize.dart';
import 'density_entry.dart';
import 'measures_editor.dart';

/// The pushed route for one vocab row.
String ingredientDetailRoute(String id) => '/ingredients/$id';

class IngredientDetailView extends ConsumerWidget {
  const IngredientDetailView({required this.ingredientId, super.key});

  final String ingredientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ingredientByIdProvider(ingredientId));
    final ingredient = async.asData?.value;

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(
          ingredient?.canonicalName ?? 'Ingredient',
          style: miseHeaderTitle(),
          overflow: TextOverflow.ellipsis,
        ),
        prefixes: [
          FHeaderAction.back(
            onPress: () =>
                context.canPop() ? context.pop() : context.go('/ingredients'),
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
        style: miseMono(size: 12, color: MiseColors.muted),
      ),
    ),
  );
}

class _DetailForm extends HookConsumerWidget {
  const _DetailForm({required this.ingredient, super.key});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ing = ingredient;
    final name = useState(ing.canonicalName);
    final category = useState(ing.category ?? '');
    final defaultUnit = useState(ing.defaultUnit);
    final basis = useState(ing.macrosBasis);
    final macros = useState<_MacroDraft>(_MacroDraft.from(ing.macros));
    final allowed = useState(allowedUnitsFor(ing).toSet());
    final message = useState<String?>(null);
    final busy = useState(false);
    // Set when the measures editor refused a volume-named label and handed
    // back the resolved spoon — the density entry pre-picks it (F2: one
    // shared editor, so the redirect works here exactly as in the sheet).
    final redirectedSpoon = useState<Unit?>(null);

    // A density write lands through the repository and re-renders this screen
    // via the watched provider; the local allowed-set follows both ways, so
    // the chips never lag the number they are derived from (D4b). Saving one
    // unions what it unlocks; deleting one strips it again, which is the only
    // place this list shrinks.
    final densityValue = ing.densityGPerMl;
    useEffect(() {
      final next = {...allowed.value};
      if (densityValue != null) {
        next.addAll(densityUnlockedUnits(ing));
      } else {
        next.removeAll(densityStrippedUnits(ing));
      }
      allowed.value = next;
      return null;
    }, [densityValue]);

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
        final saved = await ref
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
              ),
            );
        if (!context.mounted) return null;
        ref.invalidate(ingredientByIdProvider(ing.id));
        message.value = saved == null ? 'It is no longer here.' : 'Saved.';
        return saved;
      } finally {
        if (context.mounted) busy.value = false;
      }
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

        const _Label('CANONICAL NAME'),
        FTextField(
          control: FTextFieldControl.managed(
            initial: TextEditingValue(text: ing.canonicalName),
            onChange: (v) => name.value = v.text,
          ),
        ),
        const _Note(
          'renaming rewrites the match text — otherwise the next import '
          'searches for a name nothing carries',
        ),

        const _Label('ALSO KNOWN AS'),
        _AliasEditor(ingredientId: ing.id),

        const _Label('CATEGORY · DEFAULT UNIT'),
        _CategoryPicker(
          selected: category.value,
          onPick: (c) => category.value = c,
        ),
        const SizedBox(height: 8),
        _UnitChoiceRow(
          selected: defaultUnit.value,
          onPick: (u) {
            defaultUnit.value = u;
            // The default unit's own family is always sayable — keep the
            // chosen unit admitted rather than leaving a row whose default
            // its own allowed list forbids.
            allowed.value = {...allowed.value, u};
          },
        ),

        const _Label('MACROS — ENTER THEM AS THE LABEL READS'),
        Row(
          children: [
            MiseModeChip(
              label: 'per 100 g',
              selected: basis.value == MacrosBasis.perG,
              onTap: () => basis.value = MacrosBasis.perG,
            ),
            const SizedBox(width: 6),
            MiseModeChip(
              label: 'per 100 ml',
              selected: basis.value == MacrosBasis.perMl,
              onTap: () => basis.value = MacrosBasis.perMl,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _MacroFields(
          draft: macros.value,
          onChanged: (d) => macros.value = d,
          initial: ing.macros,
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
        _DensityGapNote(ingredient: ing),

        const _Label('ALLOWED UNITS — WHAT A LINE MAY SAY'),
        _AdmissionChips(
          ingredient: ing,
          selected: allowed.value,
          onToggle: (u) {
            final next = {...allowed.value};
            if (!next.remove(u)) next.add(u);
            allowed.value = next;
          },
        ),

        const _Label('MEASURES — COUNT-LIKE, IN THE BASIS'),
        MeasuresEditor(
          ingredient: ing,
          measures:
              ref.watch(ingredientMeasuresProvider(ing.id)).asData?.value ??
              const [],
          onDelete: (m) =>
              ref.read(measureRepositoryProvider).softDeleteMeasure(m.id),
          // Nothing here selects a measure — the form is not a quantity
          // entry surface; the watched provider re-renders the list.
          onAdded: (_) {},
          // A volume-named label is a density in disguise (ADR-0008 §2); the
          // editor refuses it and the density section above pre-picks that
          // spoon, which is the whole point of sharing one widget.
          onVolumeLabel: (u) => redirectedSpoon.value = u,
        ),

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
              await ref.read(ingredientRepositoryProvider).confirmStub(ing.id);
              if (!context.mounted) return;
              ref.invalidate(ingredientByIdProvider(ing.id));
              message.value = 'Confirmed — it counts from here.';
            },
          )
        else
          _UnconfirmAction(
            onUnconfirm: () async {
              await ref.read(ingredientRepositoryProvider).unconfirm(ing.id);
              if (!context.mounted) return;
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
          _UsdaLookup(ingredient: ing, flush: save)
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
        color: MiseColors.paper,
        border: Border.all(color: MiseColors.aging),
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
                color: MiseColors.aging,
              ),
              const SizedBox(width: 6),
              Text(
                'Filled in for you — check it',
                style: miseSans(size: 13, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '· USDA FoodData Central matched this name on the server.\n'
            '· Nothing counts until you confirm.',
            style: miseMono(size: 10, color: MiseColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The four macro inputs. All four or none — a partial panel would compute
/// totals out of numbers nobody supplied (invariant 3).
class _MacroFields extends StatelessWidget {
  const _MacroFields({
    required this.draft,
    required this.onChanged,
    required this.initial,
  });

  final _MacroDraft draft;
  final ValueChanged<_MacroDraft> onChanged;
  final Macros? initial;

  @override
  Widget build(BuildContext context) {
    Widget field(String label, String? seed, _MacroDraft Function(String) put) {
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
                initial: TextEditingValue(text: seed ?? ''),
                onChange: (v) => onChanged(put(v.text)),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: miseMono(size: 9, color: MiseColors.muted)),
          ],
        ),
      );
    }

    String? seed(double? v) => v == null ? null : _trimZeros(v);
    return Row(
      spacing: 6,
      children: [
        field('kcal', seed(initial?.kcal), (t) => draft.copyWith(kcal: t)),
        field(
          'protein',
          seed(initial?.protein),
          (t) => draft.copyWith(protein: t),
        ),
        field('carb', seed(initial?.carb), (t) => draft.copyWith(carb: t)),
        field('fat', seed(initial?.fat), (t) => draft.copyWith(fat: t)),
      ],
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
            'dashed chips need a density — the ${_basisFamilyWord(ingredient)} '
            'side is always yours to pick; the ${_crossFamilyWord(ingredient)} '
            'side is admitted by the density and stripped again if you delete '
            'it (ADR-0009, D4b)',
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
        color: MiseColors.line,
        child: Text(
          unit.label,
          style: miseMono(size: 11, color: MiseColors.muted),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? MiseColors.herbSoft : MiseColors.surface,
          border: Border.all(
            color: selected ? MiseColors.herb : MiseColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          unit.label,
          style: miseMono(
            size: 11,
            color: selected ? MiseColors.herbDeep : MiseColors.muted,
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
class _UnitChoiceRow extends StatelessWidget {
  const _UnitChoiceRow({required this.selected, required this.onPick});

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
            MiseModeChip(
              label: u.label,
              selected: u == selected,
              onTap: () => onPick(u),
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
      await ref
          .read(ingredientRepositoryProvider)
          .addAlias(ingredientId, draft.value);
      if (!context.mounted) return;
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
            for (final a in aliases.asData?.value ?? const <IngredientAlias>[])
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  await ref
                      .read(ingredientRepositoryProvider)
                      .removeAlias(a.id);
                  if (context.mounted) {
                    ref.invalidate(ingredientAliasesProvider(ingredientId));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: MiseColors.paper,
                    border: Border.all(color: MiseColors.line),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(a.text, style: miseMono(size: 11)),
                      const SizedBox(width: 5),
                      const Icon(
                        FLucideIcons.x,
                        size: 10,
                        color: MiseColors.muted,
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
                        color: MiseColors.herb,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'alias',
                        style: miseMono(size: 11, color: MiseColors.herb),
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
              style: miseMono(size: 10, color: MiseColors.gone),
            ),
          ),
      ],
    );
  }
}

/// Whether the imprecise tail is admitted — category-gated (ADR-0008 §5),
/// which is a fact about the category, not a switch on this form.
class _ImpreciseLine extends StatelessWidget {
  const _ImpreciseLine({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    final on =
        ingredient.defaultUnit.family == UnitFamily.imprecise ||
        kImpreciseGatedCategories.contains(ingredient.category);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('pinch · dash · to taste', style: miseMono(size: 11)),
        Text(
          on ? 'on — category-gated' : 'off — category-gated',
          style: miseMono(size: 10, color: MiseColors.muted),
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
            color: stub ? MiseColors.muted : MiseColors.fresh,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            stub
                ? 'Still a stub — left out of macro totals until confirmed.'
                : 'Complete — counts in conversions and macro totals.',
            style: miseMono(size: 11, color: MiseColors.muted),
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
        if (!enabled)
          const _Note(
            'needs macros — a row can’t count towards a total with numbers '
            'nobody supplied',
          ),
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
        style: miseMono(size: 11, color: MiseColors.muted),
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
  const _UsdaLookup({required this.ingredient, required this.flush});

  final Ingredient ingredient;

  /// Saves the form's pending edits and returns the stored row (null when the
  /// save was refused or the row is gone). Called before every probe: a
  /// lookup that reads a name the user has already changed is the F1 bug.
  final Future<Ingredient?> Function() flush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = useState<String?>(null);
    final busy = useState(false);

    Future<void> lookUp() async {
      busy.value = true;
      note.value = 'Saving, then asking USDA…';
      try {
        final saved = await flush();
        if (!context.mounted) return;
        if (saved == null) {
          note.value =
              'Save what is on this form first — the lookup asks '
              'about the name that is stored.';
          return;
        }
        final result = await enrichFromUsda(
          saved,
          probe: ref.read(usdaProbeProvider),
          repository: ref.read(ingredientRepositoryProvider),
        );
        if (!context.mounted) return;
        ref.invalidate(ingredientByIdProvider(ingredient.id));
        note.value = switch (result.outcome) {
          UsdaEnrichment.applied =>
            'USDA FoodData Central filled this in — check the numbers, then '
                'confirm. Nothing counts until you do.',
          UsdaEnrichment.nothingToCopy =>
            'USDA has a food by that name but no density and no panel for '
                'it. Fill it in by hand.',
          // Offline and "no confident match" are one state on purpose: the
          // user cannot act differently on them, and the server trigger
          // re-runs the same probe when this row uploads either way. Never a
          // dialog for a network miss.
          UsdaEnrichment.noAnswer =>
            'Nothing came back for “${saved.canonicalName}”. If you are '
                'offline the server runs the same lookup when this row syncs '
                'up. Renaming it asks again.',
          UsdaEnrichment.notBare =>
            'Nothing to fill in — this row already has numbers. A lookup only '
                'ever fills blanks, so it can’t overwrite what you entered.',
        };
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
        if (note.value != null) _Note(note.value!),
      ],
    );
  }
}

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
            final outcome = await ref
                .read(ingredientRepositoryProvider)
                .softDelete(ingredient.id);
            if (!context.mounted) return;
            switch (outcome) {
              case Deleted():
                ref.invalidate(ingredientByIdProvider(ingredient.id));
                if (context.mounted) {
                  context.canPop() ? context.pop() : context.go('/ingredients');
                }
              case DeleteRefused(:final recipeCount, :final lineCount):
                refusal.value =
                    'Still used by $recipeCount '
                    '${recipeCount == 1 ? 'recipe' : 'recipes'} '
                    '($lineCount ${lineCount == 1 ? 'line' : 'lines'}). '
                    'Change those lines first — a line’s ingredient is never '
                    'allowed to dangle.';
              case DeleteMissing():
                refusal.value = 'It is already gone.';
            }
          },
          child: DashedBorderBox(
            color: MiseColors.gone,
            child: Text(
              'Delete ingredient',
              textAlign: TextAlign.center,
              style: miseMono(size: 12, color: MiseColors.gone),
            ),
          ),
        ),
        if (refusal.value != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              refusal.value!,
              style: miseMono(size: 11, color: MiseColors.gone),
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
          border: Border.all(color: MiseColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: miseMono(
            size: 12,
            color: enabled ? MiseColors.ink : MiseColors.muted,
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
class _DensityGapNote extends StatelessWidget {
  const _DensityGapNote({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    if (ingredient.densityGPerMl != null) return const SizedBox.shrink();
    return _Note(
      'no density — the ${_crossFamilyWord(ingredient)} chips below stay '
      'locked; the ${_basisFamilyWord(ingredient)} ones never needed one. '
      'That blocks nothing: macros are what a row needs to count.',
    );
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
      child: Text(text!, style: miseMono(size: 11, color: MiseColors.muted)),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(text, style: miseLabel()),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(text, style: miseMono(size: 10, color: MiseColors.muted)),
  );
}

/// The four macro inputs as typed text, so "half filled in" is a state the
/// form can name rather than a silent zero.
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

/// The family the ingredient's macros are read in — per 100 g ⇒ weight, per
/// 100 ml ⇒ volume. D4b: this side of the admission editor is **always**
/// toggleable, because the canonical dimension is sayable with or without a
/// density (ADR-0008 §1).
String _basisFamilyWord(Ingredient ingredient) =>
    ingredient.macrosBasis == MacrosBasis.perMl ? 'volume' : 'weight';

/// The other side — the one a stored density admits and a deleted density
/// takes back (D4b).
String _crossFamilyWord(Ingredient ingredient) =>
    ingredient.macrosBasis == MacrosBasis.perMl ? 'weight' : 'volume';

/// `60` not `60.0`, `0.66` unchanged — seeds a numeric field with what a
/// person would have typed.
String _trimZeros(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';
