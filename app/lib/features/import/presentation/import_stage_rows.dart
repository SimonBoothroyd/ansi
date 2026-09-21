/// The reading screen's checklist: the server's stages as a vertical list, each
/// row carrying the time it took. The list, the order and the elapsed times all
/// arrive on the wire, so nothing is estimated. Shared by the recipe and
/// receipt readers through [PipelineStage].
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../domain/import_stage.dart';

class StageChecklist extends StatelessWidget {
  const StageChecklist({
    required this.rows,
    required this.fromPhotos,
    super.key,
  });

  final List<StageProgress> rows;
  final bool fromPhotos;

  @override
  Widget build(BuildContext context) {
    // Before the first event there is nothing true to draw a checklist from,
    // and a list of pending rows would be claiming a plan nobody has sent.
    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FCircularProgress(),
            const SizedBox(height: 12),
            Text(
              'Sending…',
              style: ansiMono(size: 12, color: AnsiColors.muted),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in rows) StageRow(row: row, fromPhotos: fromPhotos),
          ],
        ),
      ),
    );
  }
}

class StageRow extends StatelessWidget {
  const StageRow({required this.row, required this.fromPhotos, super.key});

  final StageProgress row;
  final bool fromPhotos;

  @override
  Widget build(BuildContext context) {
    final done = row.status == StageStatus.done;
    final active = row.status == StageStatus.active;
    final ink = done || active ? AnsiColors.ink : AnsiColors.muted;
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
                  // Sized by its own variant, never by a box around it: the
                  // spinner rotates about its centre, so a box smaller than the
                  // glyph puts the ink off the pivot and it wobbles.
                  ? const FCircularProgress(
                      size: FCircularProgressSizeVariant.xs,
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
              row.stage.label(fromPhotos: fromPhotos, status: row.status),
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
