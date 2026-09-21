/// The recipe header form, rendered by both the recipe editor and the import
/// review over their own draft through [RecipeHeaderHost].
///
/// Sections are declared once in [kRecipeHeaderSections]; a structural test
/// asserts both hosts show every one. Import-specific annotations go around the
/// form through [RecipeHeaderNotes].
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/text/name_clean.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../../../shared/amount_and_unit.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/ansi_stepper_row.dart';
import '../../../shared/format.dart';
import '../../../shared/inline_amount_field.dart';
import '../../../shared/write.dart';
import '../../books/data/book_providers.dart';
import '../../books/presentation/book_view_models.dart';
import '../../books/presentation/text_prompt.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';
import 'recipe_measure_delete.dart';
import 'recipe_measures_editor.dart';

/// The header's sections, each with the eyebrow it renders under.
enum RecipeHeaderSection {
  title('TITLE'),
  serves('SERVES'),
  makes('MAKES'),
  measures('MEASURES'),
  times('TIMES'),
  shelfLife('SHELF LIFE'),
  fileUnder('FILE UNDER');

  const RecipeHeaderSection(this.label);

  final String label;
}

/// The sections [RecipeHeaderForm] renders, in drawn order. TIMES follows MAKES
/// and the MEASURES that depend on it.
const kRecipeHeaderSections = RecipeHeaderSection.values;

/// What a host of the header form provides: the draft, and one setter per fact.
/// The rules behind each setter live in `RecipeHeaderEdits`.
abstract interface class RecipeHeaderHost {
  /// The draft the form renders — re-read on every build.
  Recipe get header;

  void setTitle(String title);
  void setServings(double servings);
  void setYield(double? qty, Unit? unit);
  void setSecondYield(double? qty, Unit? unit);

  /// Seats the recipe's MEASURES list. The rules are `withMeasures` and
  /// `authorRecipeMeasure`; the host keeps the list in the draft its Save lands
  /// (ADR-0011).
  void setMeasures(List<RecipeMeasure> measures);

  void setCookTime(int? seconds);
  void setTotalTime(int? seconds);
  void setKeepsForDays(int? days);
  // A positional bool tears off directly as the switch's `ValueChanged<bool>`.
  // ignore: avoid_positional_boolean_parameters
  void setFreezable(bool freezable);
  void setFreezerDays(int? days);
  void setBook(String bookId);
  void setSection(String? sectionId);
}

/// Per-section annotations a host draws around the shared form. The review uses
/// them to say what the page did or did not print.
class RecipeHeaderNotes {
  const RecipeHeaderNotes({
    this.besideServes,
    this.underMakes,
    this.afterMakes,
  });

  /// Beside the SERVES eyebrow, in the flag colour — "not printed — set it".
  final String? besideServes;

  /// Under the MAKES eyebrow, above the fields — "from source: …".
  final String? underMakes;

  /// After the MAKES fields — the honest empty-state hint when nothing was
  /// stated.
  final String? afterMakes;
}

class RecipeHeaderForm extends StatelessWidget {
  const RecipeHeaderForm({
    required this.host,
    this.notes = const RecipeHeaderNotes(),
    this.timeCaptions = true,
    this.sections = kRecipeHeaderSections,
    this.dense = false,
    super.key,
  });

  final RecipeHeaderHost host;
  final RecipeHeaderNotes notes;

  /// Whether the TIMES rows carry their one-line captions. Editor only.
  final bool timeCaptions;

  /// Which of [kRecipeHeaderSections] this instance draws, in order. All on a
  /// phone; the wide editor asks for them a cell at a time.
  final List<RecipeHeaderSection> sections;

  /// The wide header's compact cells: a short word beside (or above, see
  /// [_DenseRow]) a compact control, without the explanatory paragraphs.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final recipe = host.header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, section) in sections.indexed) ...[
          if (i > 0) const SizedBox(height: 20),
          _section(section, recipe),
        ],
      ],
    );
  }

  Widget _section(RecipeHeaderSection section, Recipe recipe) =>
      switch (section) {
        RecipeHeaderSection.title => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnsiMicroLabel(section.label),
            _TitleField(host: host),
          ],
        ),
        RecipeHeaderSection.serves => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnsiMicroLabel(
              section.label,
              suffix: notes.besideServes,
              suffixColor: AnsiColors.aging,
            ),
            _ServesStepper(
              servings: recipe.servingsBase,
              onChanged: host.setServings,
            ),
          ],
        ),
        RecipeHeaderSection.makes => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // "MAKES · optional" — the label the board's frame h draws, with
            // the optional half in sentence case beside the eyebrow.
            AnsiMicroLabel(section.label, suffix: '· optional'),
            if (notes.underMakes case final source?)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  source,
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
              ),
            _MakesSection(recipe: recipe, host: host, dense: dense),
            if (notes.afterMakes case final hint?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  hint,
                  style: ansiMono(size: 10, color: AnsiColors.muted),
                ),
              ),
          ],
        ),
        RecipeHeaderSection.measures => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnsiMicroLabel(
              section.label,
              suffix: '· optional · what you call one of these',
            ),
            _MeasuresSection(recipe: recipe, host: host),
          ],
        ),
        RecipeHeaderSection.times => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnsiMicroLabel(section.label),
            if (dense) ...[
              _MiniStepperRow(
                word: 'cook',
                value: recipe.cookTimeSeconds,
                step: 60,
                format: formatDuration,
                unsetText: 'not set',
                onChanged: host.setCookTime,
              ),
              const SizedBox(height: 7),
              _MiniStepperRow(
                word: 'total',
                value: recipe.totalTimeSeconds,
                step: 60,
                format: formatDuration,
                unsetText: 'not set',
                onChanged: host.setTotalTime,
              ),
            ] else ...[
              _StepperRow(
                label: 'Cook',
                caption: timeCaptions ? 'hands-on and on the heat' : null,
                value: recipe.cookTimeSeconds,
                step: 60,
                format: formatDuration,
                unsetText: 'not set',
                onChanged: host.setCookTime,
              ),
              const SizedBox(height: 8),
              _StepperRow(
                label: 'Total',
                caption: timeCaptions ? 'start to plate' : null,
                value: recipe.totalTimeSeconds,
                step: 60,
                format: formatDuration,
                unsetText: 'not set',
                onChanged: host.setTotalTime,
              ),
            ],
          ],
        ),
        RecipeHeaderSection.shelfLife => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnsiMicroLabel(section.label),
            if (dense)
              _DenseShelfLife(recipe: recipe, host: host)
            else
              _ShelfLifeSection(recipe: recipe, host: host),
          ],
        ),
        RecipeHeaderSection.fileUnder => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnsiMicroLabel(section.label),
            _FilingLine(recipe: recipe, host: host),
          ],
        ),
      };
}

/// The MAKES block: what one batch yields, in up to two denominations.
///
/// Independent of serves. The second denomination offers only the other unit
/// families and can be added only once the first is stated, matching the
/// database CHECK.
class _MakesSection extends HookWidget {
  const _MakesSection({
    required this.recipe,
    required this.host,
    this.dense = false,
  });

  final Recipe recipe;
  final RecipeHeaderHost host;

  /// See [RecipeHeaderForm.dense].
  final bool dense;

  /// The units a yield may be stated in: every ingredient-line unit except the
  /// imprecise ones. `batch` is excluded too.
  static final List<Unit> _units = [
    for (final u in kIngredientUnits)
      if (u.family != UnitFamily.imprecise) u,
  ];

  @override
  Widget build(BuildContext context) {
    final unit = useState<Unit>(recipe.yieldUnit ?? g);
    final unit2 = useState<Unit?>(recipe.yieldUnit2);
    final hasFirst = recipe.yieldQty != null && recipe.yieldUnit != null;
    final showSecond = recipe.yieldQty2 != null || unit2.value != null;

    // The second slot's offer: the other families only.
    final otherFamilies = [
      for (final u in _units)
        if (u.family != unit.value.family) u,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _YieldRow(
          key: const ValueKey('yield-1'),
          quantity: recipe.yieldQty,
          unit: unit.value,
          units: _units,
          onChanged: (qty, u) {
            unit.value = u;
            host.setYield(qty, u);
          },
        ),
        if (hasFirst && showSecond) ...[
          const SizedBox(height: 8),
          _YieldRow(
            key: const ValueKey('yield-2'),
            quantity: recipe.yieldQty2,
            unit: unit2.value ?? otherFamilies.first,
            units: otherFamilies,
            onRemove: () {
              unit2.value = null;
              host.setSecondYield(null, null);
            },
            onChanged: (qty, u) {
              unit2.value = u;
              host.setSecondYield(qty, u);
            },
          ),
          if (!dense)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'the second slot only offers the other families — two ways of '
                'saying one batch, never two numbers in one family',
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
            ),
        ] else if (hasFirst) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              prefix: const Icon(FLucideIcons.plus),
              onPress: () => unit2.value = otherFamilies.first,
              // The eyebrow overhead already says MAKES, and a quarter of the
              // wide cap does not hold the longer way of saying it.
              child: Text(dense ? 'Another' : 'Another denomination'),
            ),
          ),
        ],
      ],
    );
  }
}

/// The MEASURES list, under the MAKES it depends on (ADR-0018).
///
/// A word typed here rides the draft's [Recipe.measures] through the host's
/// Save, so a yield restated in the same sitting re-evaluates the words
/// immediately. The delete gate is the host's ([mayDeleteRecipeMeasure]): a
/// word lines still say cannot go.
class _MeasuresSection extends ConsumerWidget {
  const _MeasuresSection({required this.recipe, required this.host});

  final Recipe recipe;
  final RecipeHeaderHost host;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RecipeMeasuresEditor(
    recipeId: recipe.id,
    yields: recipe.yields,
    measures: recipe.measures,
    // The tap only puts the word in the draft — the docked Save lands it.
    addLabel: 'Add',
    // Nothing is written here, and the authoring rules have already run inside
    // the editor against this same draft, so there is nothing left to refuse.
    onAdd: (word) async {
      host.setMeasures([...host.header.measures, word]);
      return RecipeMeasureLanded(word);
    },
    // A re-statement keeps the row's id, so lines already saying the word
    // follow it.
    onRestate: (word) async {
      host.setMeasures([
        for (final m in host.header.measures)
          if (m.id == word.id) word else m,
      ]);
      return RecipeMeasureLanded(word);
    },
    // The refusal happens HERE rather than at Save: a draft that quietly kept a
    // row it said it had removed would be lying about what the Save will do.
    onDelete: (word) async {
      if (!await mayDeleteRecipeMeasure(context, ref, word)) return;
      host.setMeasures([
        for (final m in host.header.measures)
          if (m.id != word.id) m,
      ]);
    },
  );
}

/// One "amount + unit" yield row ([AmountAndUnitField]), with the second slot's
/// remove affordance. The remove glyph is sized to the control, not Forui's
/// touch default, so it does not set the row's height.
class _YieldRow extends StatelessWidget {
  const _YieldRow({
    required this.quantity,
    required this.unit,
    required this.units,
    required this.onChanged,
    this.onRemove,
    super.key,
  });

  final double? quantity;
  final Unit unit;
  final List<Unit> units;
  final void Function(double? quantity, Unit unit) onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AmountAndUnitField(
          amountWidth: 64,
          amount: formatQuantityIn(quantity, unit),
          unit: unit,
          units: units,
          onAmount: (t) =>
              onChanged(t.trim().isEmpty ? null : parseAmount(t), unit),
          onUnit: (u) => onChanged(quantity, u),
        ),
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          // Forui's default icon button is a 44 pt touch target, which beside
          // a 32 pt control sets the row's height on its own.
          FButton.icon(
            variant: FButtonVariant.ghost,
            size: FButtonSizeVariant.xs,
            style: const FButtonStyleDelta.delta(
              iconContentStyle: FButtonIconContentStyleDelta.delta(
                constraints: BoxConstraints.tightFor(
                  width: kInlineControlHeight,
                  height: kInlineControlHeight,
                ),
              ),
            ),
            onPress: onRemove,
            child: const Icon(FLucideIcons.x),
          ),
        ],
      ],
    );
  }
}

/// The recipe's title, tidied by [cleanName] (trim, collapse spaces, Title
/// Case) when the field is left; the editor's Save is the backstop. The tidied
/// text is pushed into the field's existing controller.
class _TitleField extends HookWidget {
  const _TitleField({required this.host});

  final RecipeHeaderHost host;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: host.header.title);
    final voice = ansiSerifDelta(size: AnsiType.row);
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) return;
        final cleaned = cleanName(host.header.title, NameKind.title);
        if (cleaned == host.header.title) return;
        host.setTitle(cleaned);
        controller.text = cleaned;
      },
      child: FTextField(
        key: const ValueKey('recipe-title'),
        hint: 'e.g. Weeknight Chicken Curry',
        // The title is set in the face it is read in elsewhere; Forui's default
        // field is the interface sans.
        style: FTextFieldStyleDelta.delta(
          contentTextStyle: FVariantsDelta.delta([
            FVariantOperation.all(voice),
          ]),
          hintTextStyle: FVariantsDelta.delta([FVariantOperation.all(voice)]),
        ),
        control: FTextFieldControl.managed(
          controller: controller,
          onChange: (v) => host.setTitle(v.text),
        ),
      ),
    );
  }
}

class _ServesStepper extends StatelessWidget {
  const _ServesStepper({required this.servings, required this.onChanged});

  final double servings;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnsiStepperRow(
      onDecrement: servings > 1 ? () => onChanged(servings - 1) : null,
      onIncrement: () => onChanged(servings + 1),
      value: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Text(
          formatQuantity(servings),
          style: ansiMono(size: 18, weight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// The shelf-life inputs: fridge days (drives cook-plan clustering), whether it
/// freezes, and the freezer window. Unset fridge days means the cook plan never
/// splits the recipe.
class _ShelfLifeSection extends StatelessWidget {
  const _ShelfLifeSection({required this.recipe, required this.host});

  final Recipe recipe;
  final RecipeHeaderHost host;

  static String _days(int value) => '$value ${plural(value, 'day')}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepperRow(
          label: 'Keeps in the fridge',
          value: recipe.keepsForDays,
          format: _days,
          unsetText: 'not set',
          onChanged: host.setKeepsForDays,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Drives the batch cook plan — how far apart the same dish can be '
            'planned before it becomes two things to cook.',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ),
        const SizedBox(height: 14),
        FSwitch(
          label: Text('Freezes', style: ansiSans(size: 15)),
          value: recipe.freezable,
          onChange: host.setFreezable,
        ),
        if (recipe.freezable) ...[
          const SizedBox(height: 12),
          _StepperRow(
            label: 'Keeps in the freezer',
            value: recipe.freezerDays,
            format: _days,
            unsetText: 'no limit',
            onChanged: host.setFreezerDays,
          ),
        ],
      ],
    );
  }
}

/// The wide header's SHELF LIFE cell: the same two facts without the
/// explanatory paragraph.
class _DenseShelfLife extends StatelessWidget {
  const _DenseShelfLife({required this.recipe, required this.host});

  final Recipe recipe;
  final RecipeHeaderHost host;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _MiniStepperRow(
        word: 'fridge',
        value: recipe.keepsForDays,
        format: _ShelfLifeSection._days,
        unsetText: 'not set',
        onChanged: host.setKeepsForDays,
      ),
      const SizedBox(height: 7),
      _DenseRow(
        word: 'freezes',
        control: FSwitch(value: recipe.freezable, onChange: host.setFreezable),
      ),
      if (recipe.freezable) ...[
        const SizedBox(height: 7),
        _MiniStepperRow(
          word: 'freezer',
          value: recipe.freezerDays,
          format: _ShelfLifeSection._days,
          unsetText: 'no limit',
          onChanged: host.setFreezerDays,
        ),
      ],
    ],
  );
}

/// Every word a wide header cell puts beside a control. The label column is
/// measured over all of them so controls align across cells.
const _kDenseWords = ['cook', 'total', 'fridge', 'freezes', 'freezer'];

/// The measured label column, cached per text scale because the header rebuilds
/// on every title keystroke.
final _denseWordColumns = <TextScaler, double>{};

/// A dense cell's label column width: the widest of [_kDenseWords] at
/// [ansiLabel] and the reader's text scale. Measured, because a fixed width
/// breaks words when the type scale or word list moves.
double _denseWordColumn(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return _denseWordColumns.putIfAbsent(scaler, () {
    var widest = 0.0;
    for (final word in _kDenseWords) {
      final painter = TextPainter(
        text: TextSpan(text: word.toUpperCase(), style: ansiLabel()),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    // Up to the whole pixel: a column a fraction short of the word it holds is
    // the same clipped word, drawn to look like a rounding error.
    return widest.ceilToDouble();
  });
}

/// One fact in a wide header cell: the word, then its control. A [Wrap], so
/// when the pair is wider than the cell the control moves down a line and the
/// word never breaks.
class _DenseRow extends StatelessWidget {
  const _DenseRow({required this.word, required this.control});

  final String word;

  /// The stepper or switch this fact is set with — the shipped control.
  final Widget control;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 9,
    runSpacing: 3,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: _denseWordColumn(context),
        child: Text(
          word.toUpperCase(),
          style: ansiLabel(),
          softWrap: false,
          maxLines: 1,
        ),
      ),
      control,
    ],
  );
}

/// One fact in a wide header cell: the word, then [AnsiStepperRow] in its small
/// size.
class _MiniStepperRow extends StatelessWidget {
  const _MiniStepperRow({
    required this.word,
    required this.value,
    required this.format,
    required this.unsetText,
    required this.onChanged,
    this.step = 1,
  });

  final String word;
  final int? value;
  final int step;
  final String Function(int value) format;
  final String unsetText;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return _DenseRow(
      word: word,
      control: AnsiStepperRow(
        small: true,
        onDecrement: value == null
            ? null
            : () => onChanged(value <= step ? null : value - step),
        onIncrement: () => onChanged((value ?? 0) + step),
        value: SizedBox(
          width: 74,
          child: Text(
            value == null ? unsetText : format(value),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: value == null
                ? ansiMono(size: 12, color: AnsiColors.muted)
                : ansiMono(size: 13.5, weight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// A label with a nullable stepper over an integer fact (days, or seconds
/// stepped a minute at a time). Stepping below one [step] clears the value
/// ([unsetText]); stepping up from unset starts at one [step].
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.format,
    required this.unsetText,
    required this.onChanged,
    this.caption,
    this.step = 1,
  });

  final String label;

  /// The one-line explainer under the label, when the host wants one.
  final String? caption;
  final int? value;
  final int step;
  final String Function(int value) format;
  final String unsetText;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return AnsiStepperRow(
      leading: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: ansiSans(size: 15)),
            if (caption case final caption?)
              Text(caption, style: ansiMono(size: 10, color: AnsiColors.muted)),
          ],
        ),
      ),
      onDecrement: value == null
          ? null
          : () => onChanged(value <= step ? null : value - step),
      onIncrement: () => onChanged((value ?? 0) + step),
      value: SizedBox(
        width: 100,
        child: Text(
          value == null ? unsetText : format(value),
          textAlign: TextAlign.center,
          style: value == null
              ? ansiMono(size: 13, color: AnsiColors.muted)
              : ansiMono(size: 15, weight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Where the recipe is filed, as one line that opens the picker. Worded like
/// the recipe page's `BOOK · SECTION` eyebrow.
class _FilingLine extends ConsumerWidget {
  const _FilingLine({required this.recipe, required this.host});

  final Recipe recipe;
  final RecipeHeaderHost host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // With no books there is nothing to file into, and `ensureDefaultBook`
    // means that cannot persist.
    final books = ref.watch(libraryProvider).asData?.value ?? const [];
    if (books.isEmpty) return const SizedBox.shrink();

    final book = books.firstWhere(
      (b) => b.id == (recipe.bookId ?? books.first.id),
      orElse: () => books.first,
    );
    final section = book.sections
        .where((s) => s.id == recipe.sectionId)
        .firstOrNull;
    final crumb = '${book.name} · ${section?.name ?? 'Unsectioned'}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_showFilingSheet(context, recipe, host)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AnsiColors.surface,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  crumb.toUpperCase(),
                  style: ansiLabel(color: AnsiColors.herb),
                ),
              ),
              Text(
                'change',
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
              const SizedBox(width: 4),
              const Icon(
                FLucideIcons.chevronRight,
                size: 14,
                color: AnsiColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picker, on the root navigator so it covers the tab bar like every other
/// sheet the app opens.
Future<void> _showFilingSheet(
  BuildContext context,
  Recipe recipe,
  RecipeHeaderHost host,
) => showAnsiSheet<void>(
  context: context,
  builder: (_) => AnsiSheetShell(
    title: 'File under',
    dismiss: AnsiSheetDismiss.none,
    children: [
      const SizedBox(height: 16),
      _FilingPicker(recipe: recipe, host: host),
    ],
  ),
);

/// Picks the book and section. The section list follows the chosen book, plus
/// "Unsectioned" (value `''`) and a "+" that creates a section inline.
class _FilingPicker extends ConsumerWidget {
  const _FilingPicker({required this.recipe, required this.host});

  final Recipe recipe;
  final RecipeHeaderHost host;

  static const _unsectioned = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No books shows nothing to file into; `ensureDefaultBook` keeps that state
    // from persisting.
    final books = ref.watch(libraryProvider).asData?.value ?? const [];
    if (books.isEmpty) return const SizedBox.shrink();

    final currentBookId = recipe.bookId ?? books.first.id;
    final currentBook = books.firstWhere(
      (b) => b.id == currentBookId,
      orElse: () => books.first,
    );
    final bookNames = {for (final b in books) b.id: b.name};
    final sectionNames = {for (final s in currentBook.sections) s.id: s.name};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FSelect<String>.rich(
          format: (id) => bookNames[id] ?? '—',
          control: FSelectControl<String>.lifted(
            value: currentBookId,
            onChange: (id) {
              if (id != null) host.setBook(id);
            },
          ),
          children: [
            for (final b in books)
              FSelectItem(title: Text(b.name), value: b.id),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FSelect<String>.rich(
                format: (id) => id == _unsectioned
                    ? 'Unsectioned'
                    : (sectionNames[id] ?? 'Unsectioned'),
                control: FSelectControl<String>.lifted(
                  value: recipe.sectionId ?? _unsectioned,
                  onChange: (id) => host.setSection(
                    (id == null || id == _unsectioned) ? null : id,
                  ),
                ),
                children: [
                  const FSelectItem(
                    title: Text('Unsectioned'),
                    value: _unsectioned,
                  ),
                  for (final s in currentBook.sections)
                    FSelectItem(title: Text(s.name), value: s.id),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FButton.icon(
              variant: FButtonVariant.secondary,
              onPress: () async {
                // The prompt's keyboard can unmount this row before Add is
                // tapped, so the write goes through handles that outlive it
                // (`hostContextOf`).
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final overlay = hostContextOf(context);
                final name = await promptForText(
                  context,
                  title: 'New section',
                  hint: 'Name it anything',
                  confirm: 'Add',
                  clean: NameKind.title,
                );
                if (name == null || name.trim().isEmpty) return;
                final id = await container.write(
                  overlay,
                  'add that section',
                  () => container
                      .read(bookRepositoryProvider)
                      .createSection(currentBookId, name),
                );
                // Selecting a section that was never created would file the
                // recipe under an id the server has never heard of.
                if (id != null) host.setSection(id);
              },
              child: const Icon(FLucideIcons.plus),
            ),
          ],
        ),
      ],
    );
  }
}
