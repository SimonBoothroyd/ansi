/// *When was this shop*: corrects the receipt's day and time, which decide the
/// week it files under. An unread date opens on the scan day and says so. The
/// calendar moves the day, the 24-hour wheels move the clock, and *Use it*
/// commits both; a day moved alone keeps the time the receipt already had.
/// A moment later than now cannot be used.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';

/// The calendar, so a test names it rather than hunting a day cell by text.
const kReceiptDateCalendarKey = ValueKey('receipt-date-calendar');

/// The hour and minute wheels.
const kReceiptTimePickerKey = ValueKey('receipt-time-picker');

/// The button that commits the picked day and time.
const kReceiptDateUseKey = ValueKey('receipt-date-use');

/// Opens the sheet on [current]; resolves to the picked wall time, or null
/// when dismissed. Days after [now] are not selectable, and a time later than
/// [now] holds *Use it*.
Future<DateTime?> showReceiptDateSheet(
  BuildContext context, {
  required DateTime current,
  DateTime? now,
}) => showAnsiSheet<DateTime>(
  context: context,
  builder: (sheetContext) => _ReceiptDateSheet(
    current: current,
    now: now ?? DateTime.now(),
    onDone: (picked) => Navigator.of(sheetContext).pop(picked),
  ),
);

class _ReceiptDateSheet extends HookWidget {
  const _ReceiptDateSheet({
    required this.current,
    required this.now,
    required this.onDone,
  });

  final DateTime current;
  final DateTime now;
  final ValueChanged<DateTime> onDone;

  @override
  Widget build(BuildContext context) {
    final lastDay = DateTime(now.year, now.month, now.day);
    final day = useState(DateTime(current.year, current.month, current.day));
    final time = useState(FTime.fromDateTime(current));
    final picked = pickedMoment(current, day.value, time.value);
    final later = picked.isAfter(now);

    return AnsiSheetShell(
      title: 'When was this shop',
      scrollable: true,
      children: [
        Center(
          child: FCalendar(
            key: kReceiptDateCalendarKey,
            control: FCalendarControl.managedDate(
              initial: day.value,
              toggleable: false,
              selectable: (d) =>
                  !DateTime(d.year, d.month, d.day).isAfter(lastDay),
              onChange: (d) {
                if (d != null) day.value = DateTime(d.year, d.month, d.day);
              },
            ),
            today: now,
            initialMonth: current,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 132,
          child: FTimePicker(
            key: kReceiptTimePickerKey,
            hour24: true,
            control: FTimePickerControl.managed(
              initial: time.value,
              onChange: (t) => time.value = t,
            ),
          ),
        ),
        if (later) ...[
          const SizedBox(height: 6),
          Text(
            'that is later than now',
            textAlign: TextAlign.center,
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ],
        const SizedBox(height: 12),
        FButton(
          key: kReceiptDateUseKey,
          onPress: later ? null : () => onDone(picked),
          child: const Text('Use it'),
        ),
      ],
    );
  }
}

/// [time] on [day] as plain wall time with no zone, the way every receipt's
/// moment is held. An unchanged clock keeps [current]'s seconds; a moved one
/// starts its minute.
DateTime pickedMoment(DateTime current, DateTime day, FTime time) =>
    time == FTime.fromDateTime(current)
    ? moveToDay(current, day)
    : DateTime(day.year, day.month, day.day, time.hour, time.minute);

/// [wall] on [day], keeping its clock — as plain wall time with no zone, the
/// way every receipt's moment is held.
DateTime moveToDay(DateTime wall, DateTime day) =>
    DateTime(day.year, day.month, day.day, wall.hour, wall.minute, wall.second);
