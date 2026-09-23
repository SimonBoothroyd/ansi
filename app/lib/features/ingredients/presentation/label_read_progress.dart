/// The reading screen the ingredient form shows while a photographed label is
/// read: the recipe import's own checklist ([StageChecklist]), one row long,
/// over the whole form.
///
/// `read-label` answers in one body rather than a stream, so there is one stage
/// and its time is the client's clock. The screen is opaque and takes every
/// tap, so nothing is typed into a field the reading is about to fill.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../import/domain/import_stage.dart';
import '../../import/presentation/import_stage_rows.dart';

/// The one stage a label read has.
enum LabelReadStage implements PipelineStage {
  read;

  @override
  String get id => 'read';

  @override
  String label({required bool fromPhotos, required StageStatus status}) =>
      status == StageStatus.active ? 'Reading the label…' : 'Label read';
}

class LabelReadProgress extends HookWidget {
  const LabelReadProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final clock = useMemoized(() => Stopwatch()..start());
    final elapsed = useState(Duration.zero);
    useEffect(() {
      final tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => elapsed.value = clock.elapsed,
      );
      return tick.cancel;
    }, const []);
    return ColoredBox(
      color: context.theme.colors.background,
      // Absorbs every tap, so the form under it cannot be reached.
      child: AbsorbPointer(
        child: StageChecklist(
          rows: [
            StageProgress(
              stage: LabelReadStage.read,
              status: StageStatus.active,
              elapsed: elapsed.value,
            ),
          ],
          fromPhotos: true,
        ),
      ),
    );
  }
}
