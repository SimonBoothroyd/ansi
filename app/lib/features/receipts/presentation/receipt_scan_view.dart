/// The scan route (`/receipts/review`): one screen switching on the
/// [ReceiptScanController] — intake → reading → review → saved.
///
/// It is the recipe import's own shape, and deliberately so: the camera, the
/// crop, the *another page* question and the reading checklist are already
/// built, tested and understood, and a receipt asks the same things of them.
/// What the screen adds is one line of guidance, because a receipt is longer
/// than a page and how it is photographed decides whether it can be joined at
/// all.
///
/// **Nothing is written until Save**, so every failure here is safe to
/// repeat, and backing out leaves the ledger as it was.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_modals.dart';
import '../../import/data/photo_intake.dart';
import '../../import/presentation/import_stage_rows.dart';
import '../../import/presentation/photo_doors.dart';
import '../domain/receipt_repository.dart';
import 'receipt_review_body.dart';
import 'receipt_view_models.dart';

/// The one line of guidance the camera door carries.
const kReceiptShootGuidance =
    'Photograph the receipt. A long one goes in two or three shots, top to '
    'bottom, overlapping a few lines.';

class ReceiptScanView extends ConsumerWidget {
  const ReceiptScanView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receiptScanControllerProvider);

    // A saved receipt lands on its page in the ledger, replacing the (now
    // spent) scan so back does not return to it. A replacement rather than
    // `go`: `go` would flatten the stack, and back from the receipt would
    // leave the app instead of returning to the Shop.
    ref.listen(receiptScanControllerProvider, (_, next) {
      if (next is ReceiptSaved) {
        context.pushReplacement('/receipts/${next.receiptId}');
      }
    });

    // Only a fresh scan is this screen's to review; a saved receipt opening
    // behind a replaced route is its own page's.
    final reviewing = state is ReceiptReviewing && !state.isSaved
        ? state
        : null;
    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(
          reviewing == null ? 'Scan a receipt' : 'Review receipt',
          style: ansiHeaderTitle(),
        ),
        // A scan is always started from the Shop's foot, so a pasted link to
        // it goes home there.
        prefixes: [
          FHeaderAction.back(onPress: () => ansiBack(context, home: '/shop')),
        ],
        suffixes: [
          if (reviewing != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  reviewing.map.headerCount == 0
                      ? 'looks good'
                      : '${reviewing.map.headerCount} to review',
                  style: ansiMono(
                    size: 11,
                    color: reviewing.map.headerCount == 0
                        ? AnsiColors.herb
                        : AnsiColors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
      child: switch (state) {
        ReceiptIdle() => const _Intake(),
        ReceiptScanFailed(:final message) => _Intake(error: message),
        // A receipt only ever arrives as photos, so the checklist is always
        // in the photo tense.
        ReceiptReading(:final rows) => StageChecklist(
          rows: rows,
          fromPhotos: true,
        ),
        final ReceiptReviewing s when !s.isSaved => ReceiptReviewBody(state: s),
        ReceiptReviewing() => const _Busy(label: 'Done'),
        // The two states of a SAVED receipt being read back belong to its own
        // page; the scan only ever passes through them on the way there.
        ReceiptOpening() || ReceiptGone() => const _Busy(label: 'Done'),
        ReceiptSaving() => const _Busy(label: 'Saving…'),
        ReceiptSaved() => const _Busy(label: 'Done'),
      },
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
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

/// The guidance and the photo doors.
class _Intake extends ConsumerWidget {
  const _Intake({this.error});

  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(receiptScanControllerProvider.notifier);
    final intake = ref.read(photoIntakeProvider);

    Future<void> shoot(PhotoSource source) async {
      final paths = await intake.pickAndCrop(
        source,
        askAnotherPage: (pagesSoFar) async {
          if (!context.mounted) return false;
          return askAnsi(
            context,
            title: pagesSoFar == 1
                ? '1 photo so far'
                : '$pagesSoFar photos so far',
            body: 'Overlap the last photo by a few lines.',
            confirm: 'Another photo',
            cancel: 'Read it',
          );
        },
      );
      if (paths.isEmpty) return;
      await controller.scan(ReceiptPhotos(paths));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        Text(
          kReceiptShootGuidance,
          style: ansiSans(size: 14, color: AnsiColors.muted, height: 1.4),
        ),
        const SizedBox(height: 20),
        ImportPhotoDoors(onPick: shoot),
        if (error != null) ...[
          const SizedBox(height: 20),
          Text(error!, style: ansiSans(size: 13, color: AnsiColors.gone)),
        ],
      ],
    );
  }
}
