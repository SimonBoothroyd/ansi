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

import 'package:flutter/foundation.dart' show kIsWeb;
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

/// The one line of guidance the camera door carries, from the design board.
const kReceiptShootGuidance =
    'Photograph the receipt. A long one goes in two or three shots, top to '
    'bottom, overlapping a few lines — the overlap is how the parts are '
    'joined. We read the store, the date and every line, then you confirm '
    'each match.';

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

    final reviewing = state is ReceiptReviewing ? state : null;
    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(
          reviewing == null ? 'Scan a receipt' : 'Review receipt',
          style: ansiHeaderTitle(),
        ),
        prefixes: [FHeaderAction.back(onPress: () => ansiBack(context))],
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
        final ReceiptReviewing s => ReceiptReviewBody(state: s),
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

/// The camera, the guidance, and the way the parts become one strip.
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
            body:
                'Photograph the next stretch of the receipt, overlapping a '
                'few lines with the last one — or read what you have.',
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
        const SizedBox(height: 18),
        Text(
          'The parts are one strip. The photos are joined where the end of '
          'one repeats the start of the next — by position, never by name, '
          'because a receipt honestly prints the same item twice when two '
          'were bought. What the join gets wrong, the review catches against '
          'the printed subtotal.',
          style: ansiSans(size: 12.5, color: AnsiColors.muted, height: 1.4),
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 12),
          Text(
            'In a browser there is no camera and no crop step, so a receipt '
            'is shot on the phone and reviewed on whichever screen is '
            'nearest.',
            style: ansiSans(size: 12.5, color: AnsiColors.muted, height: 1.4),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 20),
          Text(error!, style: ansiSans(size: 13, color: AnsiColors.gone)),
        ],
      ],
    );
  }
}
