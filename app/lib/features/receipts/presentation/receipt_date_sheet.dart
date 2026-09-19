/// *When was this shop* — the receipt's date, as a door.
///
/// A receipt's date is the paper's fact, and most of the time the reader gets
/// it. This is for the rest: a strip whose date could not be read (the review
/// then opens on the day of the scan, which is a guess and says so), and a
/// read that was simply wrong. The date decides which **week** the receipt
/// files under, so a wrong one is a wrong ledger.
///
/// **The day, not the minute.** Nothing reads a receipt's clock — the ledger
/// files by day — so the door moves the day and keeps whatever time the
/// receipt already had, the paper's where it printed one.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';

/// The calendar, so a test names it rather than hunting a day cell by text.
const kReceiptDateCalendarKey = ValueKey('receipt-date-calendar');

/// Opens the calendar on [current]; resolves to the picked wall time, or null
/// when the sheet was dismissed.
///
/// A shop cannot have happened tomorrow, so the days after [today] are not
/// selectable.
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
