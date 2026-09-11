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
import '../../../shared/guarded_navigation.dart';
import '../data/photo_intake.dart';
import '../domain/import_repository.dart';
import '../domain/import_stage.dart';
import 'import_view_models.dart';
import 'reconciliation_view.dart';

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
          FHeaderAction.back(
            onPress: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.goOnce('/');
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
      child: switch (state) {
        ImportIdle() => _IntakeForm(
          initialBookId: initialBookId,
          initialSectionId: initialSectionId,
        ),
        ImportFailed(:final message) => _IntakeForm(
          error: message,
          initialBookId: initialBookId,
          initialSectionId: initialSectionId,
        ),
        ImportLoading(:final rows, :final fromPhotos) => _Reading(
          rows: rows,
          fromPhotos: fromPhotos,
        ),
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
          Text(label, style: ansiMono(size: 12, color: AnsiColors.muted)),
        ],
      ),
    );
  }
}

/// The reading screen: the server's stages as a vertical checklist, each row
/// carrying the time it actually took.
///
/// The wait is a minute or more from photos, and a screen that says one frozen
/// sentence through all of it reads as a hang. What makes this honest rather
/// than reassuring is that every row is something the server SAID — the list,
/// the order and the elapsed times all arrive on the wire (import spec §4.7),
/// so nothing here is a guess about progress.
class _Reading extends StatelessWidget {
  const _Reading({required this.rows, required this.fromPhotos});

  final List<StageProgress> rows;
  final bool fromPhotos;

  @override
  Widget build(BuildContext context) {
    // Before the first event there is nothing true to draw a checklist from.
    if (rows.isEmpty) return const _Busy(label: 'Sending…');
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows) _StageRow(row: row, fromPhotos: fromPhotos),
          ],
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.row, required this.fromPhotos});

  final StageProgress row;
  final bool fromPhotos;

  @override
  Widget build(BuildContext context) {
    final done = row.status == StageStatus.done;
    final active = row.status == StageStatus.active;
    final ink = done
        ? AnsiColors.ink
        : active
        ? AnsiColors.ink
        : AnsiColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Center(
              child: done
                  ? const Icon(
                      FLucideIcons.check,
                      size: 14,
                      color: AnsiColors.herb,
                    )
                  : active
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: FCircularProgress(),
                    )
                  : Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AnsiColors.line,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.stage.label(fromPhotos: fromPhotos),
              style: ansiSans(
                size: 13,
                color: ink,
                weight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          // A pending stage has no honest duration, so it shows none.
          if (row.elapsed case final elapsed?)
            Text(
              formatStageDuration(elapsed),
              style: ansiMono(
                size: 12,
                color: done ? AnsiColors.muted : AnsiColors.herb,
              ),
            ),
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
      final paths = await intake.pickAndCrop(source);
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
        // The photo door, split by where the page comes from: shoot it now, or
        // pick one or more from the library. Either way it is pick → crop/
        // rotate each → import the cropped set. An empty result (nothing
        // picked, camera dismissed, every page cancelled) starts nothing; the
        // repository downscales each page before upload.
        Row(
          children: [
            Expanded(
              child: FButton(
                variant: FButtonVariant.outline,
                prefix: const Icon(FLucideIcons.camera),
                onPress: () => importPhotos(PhotoSource.camera),
                child: const Text('Take a photo'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FButton(
                variant: FButtonVariant.outline,
                prefix: const Icon(FLucideIcons.image),
                onPress: () => importPhotos(PhotoSource.library),
                child: const Text('Choose photos'),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 20),
          Text(error!, style: ansiSans(size: 13, color: AnsiColors.gone)),
        ],
      ],
    );
  }
}
