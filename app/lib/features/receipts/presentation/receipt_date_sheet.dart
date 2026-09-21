/// *When was this shop*: corrects the receipt's date, which decides the week it
/// files under. An unread date opens on the scan day and says so. The sheet
/// moves the day and keeps the time the receipt already had.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';

/// The calendar, so a test names it rather than hunting a day cell by text.
const kReceiptDateCalendarKey = ValueKey('receipt-date-calendar');

/// Opens the calendar on [current]; resolves to the picked wall time, or null
/// when dismissed. Days after [today] are not selectable.
Future<DateTime?> showReceiptDateSheet(
  BuildContext context, {
  required DateTime current,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final lastDay = DateTime(now.year, now.month, now.day);
  return showAnsiSheet<DateTime>(
    context: context,
    builder: (sheetContext) => AnsiSheetShell(
      title: 'When was this shop',
      children: [
        Center(
          child: FCalendar(
            key: kReceiptDateCalendarKey,
            control: FCalendarControl.managedDate(
              initial: DateTime(current.year, current.month, current.day),
              toggleable: false,
              selectable: (day) =>
                  !DateTime(day.year, day.month, day.day).isAfter(lastDay),
              onChange: (day) {
                if (day == null) return;
                Navigator.of(sheetContext).pop(moveToDay(current, day));
              },
            ),
            today: now,
            initialMonth: current,
          ),
        ),
      ],
    ),
  );
}

/// [wall] on [day], keeping its clock — as plain wall time with no zone, the
/// way every receipt's moment is held.
DateTime moveToDay(DateTime wall, DateTime day) =>
    DateTime(day.year, day.month, day.day, wall.hour, wall.minute, wall.second);
