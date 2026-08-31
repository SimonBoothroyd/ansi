/// The import route (`/import`): a single screen that switches on the
/// [ImportController] state machine — intake → loading → reconciliation →
/// committing — and, on a committed recipe, routes to its page.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../data/photo_intake.dart';
import '../domain/import_repository.dart';
import 'import_view_models.dart';
import 'reconciliation_view.dart';

class ImportView extends HookConsumerWidget {
  const ImportView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);

    // A committed recipe lands on its page; replace the flow in history so back
    // doesn't return to the (now spent) import screen.
    ref.listen(importControllerProvider, (_, next) {
      if (next is ImportCommitted) context.go('/recipes/${next.recipeId}');
    });

    final title = switch (state) {
      ImportReconciling() => 'Review recipe',
      _ => 'Import a recipe',
    };
    // "N to review" rides the header — the honest count of lines still wanting
    // a look, on the single review surface.
    final reviewCount = state is ImportReconciling ? state.reviewCount : null;
    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(title, style: miseHeaderTitle()),
        prefixes: [
          FHeaderAction.back(
            onPress: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
        ],
        suffixes: [
          if (reviewCount != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  reviewCount == 0 ? 'looks good' : '$reviewCount to review',
                  style: miseMono(
                    size: 11,
                    color: reviewCount == 0
                        ? MiseColors.herb
                        : MiseColors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
      child: switch (state) {
        ImportIdle() => const _IntakeForm(),
        ImportFailed(:final message) => _IntakeForm(error: message),
        ImportLoading() => const _Busy(label: 'Reading the recipe…'),
        ImportReconciling() => ReconciliationBody(state: state),
        ImportCommitting() => const _Busy(label: 'Saving…'),
        ImportCommitted() => const _Busy(label: 'Done'),
      },
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FCircularProgress(),
          const SizedBox(height: 12),
          Text(label, style: miseMono(size: 12, color: MiseColors.muted)),
        ],
      ),
    );
  }
}

class _IntakeForm extends HookConsumerWidget {
  const _IntakeForm({this.error});

  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = useState('');
    final controller = ref.read(importControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Text(
          'Paste a recipe link, or import from photos. We read the '
          'ingredients and steps, then you confirm each match — nothing is '
          'guessed for you.',
          style: miseSans(size: 14, color: MiseColors.muted, height: 1.4),
        ),
        const SizedBox(height: 20),
        Text('RECIPE URL', style: miseLabel()),
        const SizedBox(height: 6),
        FTextField(
          hint: 'https://…',
          control: FTextFieldControl.managed(
            onChange: (v) => url.value = v.text,
          ),
        ),
        const SizedBox(height: 12),
        FButton(
          onPress: url.value.trim().isEmpty
              ? null
              : () => controller.startImport(ImportFromUrl(url.value.trim())),
          child: const Text('Import from link'),
        ),
        const SizedBox(height: 24),
        FButton(
          variant: FButtonVariant.outline,
          prefix: const Icon(FLucideIcons.camera),
          // Pick one or more pages → crop/rotate each → import the cropped set.
          // An empty result (nothing picked, every page cancelled) starts
          // nothing; the repository downscales each page before upload.
          onPress: () async {
            final paths = await ref.read(photoIntakeProvider).pickAndCrop();
            if (paths.isEmpty) return;
            await controller.startImport(ImportFromPhotos(paths));
          },
          child: const Text('Import from photos'),
        ),
        if (error != null) ...[
          const SizedBox(height: 20),
          Text(error!, style: miseSans(size: 13, color: MiseColors.gone)),
        ],
      ],
    );
  }
}
