/// The quantity + unit-chip sheet for a **component** line (step 8.6 / D2,
/// design board frame d) — the 7.7 sheet's anatomy with batch math on the
/// chips.
///
/// Same dock, same [UnitChip]s, same live conversion line, same Optional row.
/// Three things differ, and each is a consequence of a component being a
/// recipe rather than an ingredient:
///
/// - the chips are **`batch` ∪ the yields' families**, kitchen-trimmed
///   ([componentUnitChips]) — `batch` is always sayable, and a family opens
///   only because the recipe states a yield in it. There is no density for a
///   recipe, so a family nobody stated is not offered; the fix is the yield's
///   optional second denomination, not a guess;
/// - the conversion line reads in batches ("0.25 cup = 0.25 of a batch ·
///   makes 1 cup"), and a recipe with no yield gets the *not-an-error* state:
///   the `batch` chip alone, the honest note, and one tap to go set the yield.
///   The link, the page and scaling all work meanwhile — only derived numbers
///   wait;
/// - there is **no `+` manage-measures chip**: a measure is an ingredient
///   concept ("potato, medium = 213 g" says nothing about a recipe), which is
///   the same reason a component line never carries a `measure_id`.
///
/// The 7.7 **stored-selection rule carries over**: an imported line's printed
/// unit is an admissible chip even when this sheet would not offer it, marked
/// as outside the filter and rendered with the honest unresolved line — never
/// silently rewritten.
///
/// **A MEASURED line is not re-denominated here.** A line said in one of the
/// target's own words — `3 blob` (ADR-0018) — has no catalog unit, and this
/// sheet's whole offer is catalog units: opened on such a line it would hand a
/// unit back, and the caller would write that unit where the word was. The word
/// is the only place its amount lived, so that is a silent, irreversible loss.
///
/// So while this build has no authoring control (`initialMeasureId` is the seam
/// for one), the sheet opened on a measured line offers **exactly that word**,
/// preselected and marked as the recipe's own, and hands back
/// [ComponentQuantity] with a **null `unit`** — "the number changed, the
/// denomination did not". The quantity is fully editable, which is the part a
/// cook actually wants to change; the word is the target recipe's to state, and
/// the door to it is that recipe's MEASURES list.
///
/// A line whose word has been RETIRED is measured too, and gets the same
/// treatment for a stronger reason: it has no honest denomination to show at
/// all, so a units-only sheet would not just replace the word, it would put a
/// confident `3 cup` where the app was correctly saying it did not know. The
/// chip row says the word has gone; the number stays editable and the pointer
/// stays put, so the repair is the target recipe's MEASURES, where it belongs.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/format.dart';
import '../../../shared/unit_chip.dart';
import '../domain/component_math.dart';
import '../domain/component_units.dart';
import '../domain/recipe.dart';
import 'component_format.dart';
import 'recipe_chip.dart';

/// What the component sheet resolved to: the amount, the unit it counts, and
/// whether the line is optional.
///
/// `unit` is **null exactly when the line keeps the denomination it arrived
/// with** — a measured line's own word, which this sheet does not offer to
/// replace. It is the same nullability `LineItem.unit` carries, and it means
/// the same thing: the amount is said in one of the target recipe's words
/// rather than in a catalog unit, so a caller must set the quantity and leave
/// the denomination alone.
typedef ComponentQuantity = ({double? quantity, Unit? unit, bool optional});

/// What the chip row says where the word would be, for a line whose word has
/// been retired. Not a unit and not a guess: the row's job here is to say that
/// the denomination is missing and inert, and the sentence under it says where
/// the word is put back.
const _kGoneWordChip = 'word gone';

/// Opens the component quantity sheet for [target]; resolves to the chosen
/// amount, or null if dismissed.
///
/// [onSetYield] is the deep link the no-yield state offers ("Set the yield").
/// Null where there is nowhere to send the user (a host with no router).
///
/// [initialMeasureId] is `LineItem.recipeMeasureId` — the pointer the line
/// actually carries. Pass it whenever the line has one: the word itself is
/// looked up on [target], because that is where it lives.
Future<ComponentQuantity?> showComponentQuantitySheet(
  BuildContext context, {
  required SubRecipeTarget target,
  double? initialQuantity,
  Unit? initialUnit,
  String? initialMeasureId,
  bool initialOptional = false,
  VoidCallback? onSetYield,
}) {
  return showAnsiSheet<ComponentQuantity>(
    context: context,
    builder: (sheetContext) => ComponentQuantityEditor(
      target: target,
      initialQuantity: initialQuantity,
      initialUnit: initialUnit,
      initialMeasureId: initialMeasureId,
      initialOptional: initialOptional,
      onSetYield: onSetYield == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              onSetYield();
            },
      onDone: (result) => Navigator.of(sheetContext).pop(result),
    ),
  );
}

class ComponentQuantityEditor extends HookWidget {
  const ComponentQuantityEditor({
    required this.target,
    required this.onDone,
    this.initialQuantity,
    this.initialUnit,
    this.initialMeasureId,
    this.initialOptional = false,
    this.onSetYield,
    super.key,
  });

  final SubRecipeTarget target;
  final double? initialQuantity;

  /// The line's stored unit — always an admissible chip (the 7.7 rule).
  final Unit? initialUnit;

  /// The line's `recipe_measure_id`, when it says one of the target's own
  /// words. Non-null is the whole condition the library doc describes: this
  /// sheet then keeps the denomination and edits only the number. The word
  /// itself is read off [target] — never joined onto the line, which is what
  /// makes a re-stated `blob` follow through everywhere at once.
  final String? initialMeasureId;

  /// Whether the line already says it may be left out.
  final bool initialOptional;

  final ValueChanged<ComponentQuantity> onDone;
  final VoidCallback? onSetYield;

  @override
  Widget build(BuildContext context) {
    final yields = target.yields;
    final measureId = initialMeasureId;
    // The LIVE word, off the target's own measures, never off the resolution: a
    // word can be perfectly alive and still unresolvable (a `makes` restated
    // into another family under it), and that line must read "3 blob —
    // unresolved — …" rather than a bare "3 — unresolved". Null means it has
    // gone, which the row says in as many words.
    final word = measureId == null
        ? null
        : recipeMeasureById(measureId, target.measures);
    final quantity = useState<double?>(initialQuantity);
    final unit = useState<Unit>(initialUnit ?? _defaultUnit(yields));
    final optional = useState<bool>(initialOptional);
    final offer = componentUnitChips(yields: yields, stored: initialUnit);

    final note = componentConversionLine(
      quantity: quantity.value,
      unit: measureId == null ? unit.value : null,
      yields: yields,
      recipeMeasureId: measureId,
      measures: target.measures,
    );

    return AnsiSheetShell(
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: RecipeChip(title: target.title, size: 16),
        ),
        const SizedBox(height: 4),
        Text(
          yields.isEmpty
              ? 'no yield set · your recipe'
              : '${yields.map(yieldText).join(' · ')} · your recipe',
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 16),
        Text('QUANTITY', style: ansiLabel()),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 132,
              child: FTextField(
                autofocus: true,
                hint: 'qty',
                // A TEXT keyboard, not the decimal pad: iOS's numeric pads
                // carry no `/`, so `1/2` could not be typed on one — and a
                // fraction is how a recipe says this number.
                keyboardType: TextInputType.text,
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(
                    text: formatQuantityIn(quantity.value, unit.value),
                  ),
                  onChange: (v) => quantity.value = parseAmount(v.text),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                // Nothing where the denomination was for a gone word: the
                // number is all this line honestly says.
                word?.label ?? (measureId == null ? unit.value.label : ''),
                style: ansiMono(size: 15, color: AnsiColors.herbDeep),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          note ??
              (yields.isEmpty ? 'no yield set — amounts in batches only' : ''),
          textAlign: TextAlign.center,
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: kUnitChipHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // A measured line's row is its own denomination alone:
                // selected, marked, and inert. Every other chip here is a
                // catalog unit, and tapping one would write it where the word
                // was — see the library doc.
                if (measureId != null)
                  UnitChip(
                    label: word?.label ?? _kGoneWordChip,
                    suffix: word != null
                        ? 'this recipe’s word'
                        : 'nothing to change it to',
                    selected: true,
                    onTap: () {},
                  )
                else
                  for (final u in offer.chips)
                    UnitChip(
                      label: u.label,
                      suffix: u == offer.offFilter ? 'not in filter' : null,
                      selected: unit.value == u,
                      onTap: () => unit.value = u,
                    ),
              ],
            ),
          ),
        ),
        if (measureId != null) ...[
          const SizedBox(height: 8),
          Text(
            word != null ? kMeasuredLineKeepsItsWord : kGoneWordKeepsItsPointer,
            textAlign: TextAlign.center,
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ],
        // The no-yield state is not an error state: the link, the page and
        // scaling all work: only the derived numbers wait, one tap away.
        if (yields.isEmpty && onSetYield != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSetYield,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AnsiColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Set the yield',
                textAlign: TextAlign.center,
                style: ansiMono(size: 12),
              ),
            ),
          ),
        ],
        // The Optional row is the ingredient sheet's, word for word: a
        // sub-recipe may be left out of a total exactly as a garnish may.
        const SizedBox(height: 14),
        FSwitch(
          label: Text('Optional', style: ansiSans(size: 15)),
          value: optional.value,
          onChange: (on) => optional.value = on,
        ),
        const SizedBox(height: 4),
        Text(
          'left out of macros and the shop list, and named where it left',
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 14),
        FButton(
          onPress: () => onDone((
            quantity: quantity.value,
            // Null for a measured line: the number changed, the denomination
            // did not. A unit here would be written where the word was.
            unit: measureId == null ? unit.value : null,
            optional: optional.value,
          )),
          child: const Text('Done'),
        ),
      ],
    );
  }

  /// Why a measured line's denomination is not on offer — one sentence, in the
  /// app's refusal voice: name the fact, and name where the fact is changed.
  static const kMeasuredLineKeepsItsWord =
      'This line is said in the recipe’s own word, so the number is yours to '
      'change and the word is that recipe’s — under its MEASURES.';

  /// The same sentence for a line whose word has been retired. It keeps its
  /// pointer rather than being handed a unit, because a unit here would be a
  /// number nobody stated where the app was honestly saying it did not know.
  static const kGoneWordKeepsItsPointer =
      'The word this line was written in is gone from that recipe, so there is '
      'nothing honest to count it in. The number is kept; put the word back '
      'under that recipe’s MEASURES.';

  /// What a fresh component line counts before anyone picks a chip: the
  /// yield's own unit when the recipe states one ("¼ cup" of a `makes 1 cup`
  /// aioli is the line a page prints), and `batch` otherwise — the one
  /// denomination that never needs a yield.
  static Unit _defaultUnit(List<YieldDenomination> yields) =>
      yields.isEmpty ? batches : yields.first.unit;
}
