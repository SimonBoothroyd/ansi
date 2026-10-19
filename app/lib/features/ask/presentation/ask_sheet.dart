/// The Ask sheet: what Ansi can see, the conversation, and a field with a
/// mic.
///
/// The chip above the field says what Ansi can see — **Ragù · serves 6** —
/// and its ✕ asks from nowhere instead. A spoken question is sent when the
/// member pauses and its answer is read aloud; when Ansi asks something
/// back, the mic opens for the reply. An
/// action Ansi takes — a step's timer, the stepper, opening a recipe — lands
/// on the phone at once and is listed under the answer.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/ansi_toast.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../data/ask_voice.dart';
import '../domain/ask_proposal.dart';
import '../domain/ask_read_aloud.dart';
import '../domain/ask_screen.dart';
import '../domain/ask_spoken_question.dart';
import '../domain/ask_thread.dart';
import 'ask_card.dart';
import 'ask_controller.dart';
import 'ask_wiring.dart';

/// Opens the sheet over the page that knows [screen]. [screen] is read at each
/// question, so a stepper Ansi moved is what the next question scales to.
Future<void> showAskSheet(
  BuildContext context, {
  required AskScreen Function() screen,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);
  return showAnsiSheet<void>(
    context: context,
    builder: (sheetContext) => AskSheet(
      screen: screen,
      runnerFor: (open) => askToolRunner(container, screen: screen, open: open),
      open: (recipeId) {
        Navigator.of(sheetContext).maybePop();
        host.context.pushOnce('/recipes/$recipeId');
      },
    ),
  );
}

class AskSheet extends HookConsumerWidget {
  const AskSheet({
    required this.screen,
    required this.runnerFor,
    required this.open,
    super.key,
  });

  final AskScreen Function() screen;

  /// Builds the runner; its `open_recipe` records the recipe to open once
  /// the answer is in.
  final AskToolRunnerFactory runnerFor;

  /// Closes the sheet and opens a recipe.
  final void Function(String recipeId) open;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(askControllerProvider);
    final readAloud = ref.watch(askReadAloudSettingProvider);
    final text = useTextEditingController();
    final typed = useValueListenable(text).text;
    final listening = useState(false);
    final chipOff = useState(false);
    final voice = ref.read(askVoiceProvider);

    // A thread idle past its half hour is gone when the sheet opens. A card
    // still waiting when the sheet closes is a Cancel.
    final notifier = ref.read(askControllerProvider.notifier);
    useEffect(() {
      Future.microtask(notifier.forgetIfStale);
      return () {
        unawaited(voice.stopSpeaking());
        Future.microtask(() => notifier.decide(AskDecision.cancelled));
      };
    }, const []);

    AskScreen current() => chipOff.value ? const AskNoScreen() : screen();

    // The mic sends what it heard, and a question Ansi asks back opens the
    // mic, so one is declared ahead of the other.
    late final Future<void> Function() mic;

    Future<void> send(String words, {required bool spoken}) async {
      final question = words.trim();
      if (question.isEmpty) return;
      text.clear();
      final notifier = ref.read(askControllerProvider.notifier);
      final reads = ref.read(askReadAloudSettingProvider).reads(spoken: spoken);
      String? toOpen;
      final answer = await notifier.ask(
        question,
        screen: current(),
        runner: runnerFor((id) => toOpen = id),
        spoken: spoken,
      );
      if (answer == null) return;
      final reading = reads ? voice.speak(answer) : Future<void>.value();
      final id = toOpen;
      if (id != null) {
        unawaited(reading);
        if (context.mounted) open(id);
        return;
      }
      if (!spoken || !asksBack(answer)) {
        unawaited(reading);
        return;
      }
      // Ansi asked back: the mic opens for the reply once the question has
      // been read — unless the member has moved on (tapped the mic, typed,
      // started anew, closed the sheet).
      await reading;
      if (!context.mounted || listening.value || text.text.isNotEmpty) return;
      final now = ref.read(askControllerProvider);
      if (now.busy || now.thread.exchanges.lastOrNull?.answer != answer) {
        return;
      }
      await mic();
    }

    mic = () async {
      if (listening.value) {
        await voice.stopListening();
        return;
      }
      listening.value = true;
      final ok = await voice.listen(
        onWords: (words, {required done}) {
          if (!context.mounted) return;
          text.text = words;
          if (done) {
            listening.value = false;
            unawaited(send(words, spoken: true));
          }
        },
      );
      if (!ok && context.mounted) {
        listening.value = false;
        text.text = '';
        showAskMicRefused(context);
      }
    };

    final label = chipOff.value ? null : screen().chipLabel;
    final exchanges = state.thread.exchanges;

    return AnsiSheetShell(
      title: 'Ask Ansi',
      centerTitle: false,
      heightFactor: 0.72,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            if (label != null)
              Flexible(
                child: _SeesChip(
                  label: label,
                  onDismiss: () => chipOff.value = true,
                ),
              )
            else
              Flexible(
                child: Text(
                  'Asking about nothing on screen',
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
              ),
            const SizedBox(width: 8),
            AnsiTap(
              onTap: () =>
                  ref.read(askReadAloudSettingProvider.notifier).cycle(),
              semanticsLabel: readAloud.label,
              padding: const EdgeInsets.all(6),
              child: Icon(
                readAloud == AskReadAloud.never
                    ? FLucideIcons.volumeX
                    : FLucideIcons.volume2,
                size: 18,
                color: readAloud == AskReadAloud.always
                    ? AnsiColors.herb
                    : AnsiColors.muted,
              ),
            ),
            if (exchanges.isNotEmpty && !state.busy)
              AnsiTap(
                onTap: () {
                  unawaited(voice.stopSpeaking());
                  ref.read(askControllerProvider.notifier).clear();
                },
                semanticsLabel: 'Start a new conversation',
                padding: const EdgeInsets.all(6),
                child: const Icon(
                  FLucideIcons.squarePen,
                  size: 18,
                  color: AnsiColors.muted,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: exchanges.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    _examples(current()),
                    style: ansiMono(size: 11.5, color: AnsiColors.muted),
                  ),
                )
              : ListView(
                  reverse: true,
                  children: [
                    // The card waits under the question it answers.
                    if (state.card case final card?) AskCard(proposal: card),
                    for (final (i, e) in exchanges.reversed.indexed)
                      _ExchangeView(
                        exchange: e,
                        // The card stands where the spinner would.
                        waiting: i == 0 && state.card == null,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FTextField(
                hint: listening.value ? 'Listening…' : 'Ask a question',
                textInputAction: TextInputAction.send,
                enabled: !state.busy,
                maxLines: 3,
                minLines: 1,
                control: FTextFieldControl.managed(controller: text),
                onSubmit: (v) => unawaited(send(v, spoken: false)),
              ),
            ),
            const SizedBox(width: 8),
            if (typed.trim().isNotEmpty && !listening.value)
              FButton.icon(
                onPress: state.busy
                    ? null
                    : () => unawaited(send(text.text, spoken: false)),
                child: const Icon(FLucideIcons.arrowUp),
              )
            else
              FButton.icon(
                variant: listening.value
                    ? FButtonVariant.primary
                    : FButtonVariant.outline,
                onPress: state.busy ? null : () => unawaited(mic()),
                child: Semantics(
                  label: listening.value ? 'Stop listening' : 'Speak',
                  child: Icon(
                    listening.value ? FLucideIcons.micOff : FLucideIcons.mic,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// What can be said from [screen], as the empty sheet suggests it.
String _examples(AskScreen screen) => switch (screen) {
  AskRecipeScreen() =>
    '“How much tamari?” · “What’s step 3?” · “Start the simmer timer” · '
        '“Make it 8 servings”',
  AskWeekScreen(tab: AskWeekTab.shop) =>
    '“Do we need tamari?” · “What’s left to buy?” · “Add milk to the list”',
  AskWeekScreen(tab: AskWeekTab.cook) =>
    '“What am I cooking on Sunday?” · “What’s for dinner tonight?”',
  AskWeekScreen() =>
    '“What’s for dinner tonight?” · “Move Tuesday’s curry to Thursday” · '
        '“I’m eating out Friday” · “Copy last week”',
  AskNoScreen() =>
    '“What’s for dinner tonight?” · “Open the aioli” · '
        '“Set all dinners next week to Ragù”',
};

/// What the mic says when the phone cannot listen: no recogniser, or the
/// microphone refused.
void showAskMicRefused(BuildContext context) => showAnsiFailureToast(
  context,
  what: 'hear you — allow the microphone in Settings, or type the question',
);

class _SeesChip extends StatelessWidget {
  const _SeesChip({required this.label, required this.onDismiss});

  final String label;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: 10, right: 2),
    decoration: BoxDecoration(
      color: AnsiColors.herbSoft,
      borderRadius: BorderRadius.circular(AnsiRadii.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'On: $label',
            overflow: TextOverflow.ellipsis,
            style: ansiMono(size: 11, color: AnsiColors.herbDeep),
          ),
        ),
        AnsiTap(
          onTap: onDismiss,
          semanticsLabel: 'Ask without this screen',
          padding: const EdgeInsets.all(6),
          child: const Icon(FLucideIcons.x, size: 14, color: AnsiColors.herb),
        ),
      ],
    ),
  );
}

class _ExchangeView extends StatelessWidget {
  const _ExchangeView({required this.exchange, this.waiting = true});

  final AskExchange exchange;

  /// Whether an unanswered exchange shows the spinner.
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final answer = exchange.answer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exchange.question,
            textAlign: TextAlign.right,
            style: ansiMono(size: 12, color: AnsiColors.muted),
          ),
          const SizedBox(height: 6),
          if (answer == null && waiting)
            const Align(
              alignment: Alignment.centerLeft,
              child: FCircularProgress(),
            )
          else if (answer != null)
            Text(
              answer,
              style: ansiSans(
                size: 15,
                color: exchange.failed ? AnsiColors.muted : AnsiColors.ink,
              ),
            ),
          for (final d in exchange.done)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '✓ $d',
                style: ansiMono(size: 11, color: AnsiColors.herb),
              ),
            ),
        ],
      ),
    );
  }
}
