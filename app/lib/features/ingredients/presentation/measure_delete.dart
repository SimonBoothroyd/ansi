/// The one gate both delete paths pass through: **a measure a recipe still
/// uses cannot be deleted.**
///
/// The FKs carry no `on delete` and the delete is a tombstone, so nothing in
/// the schema stops a measure going out from under the lines that name it —
/// and what those lines do afterwards is worse than an error. The macro engine
/// drops an unresolvable measure from the totals; the shop degrades it to a
/// bare count. Both silently, in a recipe nobody was looking at.
///
/// So the delete asks first, and the refusal has a door, exactly as deleting a
/// book that still holds recipes does: "it holds 42 recipes" is something a
/// person can act on, "failed" is not.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../data/ingredient_providers.dart';

/// Whether [measure] may be deleted — and, when it may not, the refusal that
/// says why and the door to the recipes still saying it.
///
/// The count is read from the REPOSITORY at the moment of the tap, never from
/// a cached list: the row a sheet is looking at can be minutes old.
Future<bool> mayDeleteMeasure(
  BuildContext context,
  WidgetRef ref,
  Measure measure,
) async {
  // Read before the first await: the row that opened this can be unmounted by
  // the time the dialog answers.
  final repo = ref.read(measureRepositoryProvider);
  final host = hostContextOf(context);
  final usage = await repo.countLinesUsing(measure.id);
  if (!usage.any) return true;

  final recipes = usage.recipes;
  final took = await refuseAnsi(
    // The host outlives the row — see [hostContextOf].
    // ignore: use_build_context_synchronously
    host.context,
    title: 'Can’t delete “${measure.label}” yet',
    body:
        '${usage.lines} ${plural(usage.lines, 'line')} still '
        '${plural(usage.lines, 'says', plural: 'say')} it'
        '${recipes.isEmpty ? '' : ', in ${recipes.length} '
                  '${plural(recipes.length, 'recipe')}'}. '
        'Change ${plural(usage.lines, 'it', plural: 'them')} to another unit '
        'first — deleting it now would quietly drop '
        '${plural(usage.lines, 'that line', plural: 'those lines')} out of '
        'every total.',
    door: recipes.isEmpty ? null : 'Show me where',
  );
  if (took) {
    await showAnsiSheet<void>(
      // The host outlives the row — see [hostContextOf].
      // ignore: use_build_context_synchronously
      context: host.context,
      builder: (context) => _UsedBy(measure: measure, recipes: recipes),
    );
  }
  return false;
}

/// The door: every recipe still saying this measure, each one a way in.
class _UsedBy extends StatelessWidget {
  const _UsedBy({required this.measure, required this.recipes});

  final Measure measure;
  final List<({String id, String title})> recipes;

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
      const SizedBox(height: 10),
      Text(
        'a planned meal or a shopping top-up can say it too — those are not '
        'recipes, so there is no page to send you to',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    ],
  );
}
