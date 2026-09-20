/// The recipe editor — create (`recipeId == null`) or edit an existing recipe.
///
/// Fields are uncontrolled (`initial` + `onChange`) and every repeating child
/// is keyed by its stable domain id, so the notifier rebuilding the tree on
/// each edit never resets a controller or moves the caret.
///
/// The ingredient list is **one flat reorderable list**: a heading row starts
/// each group and the line rows after it belong to it, so dragging a line
/// under another heading files it there. Reordering a line and moving it
/// between groups are the same gesture, and a moved line keeps its id — which
/// is what keeps every method chip pointing at it.
///
/// **At [AnsiLayout.expanded] the same form is two columns** under one header:
/// the lines left in the row grammar they already have, the method right as
/// the same step cards, capped and centred like the recipe page — the page and
/// the editor are the same recipe, so they measure the same. Nothing is
/// re-drawn for the width: the rows, the chips, the cards, the step cards and
/// all five doors are the phone's, laid out beside each other instead of under
/// each other, and the list is still ONE reorderable list.
///
/// What the width buys is a single relationship: while a step has focus, every
/// line its chips point at wears the Shop pane's selected-row wash and the chip
/// the caret is inside is ringed, so a chip is written, read back and repaired
/// without scrolling between the two. It follows **focus**, never the pointer —
/// a hover-only link is a target that is not drawn — it is view state that is
/// never stored, and a resting editor lights nothing.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/reorder_grip.dart';
import '../../../shared/write.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../domain/line_display.dart';
import '../domain/method_draft.dart';
import '../domain/recipe.dart';
import '../domain/recipe_measure_repository.dart';
import 'component_format.dart';
import 'component_quantity_sheet.dart';
import 'ingredient_line.dart';
import 'line_card.dart';
import 'line_target_picker.dart';
import 'method_editor.dart';
import 'recipe_chip.dart';
import 'recipe_header_form.dart';
import 'recipe_view_models.dart';

/// The query parameter that asks a NEW recipe's editor to hand the recipe
/// back instead of landing on its page. One name, one place, so the route the
/// picker writes and the route the router reads agree.
const kHandBackQueryParam = 'handback';

/// The pushed route for a sub-recipe that does not exist yet — what a line
/// target picker opens when the thing the line wants has not been written.
///
/// [title] prefills the field with the words already typed into the picker's
/// search, and the editor pops with the saved recipe as a [SubRecipeTarget]
/// (or null if the person backed out) so the line waiting on it can be made.
String newSubRecipeRoute({String title = ''}) {
  final name = title.trim();
  final seed = name.isEmpty ? '' : 'title=${Uri.encodeQueryComponent(name)}&';
  return '/recipes/new?$seed$kHandBackQueryParam=1';
}

class RecipeEditorView extends ConsumerWidget {
  const RecipeEditorView({
    this.recipeId,
    this.initialTitle,
    this.initialBookId,
    this.initialSectionId,
    this.handsBackTarget = false,
    super.key,
  });

  final String? recipeId;

  /// Seeds a NEW recipe's title (`/recipes/new?title=…`) — the query the
  /// Library's "nothing matches" state was searched for. Ignored when
  /// [recipeId] is set: an existing recipe already has a title.
  final String? initialTitle;

  /// The shelf the door that opened this knew about (0028 E3) — a section's
  /// `＋` carries both; every other door carries neither.
  final String? initialBookId;
  final String? initialSectionId;

  /// Whether Save should POP with the recipe as a [SubRecipeTarget] rather
  /// than land on its page — true only for the picker door
  /// ([newSubRecipeRoute]), where a line is being held open for it.
  final bool handsBackTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = recipeEditorProvider(
      recipeId,
      initialTitle: initialTitle,
      initialBookId: initialBookId,
      initialSectionId: initialSectionId,
    );
    final async = ref.watch(editor);
    final notifier = ref.read(editor.notifier);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(
          recipeId == null ? 'New recipe' : 'Edit recipe',
          style: ansiHeaderTitle(),
        ),
        // Editing an existing recipe is a page over that recipe, so with
        // nothing under it — a pasted `/recipes/9/edit` — back belongs on the
        // recipe. A new recipe has no page of its own yet, so it belongs on
        // the Library.
        prefixes: [
          FHeaderAction.back(
            onPress: () => ansiBack(
              context,
              home: recipeId == null ? '/' : '/recipes/$recipeId',
            ),
          ),
        ],
        suffixes: [
          FButton(
            size: FButtonSizeVariant.sm,
            // Disabled until the draft has loaded — saving mid-load would hit
            // `state.requireValue` with nothing there.
            onPress: !async.hasValue
                ? null
                : () async {
                    // Both captured before the warning dialog, so the write
                    // still lands from handles the header cannot take with it.
                    final container = ProviderScope.containerOf(
                      context,
                      listen: false,
                    );
                    final host = hostContextOf(context);
                    if (!await _mayOrphanMeasures(context, notifier)) return;
                    // Through the write door: unguarded, a throw inside
                    // `save()` shows only as the editor not navigating, which
                    // reads as a laggy button rather than a lost recipe.
                    // The authoring rules' own refusals are caught instead of
                    // toasted, because each is a sentence about a word rather
                    // than a write that failed.
                    String? refused;
                    final saved = await container.write(
                      host,
                      'save the recipe',
                      () async {
                        try {
                          return await notifier.save();
                        } on RecipeMeasureRefused catch (e) {
                          refused = e.message;
                        } on RecipeMeasureInUse catch (e) {
                          refused = recipeMeasureDeleteRefusalText(
                            label: e.label,
                            lines: e.usage.lines,
                            recipes: e.usage.recipes.length,
                          );
                        }
                        return null;
                      },
                    );
                    if (refused case final said?) {
                      // The draft is untouched: nothing was written, and the
                      // sentence names the one thing to change.
                      await refuseAnsi(
                        // The host outlives the header — see [hostContextOf].
                        // ignore: use_build_context_synchronously
                        host.context,
                        title: 'That Save didn’t land',
                        body: said,
                      );
                      return;
                    }
                    if (saved == null || !context.mounted) return;
                    // Editing returns you to where you opened the editor;
                    // creating lands you on the thing you made. An existing
                    // recipe's page is already beneath the editor as a watched
                    // query, so a pop shows the save — replacing would stack a
                    // second copy of that page and cost a second back. A new
                    // recipe has only its opener beneath, so the editor is
                    // replaced (not `go`ne to: that would flatten the stack,
                    // back would leave the app and the iOS edge swipe would
                    // vanish on a page that looks exactly like a pushed one).
                    // …unless a picker pushed this to make a sub-recipe: that
                    // line is still open under the editor, and landing on the
                    // new recipe's page would abandon it.
                    if (recipeId != null) {
                      // Through the back helper, not a bare pop: an editor
                      // opened by a pasted link has nothing under it, and a
                      // Save that then threw left the recipe written and the
                      // person still in the form.
                      ansiBack(context, home: '/recipes/$recipeId');
                    } else if (handsBackTarget) {
                      ansiBack(
                        context,
                        home: '/recipes/${saved.id}',
                        result: saved.asSubRecipeTarget,
                      );
                    } else {
                      context.pushReplacement('/recipes/${saved.id}');
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
      child: async.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, st) => AnsiErrorState(
          what: 'the editor',
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(recipeEditorProvider(recipeId)),
        ),
        data: (recipe) => _EditorForm(recipe: recipe, notifier: notifier),
      ),
    );
  }
}

/// Asks before a Save that takes away the `makes` a live word stands on, and
/// returns whether to go on with it (ADR-0018 rule 4).
///
/// It **warns, never refuses**: what a batch makes is the recipe's own fact and
/// the household may restate it. Nothing is deleted either — the words survive
/// and every line saying one reads as unresolved until MAKES says that family
/// again — so the point of the question is only that nobody finds that out from
/// a broken line afterwards. A word already orphaned when the editor opened is
/// not re-reported: re-warning about a gap already on screen teaches a person
/// to dismiss the dialog.
Future<bool> _mayOrphanMeasures(
  BuildContext context,
  RecipeEditor notifier,
) async {
  final orphaned = notifier.measuresOrphanedBySave();
  if (orphaned.isEmpty) return true;
  return askAnsi(
    context,
    title:
        'Leave ${plural(orphaned.length, 'that word', plural: 'those words')} '
        'on nothing?',
    body: recipeMeasuresOrphanedWarning(orphaned),
    confirm: 'Save anyway',
    cancel: 'Keep editing',
  );
}

/// How wide the ingredients column is drawn at [AnsiLayout.expanded].
///
/// Fixed, and the one number the width does not give back: an 84 px amount, a
/// grip, a name and a note is what that row is, so at 1024 the 92 px the cap
/// loses all come out of the method column instead.
const double kEditorLinesColumn = 420;

/// The seam between the two columns — the recipe page's own.
const double kEditorColumnGap = 22;

class _EditorForm extends HookWidget {
  const _EditorForm({required this.recipe, required this.notifier});

  final Recipe recipe;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) {
    final wide = AnsiLayout.of(context) == AnsiLayout.expanded;
    // Bumped when a drag starts: every open line card closes, so what crosses
    // the list is a row like every other row rather than forms of wildly
    // different heights.
    final collapseEpoch = useState(0);
    // Which step has the caret. View state, never stored, and read only at
    // expanded — on a phone the lines it would light are a scroll away.
    final focusedStep = useState<String?>(null);
    final onStepFocus = useCallback((String stepId, {required bool focused}) {
      // A step losing focus clears the lighting only if it is the step that
      // set it: the loss and the next gain arrive in either order.
      if (focused) {
        focusedStep.value = stepId;
      } else if (focusedStep.value == stepId) {
        focusedStep.value = null;
      }
    }, const []);
    final lit = wide
        ? _litLines(notifier, focusedStep.value)
        : const <String>{};

    // ONE flat list per recipe: a heading row starts each group, and every
    // line row after it belongs to it. A line dropped under another heading is
    // filed under that heading, so reordering a line and moving it to another
    // group are one gesture rather than two features.
    final rows = <Widget>[];
    var lineCount = 0;
    for (final group in recipe.groups) {
      rows.add(
        _GroupHeading(
          key: ValueKey('group-${group.id}'),
          group: group,
          notifier: notifier,
          removable: recipe.groups.length > 1,
        ),
      );
      for (final item in group.items) {
        lineCount++;
        rows.add(
          _LineItemEditor(
            key: ValueKey('line-${item.id}'),
            item: item,
            recipeId: recipe.id,
            notifier: notifier,
            dragIndex: rows.length,
            collapseEpoch: collapseEpoch.value,
            lit: lit.contains(item.id),
          ),
        );
      }
    }

    final lines = SliverReorderableList(
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
      onReorderItem: notifier.moveLine,
      // An open card closes as soon as a drag begins.
      onReorderStart: (_) => collapseEpoch.value++,
      proxyDecorator: liftedRow,
    );
    final doors = _ListDoors(recipe: recipe, notifier: notifier, stacked: wide);
    final method = MethodEditor(
      recipe: recipe,
      notifier: notifier,
      onStepFocus: wide ? onStepFocus : null,
      ringsCaretChip: wide,
    );

    return CustomScrollView(
      // Once you start dragging the list you have finished typing, and a field
      // left focused off the top of the screen asks to be scrolled back to on
      // every keyboard metrics change — enough to throw the page to the title
      // while a line further down is being corrected.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: wide
          ? [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  ansiPageGutter,
                  8,
                  ansiPageGutter,
                  0,
                ),
                sliver: SliverList.list(
                  children: [_WideHeader(host: notifier)],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  ansiPageGutter,
                  20,
                  ansiPageGutter,
                  40,
                ),
                // One scroll, two columns — the recipe page's own shape, drawn
                // as slivers so the lines stay ONE reorderable list and a long
                // method's cards are still built lazily.
                sliver: SliverCrossAxisGroup(
                  slivers: [
                    SliverConstrainedCrossAxis(
                      maxExtent: kEditorLinesColumn,
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: EditorSectionHead(
                              label: 'INGREDIENTS',
                              count: _linesAndGroups(
                                lineCount,
                                recipe.groups.length,
                              ),
                            ),
                          ),
                          lines,
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: doors,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(left: kEditorColumnGap),
                      sliver: SliverList.list(children: [method]),
                    ),
                  ],
                ),
              ),
            ]
          : [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                // The header is the one the import review renders too: the
                // notifier is its host, so a section added there lands here
                // without a second copy.
                sliver: SliverList.list(
                  children: [RecipeHeaderForm(host: notifier)],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: lines,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                // A list rather than one box: the slivers stay lazy, so a long
                // method's step cards are not all built to show the top of the
                // page.
                sliver: SliverList.list(
                  children: [doors, const SizedBox(height: 28), method],
                ),
              ),
            ],
    );
  }
}

/// What the ingredients column's head says it holds — the frame's own words.
String _linesAndGroups(int lines, int groups) {
  final counted = '$lines ${plural(lines, 'line')}';
  return groups > 1 ? '$counted · $groups groups' : counted;
}

/// The lines the step with the caret points at.
///
/// Read off the draft rather than remembered, so a chip added, re-pointed or
/// removed while the step is being written changes what is lit on the same
/// keystroke. A step id the draft no longer has — the step was deleted while it
/// held focus — lights nothing.
Set<String> _litLines(RecipeEditor notifier, String? stepId) {
  if (stepId == null) return const {};
  for (final step in notifier.methodDraft()) {
    if (step.id != stepId) continue;
    return {
      for (final span in step.spans)
        if (span is RefSpan) ...span.refs,
    };
  }
  return const {};
}

/// The wide editor's header: the phone's seven sections in the phone's order,
/// folded onto three rows.
///
/// Row one sits on the columns' own axis — the title over the lines, the filing
/// over the method — so nothing in the editor is measured against a third grid.
/// Row two is the four small facts across the cap, each still the shipped
/// control: a header redrawn as bare lines would state the facts and take away
/// the steppers and the chip control that set them.
///
/// Row three is MEASURES, at the cap's full width. It is the one section that
/// is a LIST with a form under it — a label, an amount, its chip and a button —
/// and a quarter of the cap holds none of that. It stays directly under the
/// MAKES cell it depends on, which is the relationship it is placed for.
class _WideHeader extends StatelessWidget {
  const _WideHeader({required this.host});

  final RecipeHeaderHost host;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kEditorLinesColumn,
            child: RecipeHeaderForm(
              host: host,
              sections: const [RecipeHeaderSection.title],
            ),
          ),
          const SizedBox(width: kEditorColumnGap),
          Expanded(
            child: RecipeHeaderForm(
              host: host,
              sections: const [RecipeHeaderSection.fileUnder],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Container(height: 1, color: AnsiColors.line),
      const SizedBox(height: 15),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, section) in const [
            RecipeHeaderSection.serves,
            RecipeHeaderSection.makes,
            RecipeHeaderSection.times,
            RecipeHeaderSection.shelfLife,
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 18),
            Expanded(
              child: RecipeHeaderForm(
                host: host,
                sections: [section],
                dense: true,
                timeCaptions: false,
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
      RecipeHeaderForm(
        host: host,
        sections: const [RecipeHeaderSection.measures],
      ),
    ],
  );
}

/// The list's own two doors, tight under the last line — the review screen's
/// pair, in the editor's words. A line added lands in the LAST group, which is
/// what makes *Add group* then *Add ingredient* read as one gesture; the drag
/// then puts it wherever it belongs.
///
/// The same two doors in the wide editor, [stacked]: side by side they want
/// 544 and the ingredients column is 420, and a column that holds an amount, a
/// grip, a name and a note is not the thing to narrow for a pair of buttons.
class _ListDoors extends StatelessWidget {
  const _ListDoors({
    required this.recipe,
    required this.notifier,
    this.stacked = false,
  });

  final Recipe recipe;
  final RecipeEditor notifier;

  /// One door over the other, for the wide editor's 420 column.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final addLine = FButton(
      variant: FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      prefix: const Icon(FLucideIcons.plus),
      onPress: () => unawaited(
        addLineToGroup(
          context,
          group: recipe.groups.last,
          recipeId: recipe.id,
          notifier: notifier,
        ),
      ),
      child: const Text('Add ingredient'),
    );
    final addGroup = FButton(
      variant: FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      prefix: const Icon(FLucideIcons.plus),
      onPress: notifier.addGroup,
      child: const Text('Add group'),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [addLine, const SizedBox(height: 8), addGroup],
      );
    }
    return Row(
      children: [
        Expanded(child: addLine),
        const SizedBox(width: 8),
        Expanded(child: addGroup),
      ],
    );
  }
}

/// One group's heading row: the name as an editable field, and the bin.
///
/// It is a row of the same flat list the lines are in — which is what lets a
/// line be dropped under it. The heading itself does not drag: reordering
/// *groups* is a separate question, and a line moving between them is what was
/// asked for.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    required this.group,
    required this.notifier,
    required this.removable,
    super.key,
  });

  final IngredientGroup group;
  final RecipeEditor notifier;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: FTextField(
              hint: 'Group name (optional)',
              control: FTextFieldControl.managed(
                initial: TextEditingValue(text: group.name ?? ''),
                onChange: (v) => notifier.setGroupName(group.id, v.text),
              ),
            ),
          ),
          if (removable) ...[
            const SizedBox(width: 8),
            Semantics(
              label: 'Delete group',
              button: true,
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: () => notifier.removeGroup(group.id),
                child: const Icon(FLucideIcons.trash2, size: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The 7.7 two-step chain, with one more door at the first step (D7): the
/// picker (board frame c) → the quantity sheet (frame b for an ingredient,
/// frame d for a component) → the line lands fully quantified. Backing out of
/// the quantity sheet still adds the line in its default unit — the amount
/// cell re-opens the sheet.
Future<void> addLineToGroup(
  BuildContext context, {
  required IngredientGroup group,
  required String recipeId,
  required RecipeEditor notifier,
}) async {
  final name = group.name;
  // The picker's search brings the keyboard, which shrinks the editor's list
  // under it: the door can be unmounted by the time a row is tapped. The
  // second sheet opens from a context that outlives it (`hostContextOf`), and
  // [notifier] is the editor's own, kept alive by the page watching it — so
  // the line is added whatever became of the door. Never a `context.mounted`
  // bail here: it would drop the pick.
  final host = hostContextOf(context);
  final picked = await showLineTargetPicker(
    context,
    editingRecipeId: recipeId,
    title: name == null || name.isEmpty
        ? 'Add an ingredient'
        : 'Add to “$name”',
  );
  if (picked == null) return;
  switch (picked) {
    case PickedIngredient(:final ingredient):
      final result = await showQuantityUnitSheet(
        // The host outlives the row — see [hostContextOf].
        // ignore: use_build_context_synchronously
        host.context,
        ingredient: ingredient,
      );
      notifier.addLineItem(
        group.id,
        ingredient,
        quantity: result is QuantitySaved ? result.quantity : null,
        choice: result is QuantitySaved ? result.choice : null,
      );
    case PickedSubRecipe(:final target):
      final result = await showComponentQuantitySheet(
        // The host outlives the row — see [hostContextOf].
        // ignore: use_build_context_synchronously
        host.context,
        target: target,
        // A picked recipe is a stored one, so its words can be coined from
        // the dock — the ＋ writes them onto IT, not onto this recipe.
        mayCoinWords: true,
        onSetYield: () => host.context.pushOnce('/recipes/${target.id}/edit'),
      );
      notifier.addComponentLineItem(
        group.id,
        target,
        quantity: result?.quantity,
        unit: result?.unit,
        recipeMeasureId: result?.recipeMeasureId,
        // The word itself, because one coined behind the ＋ a tap ago is not
        // in the target the picker handed over.
        recipeMeasure: result?.measure,
        optional: result?.optional ?? false,
      );
  }
}

class _LineItemEditor extends ConsumerWidget {
  const _LineItemEditor({
    required this.item,
    required this.recipeId,
    required this.notifier,
    required this.dragIndex,
    required this.collapseEpoch,
    this.lit = false,
    super.key,
  });

  final LineItem item;

  /// The recipe being edited — what the identity picker excludes from its
  /// "Your recipes" section (a recipe cannot become its own component).
  final String recipeId;
  final RecipeEditor notifier;

  /// This row's position in the flat list — what the grip drags by.
  final int dragIndex;

  /// Bumped by the list when a drag starts: this card closes with the rest.
  final int collapseEpoch;

  /// Whether the step being written points at this line. See [LineCard.lit].
  final bool lit;

  /// The amount cell's label. Every line prints what the recipe page prints;
  /// only an unresolved measure id adds anything, and what it adds is the
  /// honest count fallback with a note saying why the measure is not there.
  ///
  /// **Two reasons, two words.** A measure whose row has not synced down yet
  /// arrives on its own, and "pending sync" is a promise the app keeps; one
  /// the household deleted never arrives, and the same words would have the
  /// reader waiting on nothing.
  String get _label {
    final stored = item.unit;
    if (item.measure == null && item.measureId != null && stored != null) {
      final qty = formatQuantityIn(item.quantity, stored);
      final why = item.measureDeleted
          ? 'measure deleted'
          : 'measure pending sync';
      final unit = '${stored.label} · $why';
      return qty.isEmpty ? unit : '$qty $unit';
    }
    return amountOfLineItem(item);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A component line (step 8.6 / D1) has no ingredient to look up: its
    // identity is the recipe chip, and its amount is edited against the
    // target's yields, not an ingredient's units.
    if (item.isComponent) {
      return _ComponentLineEditor(
        item: item,
        recipeId: recipeId,
        notifier: notifier,
        dragIndex: dragIndex,
        collapseEpoch: collapseEpoch,
        lit: lit,
      );
    }

    final ingredient = ref
        .watch(
          lineItemIngredientProvider(
            ingredientId: item.ingredientId ?? '',
            name: item.ingredientName,
          ),
        )
        .asData
        ?.value;

    Future<void> editQuantity() async {
      // An unresolved vocab row still gets a working sheet: a stub-shaped
      // stand-in scoped to the stored unit's family (no macros, no density —
      // nothing is invented for it).
      final sheetIngredient =
          ingredient ??
          Ingredient(
            id: item.ingredientId ?? '',
            canonicalName: item.ingredientName,
            // A stand-in for a row this sheet is not really about; a line
            // said in a recipe's own word has no catalog unit to lend it.
            defaultUnit: item.measure != null ? pieces : (item.unit ?? pieces),
            status: IngredientStatus.stub,
          );
      final pending = item.measureId != null && item.measure == null;
      final measure = item.measure;
      final result = await showQuantityUnitSheet(
        context,
        ingredient: sheetIngredient,
        initialQuantity: item.quantity,
        initialChoice: measure != null
            ? MeasureOption(measure)
            : UnitOption(item.unit ?? pieces),
        pendingMeasure: pending,
      );
      if (result is! QuantitySaved) return;
      notifier.setLineItemQuantity(item.id, result.quantity);
      switch (result.choice) {
        case MeasureOption(:final measure):
          notifier.setLineItemMeasure(item.id, measure);
        // This door is the INGREDIENT sheet, which never offers one; a
        // component's own words are picked on the component dock.
        case RecipeMeasureOption(:final measure):
          notAWordForAnIngredient(measure);
        case UnitOption(:final unit):
          // An unresolved measure id survives an unrelated re-save; only an
          // explicit chip pick clears it (degrade-don't-destroy).
          if (!pending || result.unitPicked) {
            notifier.setLineItemUnit(item.id, unit);
          }
      }
    }

    // A retired row's last known name, muted like a dangling component — same
    // news, same voice. The card's `change ›` is the repair the tag asks for.
    final nameStyle = item.ingredientDeleted
        ? ansiSans(size: 15, color: AnsiColors.muted)
        : ansiSans(size: 15, weight: FontWeight.w500);

    return _EditorLine(
      item: item,
      recipeId: recipeId,
      notifier: notifier,
      amount: _label,
      dragIndex: dragIndex,
      collapseEpoch: collapseEpoch,
      lit: lit,
      onEditAmount: editQuantity,
      rowIdentity: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: item.ingredientName, style: nameStyle),
            ...noteSpans(item.note),
            ...optionalSpans(optional: item.optional),
            ...removedIngredientSpans(removed: item.ingredientDeleted),
          ],
        ),
      ),
      headIdentity: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: item.ingredientName, style: nameStyle),
            ...removedIngredientSpans(removed: item.ingredientDeleted),
          ],
        ),
      ),
    );
  }
}

/// A component line in the editor (step 8.6 / D1, board frame a's identity
/// cell on an editor row): the recipe chip where the ingredient name sits, and
/// the same amount cell — opening the batch-math sheet instead of the
/// ingredient one.
///
/// A component whose target has not synced (or was deleted) keeps its stored
/// text and says so; the amount stays editable in batches, which needs no
/// target at all.
class _ComponentLineEditor extends StatelessWidget {
  const _ComponentLineEditor({
    required this.item,
    required this.recipeId,
    required this.notifier,
    required this.dragIndex,
    required this.collapseEpoch,
    this.lit = false,
  });

  final LineItem item;
  final String recipeId;
  final RecipeEditor notifier;
  final int dragIndex;
  final int collapseEpoch;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final target = item.subRecipe;

    Future<void> editQuantity() async {
      // The sheet's keyboard can unmount this row; the yield door pushes
      // from a context that outlives it.
      final host = hostContextOf(context);
      final result = await showComponentQuantitySheet(
        context,
        target:
            target ??
            SubRecipeTarget(
              id: item.subRecipeId ?? '',
              title: item.ingredientName,
            ),
        initialQuantity: item.quantity,
        initialUnit: item.unit,
        // The pointer the line carries, so the sheet opens on the word rather
        // than on a unit. The word itself is read off the target, which is
        // what makes a re-stated `blob` follow through everywhere at once.
        initialMeasureId: item.recipeMeasureId,
        initialOptional: item.optional,
        // Only where the target recipe is really here: a line whose recipe
        // row has not synced has no yields to gate a word on and nothing to
        // stamp one onto, so the dock offers no ＋ rather than a refusal.
        mayCoinWords: target != null,
        onSetYield: target == null
            ? null
            : () => host.context.pushOnce('/recipes/${target.id}/edit'),
      );
      if (result == null) return;
      notifier
        ..setLineItemQuantity(item.id, result.quantity)
        ..setLineItemOptional(item.id, optional: result.optional);
      // Exactly one of the two, and each setter clears the other: a line is
      // denominated once (ADR-0018). Both null is a line whose word has gone
      // and whose reader picked no chip — it keeps the pointer it had, because
      // a unit written there would be a number nobody stated.
      if (result.recipeMeasureId case final id?) {
        notifier.setLineItemRecipeMeasure(item.id, id, word: result.measure);
      } else if (result.unit case final picked?) {
        notifier.setLineItemUnit(item.id, picked);
      }
    }

    return _EditorLine(
      item: item,
      recipeId: recipeId,
      notifier: notifier,
      // The word the line was written in, read off the target's LIVE measures
      // rather than off the resolution: a word can be alive and unresolvable at
      // the same time (a `makes` restated into another family under it), and
      // that row must still read `3 blob` rather than a bare `3`. Only a word
      // that has truly gone prints the number alone, which is the honest half
      // of the refusal.
      amount: componentAmountText(
        item.quantity,
        item.unit,
        measureLabel: recipeMeasureOfLine(item)?.label,
      ),
      dragIndex: dragIndex,
      collapseEpoch: collapseEpoch,
      lit: lit,
      onEditAmount: editQuantity,
      // A dangling link reads as the plain text it stored, muted, and says why
      // there is no chip — the recipe page's own degradation.
      rowIdentity: target != null
          ? Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                RecipeChip(title: target.title, size: 14),
                if (item.note != null && item.note!.trim().isNotEmpty)
                  Text(
                    item.note!.trim(),
                    style: ansiSans(
                      size: 14,
                      color: AnsiColors.muted,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                if (item.optional) const OptionalTag(),
              ],
            )
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: item.ingredientName,
                    style: ansiSans(size: 15, color: AnsiColors.muted),
                  ),
                  ...noteSpans('linked recipe missing'),
                  ...optionalSpans(optional: item.optional),
                ],
              ),
            ),
      headIdentity: target != null
          ? RecipeChip(title: target.title, size: 14)
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: item.ingredientName,
                    style: ansiSans(size: 15, color: AnsiColors.muted),
                  ),
                  ...noteSpans('linked recipe missing'),
                ],
              ),
            ),
    );
  }
}

/// The editor's ingredient line: the review's expanding card, in the editor's
/// words ([LineCard]).
///
/// At rest it is the ONE row layout the app prints everywhere — the amount,
/// the name, the note on a single line, the amount in its own fixed column so
/// every identity left-aligns — bare on the recipe page's hairline, with the
/// grip beside it. Tapping anywhere on it opens the card, which holds every
/// fact the line can carry: the identity behind `change ›`, whether it may be
/// left out, the amount, and — for the first time — the note.
class _EditorLine extends StatelessWidget {
  const _EditorLine({
    required this.item,
    required this.recipeId,
    required this.notifier,
    required this.amount,
    required this.rowIdentity,
    required this.headIdentity,
    required this.dragIndex,
    required this.collapseEpoch,
    required this.onEditAmount,
    this.lit = false,
  });

  final LineItem item;
  final String recipeId;
  final RecipeEditor notifier;
  final String amount;

  /// The identity as the row states it: the name with its note, its
  /// `optional` tag and whatever the line is wearing.
  final Widget rowIdentity;

  /// The identity as the card's head says it — the name alone, because the
  /// note and the flag are controls of their own inside the card.
  final Widget headIdentity;

  final int dragIndex;
  final int collapseEpoch;
  final VoidCallback onEditAmount;

  /// Whether the step being written points at this line. See [LineCard.lit].
  final bool lit;

  @override
  Widget build(BuildContext context) => LineCard(
    dragIndex: dragIndex,
    collapseEpoch: collapseEpoch,
    lit: lit,
    // A saved recipe has no line that needs the user, and it has no wall of
    // boxes either: the border is what "open" looks like.
    borderAtRest: false,
    collapsed: (onExpand) => _CollapsedLine(
      amount: amount,
      identity: rowIdentity,
      onExpand: onExpand,
    ),
    expanded: (onCollapse) => _OpenLine(
      item: item,
      identity: headIdentity,
      amount: amount,
      usedIn: notifier.stepsUsing(item.id),
      onEditAmount: onEditAmount,
      onChangeIdentity: () => changeLineIdentity(
        context,
        recipeId: recipeId,
        item: item,
        notifier: notifier,
      ),
      onRemove: () => removeLineWithChips(context, item, notifier),
      onCollapse: onCollapse,
      onOptional: (on) => notifier.setLineItemOptional(item.id, optional: on),
      onNote: (text) => notifier.setLineItemNote(item.id, text),
    ),
  );
}

/// The line at rest. One gesture: anywhere on it opens the card.
class _CollapsedLine extends StatelessWidget {
  const _CollapsedLine({
    required this.amount,
    required this.identity,
    required this.onExpand,
  });

  final String amount;
  final Widget identity;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Edit the line',
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kLineAmountWidth,
            child: Text(
              amount.isEmpty ? '—' : amount,
              style: ansiMono(size: 14, color: AnsiColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: identity),
          const SizedBox(width: 8),
          const Icon(FLucideIcons.pencil, size: 14, color: AnsiColors.herb),
        ],
      ),
    ),
  );
}

/// The line, open. Everything the line can say about itself, in the card's
/// slots — and the two controls that can break a method chip, `change ›` and
/// the bin, standing under the count of the steps that quote it.
class _OpenLine extends StatelessWidget {
  const _OpenLine({
    required this.item,
    required this.identity,
    required this.amount,
    required this.usedIn,
    required this.onEditAmount,
    required this.onChangeIdentity,
    required this.onRemove,
    required this.onCollapse,
    required this.onOptional,
    required this.onNote,
  });

  final LineItem item;
  final Widget identity;
  final String amount;
  final int usedIn;
  final VoidCallback onEditAmount;
  final VoidCallback onChangeIdentity;
  final VoidCallback onRemove;
  final VoidCallback onCollapse;
  final ValueChanged<bool> onOptional;
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LineCardHead(
        identity: _HeadIdentity(onChange: onChangeIdentity, child: identity),
        onRemove: onRemove,
        onCollapse: onCollapse,
      ),
      _UsedInSteps(count: usedIn),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: OptionalFlagToggle(value: item.optional, onChanged: onOptional),
      ),
      const SizedBox(height: 12),
      LineCardRow(
        label: 'AMOUNT',
        child: Align(
          alignment: Alignment.centerLeft,
          child: LineCardAmountChip(label: amount, onTap: onEditAmount),
        ),
      ),
      const SizedBox(height: 12),
      LineCardNotesField(initial: item.note, onChanged: onNote),
    ],
  );
}

/// The card's head is the identity, and the identity is the door: the shipped
/// line target picker, behind `change ›`.
///
/// It keeps the line's id (0022 D6), which is what keeps every method chip
/// pointing at it — a swap by delete + re-add would mint a fresh
/// `line_item_id` and leave them all silently dangling.
class _HeadIdentity extends StatelessWidget {
  const _HeadIdentity({required this.child, required this.onChange});

  final Widget child;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Change what this line is',
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChange,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          child,
          Text('change ›', style: ansiMono(size: 10, color: AnsiColors.herb)),
        ],
      ),
    ),
  );
}

/// What depends on this line — the quiet count that makes the substitution
/// notice and the removal prompt read as consequences rather than surprises.
///
/// It sits on the open card, under the head: nobody needs it while scanning a
/// list of ingredients, and every collapsed row is the same height without it.
class _UsedInSteps extends StatelessWidget {
  const _UsedInSteps({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'used in $count ${plural(count, 'step')}',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    );
  }
}

/// Tap the identity → the shipped picker → the line keeps its id and takes a
/// new one. Chips survive by construction; D3 then relabels them.
Future<void> changeLineIdentity(
  BuildContext context, {
  required String recipeId,
  required LineItem item,
  required RecipeEditor notifier,
}) async {
  final picked = await showLineTargetPicker(
    context,
    editingRecipeId: recipeId,
    title: 'Change ${item.ingredientName} to',
  );
  if (picked == null) return;
  switch (picked) {
    case PickedIngredient(:final ingredient):
      notifier.setLineItemIngredient(item.id, ingredient);
    case PickedSubRecipe(:final target):
      notifier.setLineItemSubRecipe(item.id, target);
  }
}

/// Removing a referenced line asks first (D3's sibling). Confirming converts
/// its chips to plain words — the sentences survive, only the links die.
Future<void> removeLineWithChips(
  BuildContext context,
  LineItem item,
  RecipeEditor notifier,
) async {
  final steps = notifier.stepsUsing(item.id);
  if (steps == 0) {
    notifier.removeLineItem(item.id);
    return;
  }
  final confirmed = await askAnsi(
    context,
    title:
        '$steps ${plural(steps, 'step mentions', plural: 'steps mention')} '
        '${item.ingredientName}.',
    body:
        'Remove those chips too? Their words stay in the sentences — only '
        'the links go.',
    confirm: 'Remove',
  );
  if (confirmed) notifier.removeLineItem(item.id);
}
