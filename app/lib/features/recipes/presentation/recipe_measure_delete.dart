/// The one gate every path that retires a recipe's own word passes through:
/// **a word lines still say cannot go.**
///
/// It is `ingredients/presentation/measure_delete.dart` one level up, and it
/// holds for a sharper reason. Nothing follows a word out because nothing may
/// (ADR-0018 rule 3): a line saying a retired word keeps its number, resolves
/// to nothing and joins no total — for good, since the word was the only place
/// its amount lived. So the retirement is refused rather than cascaded, and the
/// refusal has a door: "3 lines still say it, in 2 recipes" is something a
/// person can act on, and "failed" is not.
///
/// The repository refuses it too — its own bin and the recipe form's deferred
/// diff both throw while anything still points at the row — and this is that
/// same answer in front of the person, before anything is attempted.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../data/recipe_providers.dart';
import 'component_format.dart';

/// Whether [measure] may be retired — and, when it may not, the refusal that
/// says why and the door to the recipes still saying it.
///
/// The count is read from the REPOSITORY at the moment of the tap, never off a
/// list: the rows a form is looking at can be minutes old, and a word the other
/// phone just used is exactly the case this exists for. A word no Save has
/// written yet has no referrer, so the same question answers "yes" for a draft
/// row without a special case.
Future<bool> mayDeleteRecipeMeasure(
  BuildContext context,
  WidgetRef ref,
  RecipeMeasure measure,
) async {
  // Read before the first await: the row that opened this can be unmounted by
  // the time the dialog answers.
  final repo = ref.read(recipeMeasureRepositoryProvider);
  final host = hostContextOf(context);
  final usage = await repo.countLinesUsing(measure.id);
  if (!usage.any) return true;

  final recipes = usage.recipes;
  final refusal = recipeMeasureDeleteRefusalText(
    label: measure.label,
    lines: usage.lines,
    recipes: recipes.length,
    weeks: usage.weeks,
  );
  // Only a week says it when no live line does, and a week has no page.
  final change = usage.lines == 0
      ? 'that amount'
      : plural(usage.lines, 'that line', plural: 'those lines');
  final took = await refuseAnsi(
    // The host outlives the row — see [hostContextOf].
    // ignore: use_build_context_synchronously
    host.context,
    title: 'Still in use',
    body:
        '$refusal '
        'Change $change '
        'first — a measure that goes leaves every line saying it '
        'unresolved for good.',
    door: recipes.isEmpty ? null : 'Show me where',
  );
  if (took) {
    await showAnsiSheet<void>(
      // The host outlives the row — see [hostContextOf].
      // ignore: use_build_context_synchronously
      context: host.context,
      builder: (context) =>
          _SaidBy(measure: measure, recipes: recipes, weeks: usage.weeks),
    );
  }
  return false;
}

/// The door: every recipe still saying this word, each one a way in.
class _SaidBy extends StatelessWidget {
  const _SaidBy({
    required this.measure,
    required this.recipes,
    required this.weeks,
  });

  final RecipeMeasure measure;
  final List<({String id, String title})> recipes;

  /// How many weeks say it in their own amount — the footnote below, which is
  /// printed only when there are any.
  final int weeks;

  @override
  Widget build(BuildContext context) => AnsiSheetShell(
    children: [
      const SizedBox(height: 8),
      Text('STILL SAYS “${measure.label}”', style: ansiLabel()),
      const SizedBox(height: 10),
      for (final r in recipes)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.pushOnce('/recipes/${r.id}'),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AnsiColors.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r.title,
                    style: ansiSerif(size: AnsiType.small),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  FLucideIcons.chevronRight,
                  size: 15,
                  color: AnsiColors.muted,
                ),
              ],
            ),
          ),
        ),
      if (weeks > 0) ...[
        const SizedBox(height: 10),
        Text(
          '${plural(weeks, 'one week', plural: '$weeks weeks')} '
          '${plural(weeks, 'says', plural: 'say')} it in '
          '${plural(weeks, 'its', plural: 'their')} own amount — that is not a '
          'recipe, so there is no page to send you to',
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
      ],
    ],
  );
}
