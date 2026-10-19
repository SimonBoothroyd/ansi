/// Ansi's ears and voice: the phone's own speech recogniser and text-to-speech
/// engine. Nothing here leaves the phone except what the platform
/// recogniser itself sends; no audio reaches Ansi's servers.
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../domain/ask_read_aloud.dart';
import '../domain/ask_spoken_question.dart';

part 'ask_voice.g.dart';

/// The mic and the speaker. The device one is [DeviceAskVoice]; tests fake it.
abstract interface class AskVoice {
  /// Starts listening. [onWords] hears the words so far, with `done` true
  /// once a pause has ended the question (see [AskSpokenQuestion]). Returns
  /// false when the phone has no recogniser or the mic was refused.
  Future<bool> listen({
    required void Function(String words, {required bool done}) onWords,
  });

  /// Stops listening; the words so far arrive as done.
  Future<void> stopListening();

  /// Reads [text] aloud, interrupting anything still being read.
  Future<void> speak(String text);

  /// Stops reading aloud.
  Future<void> stopSpeaking();
}

/// The phone's own recogniser (`speech_to_text`) and engine (`flutter_tts`).
///
/// The recogniser's sessions are driven by an [AskSpokenQuestion], which
/// restarts one the phone ends on its own short silence; only these errors
/// are a quiet member rather than a lost mic.
class DeviceAskVoice implements AskVoice {
  final SpeechToText _ears = SpeechToText();
  final FlutterTts _mouth = FlutterTts();
  bool? _ready;
  AskSpokenQuestion? _question;
  bool _restarting = false;

  static const _quiet = {'error_no_match', 'error_speech_timeout'};

  @override
  Future<bool> listen({
    required void Function(String words, {required bool done}) onWords,
  }) async {
    final ready = _ready ??= await _ears.initialize(
      onStatus: (status) {
        if (status == SpeechToText.doneStatus) _ended(fatal: false);
      },
      onError: (e) => _ended(fatal: !_quiet.contains(e.errorMsg)),
    );
    if (!ready) return false;
    await _mouth.stop();
    _question?.finish();
    final question = _question = AskSpokenQuestion(
      onWords: onWords,
      restart: () => unawaited(_restart()),
      stop: () => unawaited(_ears.stop()),
    )..start();
    await _session(question);
    return true;
  }

  Future<void> _session(AskSpokenQuestion question) => _ears.listen(
    onResult: (r) => question.heard(r.recognizedWords, isFinal: r.finalResult),
    listenOptions: SpeechListenOptions(
      pauseFor: question.pause,
      listenFor: question.longest,
      cancelOnError: true,
    ),
  );

  void _ended({required bool fatal}) {
    if (_restarting) return;
    _question?.sessionEnded(fatal: fatal);
  }

  Future<void> _restart() async {
    final question = _question;
    if (question == null) return;
    _restarting = true;
    try {
      // The recogniser is still closing the session it just ended.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!question.isOver) await _session(question);
    } on Object {
      question.finish();
    } finally {
      _restarting = false;
    }
  }

  @override
  Future<void> stopListening() async => _question?.finish();

  @override
  Future<void> speak(String text) async {
    await _mouth.stop();
    await _mouth.speak(text);
  }

  @override
  Future<void> stopSpeaking() => _mouth.stop();
}

@Riverpod(keepAlive: true)
AskVoice askVoice(Ref ref) => DeviceAskVoice();

/// The read-aloud setting for this run of the app.
@Riverpod(keepAlive: true)
class AskReadAloudSetting extends _$AskReadAloudSetting {
  @override
  AskReadAloud build() => AskReadAloud.matchQuestion;

  void cycle() => state = state.next;
}
