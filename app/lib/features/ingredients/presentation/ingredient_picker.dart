/// The inline ingredient picker: a search sheet over the local seeded vocab.
///
/// Step 2 only picks existing ingredients (ADR-0004 exact/prefix search). The
/// "create new / stub" flow is deferred, so there is no add-new affordance here.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../data/ingredient_providers.dart';
import '../domain/ingredient.dart';

/// Opens the picker as a bottom sheet; resolves to the chosen ingredient, or
/// null if dismissed.
Future<Ingredient?> showIngredientPicker(BuildContext context) {
  return showFSheet<Ingredient>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (_) => const _IngredientPickerSheet(),
  );
}

class _IngredientPickerSheet extends HookConsumerWidget {
  const _IngredientPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    final results = useState<List<Ingredient>>(const []);
    // Monotonic ticket so a slow older search can never overwrite a newer
    // one's results (or touch state after the sheet is dismissed).
    final searchSeq = useRef(0);

    Future<void> runSearch(String q) async {
      query.value = q;
      final ticket = ++searchSeq.value;
      final found = await ref.read(ingredientRepositoryProvider).search(q);
      if (!context.mounted || ticket != searchSeq.value) return;
      results.value = found;
    }

    useEffect(() {
      runSearch('');
      return null;
    }, const []);

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.72,
      decoration: const BoxDecoration(
        color: MiseColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: MiseColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 10,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: MiseColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('FIND AN INGREDIENT', style: miseLabel()),
            const SizedBox(height: 12),
            FTextField(
              autofocus: true,
              hint: 'Search the vocabulary',
              control: FTextFieldControl.managed(
                onChange: (v) => runSearch(v.text),
              ),
              prefixBuilder: (context, style, _) =>
                  const Icon(FLucideIcons.search),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: results.value.isEmpty
                  ? Center(
                      child: Text(
                        query.value.isEmpty
                            ? 'No ingredients yet.'
                            : 'No match for "${query.value}".',
                        style: miseMono(size: 12, color: MiseColors.muted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: results.value.length,
                      separatorBuilder: (_, _) => const FDivider(),
                      itemBuilder: (context, i) {
                        final ing = results.value[i];
                        return FItem(
                          title: Text(
                            ing.canonicalName,
                            style: miseSans(size: 16),
                          ),
                          subtitle: ing.category == null
                              ? null
                              : Text(
                                  ing.category!,
                                  style: miseMono(
                                    size: 11,
                                    color: MiseColors.muted,
                                  ),
                                ),
                          suffix: ing.status == IngredientStatus.stub
                              ? const _StubBadge()
                              : null,
                          onPress: () => Navigator.of(context).pop(ing),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StubBadge extends StatelessWidget {
  const _StubBadge();

  @override
  Widget build(BuildContext context) {
    return FBadge(
      variant: FBadgeVariant.secondary,
      child: Text('stub', style: miseMono(size: 10, color: MiseColors.muted)),
    );
  }
}
