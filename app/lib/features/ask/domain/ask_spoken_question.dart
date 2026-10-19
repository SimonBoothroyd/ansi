/// When a spoken question is over. The app decides, not the phone's
/// recogniser: Android ends a listening session after its own short silence
/// (about a second) whatever pause it is asked for, which sent a question
/// while the member was still between words. So a session the recogniser
/// ends early is restarted, its words kept, and the question is done only
/// once the member has been quiet for [AskSpokenQuestion.pause].
library;

import 'dart:async';

/// How long a quiet member ends a spoken question, which is then sent.
const kAskPauseEndsQuestion = Duration(milliseconds: 2500);

/// How long the mic waits for a first word before giving up.
const kAskWaitForFirstWord = Duration(seconds: 6);

/// The longest one spoken question may run.
const kAskListenFor = Duration(seconds: 30);

/// One spoken question across however many recogniser sessions it takes.
class AskSpokenQuestion {
  AskSpokenQuestion({
    required this.onWords,
    required this.restart,
    required this.stop,
    this.pause = kAskPauseEndsQuestion,
    this.firstWord = kAskWaitForFirstWord,
    this.longest = kAskListenFor,
  });

  /// The words so far; `done` once, when the question is over.
  final void Function(String words, {required bool done}) onWords;

  /// Starts a new recogniser session after one ended early.
  final void Function() restart;

  /// Stops the recogniser for good.
  final void Function() stop;

  final Duration pause;
  final Duration firstWord;
  final Duration longest;

  String _kept = '';
  String _session = '';
  bool _live = false;
  bool _over = false;
  Timer? _quiet;
  Timer? _cap;

  String get words => [_kept, _session].where((w) => w.isNotEmpty).join(' ');

  bool get isOver => _over;

  /// The first session has started.
  void start() {
    _live = true;
    _quiet = Timer(firstWord, finish);
    _cap = Timer(longest, finish);
  }

  /// The recogniser heard [sessionWords] in the current session; `final`
  /// when it has closed that session's words.
  void heard(String sessionWords, {required bool isFinal}) {
    if (_over) return;
    if (sessionWords != _session) {
      _session = sessionWords;
      onWords(words, done: false);
      _quiet?.cancel();
      _quiet = Timer(pause, finish);
    }
    if (isFinal) _keep();
  }

  /// The recogniser's session ended. Unless [fatal] (the mic is gone, not
  /// just quiet), a new one starts and the question goes on.
  void sessionEnded({bool fatal = false}) {
    if (_over || !_live) return;
    _live = false;
    _keep();
    if (fatal) {
      finish();
      return;
    }
    _live = true;
    restart();
  }

  /// The question is over: by a pause, the cap, or the member's tap.
  void finish() {
    if (_over) return;
    _over = true;
    _quiet?.cancel();
    _cap?.cancel();
    stop();
    onWords(words, done: true);
  }

  void _keep() {
    if (_session.isEmpty) return;
    _kept = words;
    _session = '';
  }
}

/// Whether Ansi's [answer] asks the member something back ("Tamari in the
/// sauce or the glaze?"). After a spoken question such an answer opens the mic
/// for the reply, so a cook with full hands need not tap it.
bool asksBack(String answer) {
  final end = answer.trimRight().replaceFirst(RegExp(r'''["'”’)\]]+$'''), '');
  return end.endsWith('?');
}
