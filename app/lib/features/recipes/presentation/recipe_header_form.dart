/// The recipe header — one form, two hosts (board frames a and b).
///
/// TITLE · SERVES · MAKES · TIMES · SHELF LIFE · FILE UNDER, in that order,
/// declared once in [kRecipeHeaderSections] and iterated here. The recipe
/// editor and the import review both render this widget over their own
/// draft through [RecipeHeaderHost]; a structural test asserts that both hosts
/// show every section, so the next one added cannot silently miss the review
/// — which is how the review came to lack shelf life in the first place.
///
/// What is import-specific is drawn *around* the form, never inside a copy of
/// it: [RecipeHeaderNotes] is the slot for the review's per-section honesty
/// ("not printed — set it" beside SERVES, "from source: …" under MAKES). The
/// editor supplies none.
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

/// The header's sections, each with the eyebrow it renders under.
enum RecipeHeaderSection {
  title('TITLE'),
  serves('SERVES'),
  makes('MAKES'),
  times('TIMES'),
  shelfLife('SHELF LIFE'),
  fileUnder('FILE UNDER');

  const RecipeHeaderSection(this.label);

  final String label;
}

/// The sections [RecipeHeaderForm] renders, in the drawn order. TIMES sits
/// after MAKES so the three numbers about the dish read together before the
/// two facts about keeping it.
const kRecipeHeaderSections = RecipeHeaderSection.values;

/// What a host of the header form must provide: the draft as it stands, and
/// one setter per fact. The rules behind each setter (both halves of a yield
/// or neither, no freezer window on a dish that does not freeze…) live in
/// `RecipeHeaderEdits`, so a host is only where the result is kept.
abstract interface class RecipeHeaderHost {
  /// The draft the form renders — re-read on every build.
  Recipe get header;

  void setTitle(String title);
  void setServings(double servings);
  void setYield(double? qty, Unit? unit);
  void setSecondYield(double? qty, Unit? unit);
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

/// Per-section annotations a host draws around the shared form (frame b) — a
/// slot, not a fork. The review fills these with what only it knows: whether
/// the page printed a serving count, and what it said about the yield.
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

  /// Whether the TIMES rows carry their one-line captions ("hands-on and on
  /// the heat" / "start to plate"). Drawn on the editor only (frame a); the
  /// review is dense enough already (frame b).
  final bool timeCaptions;

  /// Which of [kRecipeHeaderSections] this instance draws, in order.
  ///
  /// All six on a phone, where the header is one column. The wide editor folds
  /// the same six onto two rows — the title over the lines, the filing over
  /// the method, then the four small facts across the cap — by asking for them
  /// a cell at a time. It is the same form either way: a cell is a slice of
  /// the section list, never a second control.
  final List<RecipeHeaderSection> sections;

  /// The wide header's four cells: a quarter of the cap is not a column, so
  /// each fact states itself with the row's own short word and the compact
  /// stepper, and the paragraphs that explain a control to a first-time
  /// reader are left to the phone's one-column form.
  ///
  /// The word sits beside its control where the cell holds both and on the line
  /// above it where it does not — see [_DenseRow]. Never inside the word.
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

/// The MAKES numbers block (step 8.6 / D2 · D9, design board frame h): what
/// one batch yields, in up to TWO denominations.
///
/// Serves and makes are two independent facts — serves is how the recipe
/// portions, makes is how much comes out — and neither derives from the other.
/// The second denomination's selector offers only the OTHER families: two ways
/// of saying one batch ("makes 250 g · 16 tbsp"), never two numbers in one
/// family. It can only be added once the first is stated, which is what the
/// migration's CHECK says too — a save must not be able to bounce off it.
class _MakesSection extends HookWidget {
  const _MakesSection({
    required this.recipe,
    required this.host,
    this.dense = false,
  });

  final Recipe recipe;
  final RecipeHeaderHost host;

  /// See [RecipeHeaderForm.dense] — a quarter of the wide cap holds the two
  /// yield rows and the door between them, and not the paragraph that explains
  /// the second slot's offer.
  final bool dense;

  /// The units a yield may be stated in: everything an ingredient line can say
  /// except the imprecise words — "makes a pinch" is not a yield, and `batch`
  /// is what a yield is measured *against*, never in.
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

/// One "amount + unit" yield row, with the second slot's remove affordance.
///
/// The pair is [AmountAndUnitField] — the same control the density, the piece
/// weight, a measure's amount and the serving use, so a number with a unit is
/// stated the same way wherever it is stated. The remove glyph is sized to
/// the control rather than to Forui's touch default: the row is a sentence,
/// and a 44 pt button beside a 32 pt control sets its height on its own.
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

/// The recipe's title, tidied when the field is left.
///
/// [cleanName] trims it, collapses its spaces and Title Cases it — no word
/// ever changes, only its case, which is why there is nothing to tell and no
/// revert line here. The editor's Save is the backstop for a field that was
/// never left.
///
/// The host owns the text and the controller follows it: the tidied title is
/// pushed into the controller the field already has, rather than the field
/// being replaced around a fresh one.
class _TitleField extends HookWidget {
  const _TitleField({required this.host});

  final RecipeHeaderHost host;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: host.header.title);
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

/// The shelf-life inputs that make a recipe batchable (step 5): how long it
/// keeps in the fridge (drives cook-plan clustering), whether it freezes, and
/// the freezer window. Fridge days unset ⇒ the cook plan never splits it.
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

/// The wide header's SHELF LIFE cell: the same two facts, each with the row's
/// own short word beside the control.
///
/// The paragraph that says what fridge days drive is not here — it explains a
/// control to somebody meeting it, and a quarter of the cap is where somebody
/// who already knows changes a number. The phone's form still carries it.
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

/// Every word a wide header cell puts beside a control.
///
/// The label column is measured over the whole family rather than over the
/// row's own word, so the two-fact cells start their controls on one axis — and
/// so a word added here widens the column instead of breaking inside itself.
const _kDenseWords = ['cook', 'total', 'fridge', 'freezes', 'freezer'];

/// The measured label column, per text scale. Measuring is cheap but the header
/// rebuilds on every keystroke in the title field, and the answer only ever
/// changes when the reader's type size does.
final _denseWordColumns = <TextScaler, double>{};

/// How wide a dense cell's label column is: the widest of [_kDenseWords] at
/// [ansiLabel], at the reader's own text scale.
///
/// Measured, never guessed. A column guessed at 40 px held COOK and broke
/// TOTAL, FRIDGE, FREEZES and FREEZER inside themselves at every expanded
/// width — the bug this replaces — and a guess would break again the first
/// time the type scale, the tracking or the word list moved.
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

/// One fact in a wide header cell: the word, then the control that sets it —
/// beside it where a quarter of the cap holds both, on the line under it where
/// it does not.
///
/// A [Wrap] rather than a [Row] because the word is the part that must not
/// give: it is drawn at its measured width and never breaks inside itself, so
/// when the pair is wider than the cell the *control* moves down a line. That
/// is the fold from 1024 to 1063, where the rail's 64 px leave the cell 216
/// and the pair wants 220. The four cells stay on one row at every expanded
/// width either way, and the stepper keeps its buttons at their touch size,
/// which is the trade the broken word was silently making instead.
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

/// One fact in a wide header cell: the word, then the compact stepper.
///
/// The same [AnsiStepperRow] the phone's row uses, in its small size — a
/// quarter of the cap does not hold a sentence, two 44 pt buttons and a
/// hundred-pixel reading.
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

/// A label with a nullable stepper over an integer fact — days for the
/// shelf-life rows, seconds stepped a minute at a time for TIMES. Stepping
/// below one [step] clears the value (rendered as [unsetText]); stepping up
/// from unset starts at one [step].
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

/// Where the recipe is filed, as ONE LINE that opens the picker.
///
/// The door that opened this screen usually knows the answer already — a
/// section's `＋` carries `?book=&section=` — so the line states a fact rather
/// than asking a question. It stays a control, because two creation doors have
/// no shelf to inherit (the Week picker's `＋ new recipe`, and the no-hits
/// state, where a live query has replaced the tree) and because this same form
/// renders for every EXISTING recipe, where it is the filing you came to
/// change.
///
/// The words are the recipe page's own eyebrow — `BOOK · SECTION` in herb
/// caps — so the editor states filing exactly as the reader already saw it.
class _FilingLine extends ConsumerWidget {
  const _FilingLine({required this.recipe, required this.host});

  final Recipe recipe;
  final RecipeHeaderHost host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same weighed emptiness the picker had (D6): with no books there is
    // nothing to file into, and `ensureDefaultBook` means that cannot persist.
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

/// Picks the book + section the recipe is filed under. Book choices come from
/// the Library; the section list follows the chosen book, plus an "Unsectioned"
/// option (value `''`) and a "+" that creates a new section inline.
class _FilingPicker extends ConsumerWidget {
  const _FilingPicker({required this.recipe, required this.host});

  final Recipe recipe;
  final RecipeHeaderHost host;

  static const _unsectioned = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Decorative emptiness, weighed (D6): with no books the filing picker
    // shows nothing to file into, which is exactly what a household with no
    // books sees — and `ensureDefaultBook` means that state cannot persist.
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
                // The prompt's keyboard shrinks the editor's list, so this
                // row can be unmounted by the time Add is tapped: the write
                // goes through handles that outlive it (`hostContextOf`).
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
