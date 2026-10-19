/// The Ask door on the Library, Week, Cook and Shop tabs: the same speech
/// bubble the recipe page carries, opening the sheet on what the tab shows.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../planning/presentation/week_view_models.dart';
import '../domain/ask_screen.dart';
import 'ask_sheet.dart';

/// A header action opening Ask Ansi. With [tab], the sheet sees that tab at
/// the week on screen, read when each question is asked; without, it sees
/// nothing in particular (the Library).
class AskDoor extends StatelessWidget {
  const AskDoor({this.tab, super.key});

  final AskWeekTab? tab;

  @override
  Widget build(BuildContext context) => FHeaderAction(
    icon: const Icon(FLucideIcons.messageCircleQuestion),
    semanticsLabel: 'Ask Ansi',
    onPress: () {
      final container = ProviderScope.containerOf(context, listen: false);
      final tab = this.tab;
      unawaited(
        showAskSheet(
          context,
          screen: () => tab == null
              ? const AskNoScreen()
              : AskWeekScreen(
                  tab: tab,
                  weekStart: container.read(viewedWeekStartProvider),
                ),
        ),
      );
    },
  );
}
