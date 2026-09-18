/// The import route (`/import`): a single screen that switches on the
/// [ImportController] state machine — intake → loading → reconciliation →
/// committing — and, on a committed recipe, routes to its page.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_modals.dart';
import '../data/photo_intake.dart';
import '../domain/import_repository.dart';
import 'import_stage_rows.dart';
import 'import_view_models.dart';
import 'photo_doors.dart';
import 'reconciliation_view.dart';
import 'wide_review_view.dart';

class ImportView extends HookConsumerWidget {
  const ImportView({this.initialBookId, this.initialSectionId, super.key});

  /// The shelf a section's `＋` was standing on (0028 E3). Null from every
  /// other door, and then the draft files into the default book as before.
  final String? initialBookId;
  final String? initialSectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);

    // A committed recipe lands on its page, replacing the (now spent) import
    // flow so back doesn't return to it. A replacement rather than `go`: `go`
    // would flatten the stack to one page, and back from the new recipe would
    // leave the app instead of returning to the tab the import started from.
    ref.listen(importControllerProvider, (_, next) {
      if (next is ImportCommitted) {
        context.pushReplacement('/recipes/${next.recipeId}');
      }
    });

    final title = switch (state) {
      ImportReconciling() => 'Review recipe',
      _ => 'Import a recipe',
    };
    // "N to review" rides the header — the honest count of lines still wanting
    // a look, read from the same provider the Save button is gated on so the
    // two can never drift.
    final reviewCount = state is ImportReconciling
        ? ref.watch(importOutstandingLinesProvider)
        : null;
    // When the check behind the count has failed and never answered, the count
    // is the structural one — zero once every line is matched — and "looks
    // good" over a Save that will not open is the header telling the opposite
    // story to the button. Say the honest thing instead; the button below
    // carries the retry.
    // The one band this screen asks for: at expanded the review is three
    // columns (`wide_review_view.dart`), and below it the phone's page.
    final wide = AnsiLayout.of(context) == AnsiLayout.expanded;
    final validation = ref.watch(importValidationProvider);
    final unchecked =
        state is ImportReconciling &&
        validation.value == null &&
        validation.hasError;
    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(title, style: ansiHeaderTitle()),
        prefixes: [
          // An import is always started from a door, so back pops it; a
          // pasted `/import` has nothing under it and lands on the Library.
          FHeaderAction.back(onPress: () => ansiBack(context)),
        ],
        suffixes: [
          if (reviewCount != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  unchecked
                      ? 'not checked'
                      : reviewCount == 0
                      ? 'looks good'
                      : '$reviewCount to review',
                  style: ansiMono(
                    size: 11,
                    color: reviewCount == 0 && !unchecked
                        ? AnsiColors.herb
                        : AnsiColors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
      // The route is `fullWidth`, so from expanded up this page is handed the
      // whole pane; below it AnsiPane has already centred it in the measure and
      // `wide` is false. The intake form is NOT drawn wide: one field, one
      // button and the photo doors are a column by nature, so it stays the
      // phone's form and the columns appear once there is a source to put in
      // the first of them.
      child: switch ((state, wide)) {
        (ImportIdle(), _) => _IntakeForm(
          initialBookId: initialBookId,
          initialSectionId: initialSectionId,
        ),
        (ImportFailed(:final message), _) => _IntakeForm(
          error: message,
          initialBookId: initialBookId,
          initialSectionId: initialSectionId,
        ),
        (ImportLoading(:final rows, :final request), true) => WideReadingBody(
          rows: rows,
          request: request,
          checklist: StageChecklist(
            rows: rows,
            fromPhotos: request is ImportFromPhotos,
          ),
        ),
        (ImportLoading(:final rows, :final fromPhotos), _) => StageChecklist(
          rows: rows,
          fromPhotos: fromPhotos,
        ),
        (final ImportReconciling s, true) => WideReviewBody(state: s),
        (final ImportReconciling s, _) => ReconciliationBody(state: s),
        (ImportCommitting(), _) => const _Busy(label: 'Saving…'),
        (ImportCommitted(), _) => const _Busy(label: 'Done'),
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
          Text(label, style: ansiMono(size: 12, color: AnsiColors.muted)),
        ],
      ),
    );
  }
}

class _IntakeForm extends HookConsumerWidget {
  const _IntakeForm({this.error, this.initialBookId, this.initialSectionId});

  /// Carried from the route so the draft is filed where the door stood
  /// (0028 E3).
  final String? initialBookId;
  final String? initialSectionId;

  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = useState('');
    final controller = ref.read(importControllerProvider.notifier);
    final intake = ref.read(photoIntakeProvider);

    Future<void> importPhotos(PhotoSource source) async {
      final paths = await intake.pickAndCrop(
        source,
        // The camera's between-pages question. It is the view that owns it,
        // not the service, because it is the only party holding a context —
        // and a screen that has gone away answers no, which keeps the pages
        // already shot rather than dropping them.
        askAnotherPage: (pagesSoFar) async {
          if (!context.mounted) return false;
          return askAnsi(
            context,
            title: pagesSoFar == 1
                ? '1 page so far'
                : '$pagesSoFar pages so far',
            body: 'Photograph the next page, or read what you have.',
            confirm: 'Another page',
            cancel: 'Read it',
          );
        },
      );
      if (paths.isEmpty) return;
      await controller.startImport(
        ImportFromPhotos(paths),
        bookId: initialBookId,
        sectionId: initialSectionId,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Text(
          'Paste a recipe link, or import from photos. We read the '
          'ingredients and steps, then you confirm each match — nothing is '
          'guessed for you.',
          style: ansiSans(size: 14, color: AnsiColors.muted, height: 1.4),
        ),
        const SizedBox(height: 20),
        Text('RECIPE URL', style: ansiLabel()),
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
              : () => controller.startImport(
                  ImportFromUrl(url.value.trim()),
                  bookId: initialBookId,
                  sectionId: initialSectionId,
                ),
          child: const Text('Import from link'),
        ),
        const SizedBox(height: 24),
        ImportPhotoDoors(onPick: importPhotos),
        if (error != null) ...[
          const SizedBox(height: 20),
          Text(error!, style: ansiSans(size: 13, color: AnsiColors.gone)),
        ],
      ],
    );
  }
}
