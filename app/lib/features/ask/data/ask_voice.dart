/// Ansi's ears and voice: the phone's own speech recogniser and text-to-speech
/// engine. Nothing here leaves the phone except what the platform
/// recogniser itself sends; no audio reaches Ansi's servers.
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../domain/ask_read_aloud.dart';

part 'ask_voice.g.dart';

/// How long a pause ends a spoken question, which is then sent.
const kAskPauseEndsQuestion = Duration(seconds: 2);

/// The longest one spoken question may run.
const kAskListenFor = Duration(seconds: 30);

/// The mic and the speaker. The device one is [DeviceAskVoice]; tests fake it.
abstract interface class AskVoice {
  /// Starts listening. [onWords] hears the words so far, with `done` true
  /// once a pause has ended the question. Returns false when the phone has
  /// no recogniser or the mic was refused.
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
class DeviceAskVoice implements AskVoice {
  final SpeechToText _ears = SpeechToText();
  final FlutterTts _mouth = FlutterTts();
  bool? _ready;

  @override
  Future<bool> listen({
    required void Function(String words, {required bool done}) onWords,
  }) async {
    final ready = _ready ??= await _ears.initialize();
    if (!ready) return false;
    await _mouth.stop();
    await _ears.listen(
      onResult: (r) => onWords(r.recognizedWords, done: r.finalResult),
      listenOptions: SpeechListenOptions(
        pauseFor: kAskPauseEndsQuestion,
        listenFor: kAskListenFor,
        cancelOnError: true,
      ),
    );
    return true;
  }

  @override
  Future<void> stopListening() => _ears.stop();

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
