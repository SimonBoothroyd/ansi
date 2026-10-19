import 'package:ansi/features/ask/domain/ask_spoken_question.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A recogniser-free run of one spoken question on a fake clock.
class _Run {
  _Run() {
    question = AskSpokenQuestion(
      onWords: (w, {required done}) {
        heard.add(w);
        if (done) sent.add(w);
      },
      restart: () => restarts++,
      stop: () => stops++,
    );
  }

  late final AskSpokenQuestion question;
  final heard = <String>[];
  final sent = <String>[];
  int restarts = 0;
  int stops = 0;
}

void main() {
  test('the phone ending its session early does not send the question', () {
    fakeAsync((clock) {
      final r = _Run()..question.start();
      r.question.heard('how much', isFinal: false);
      clock.elapse(const Duration(milliseconds: 900));
      // Android's own ~1 s silence: a final result, then the session ends.
      r.question.heard('how much', isFinal: true);
      r.question.sessionEnded();
      expect(r.sent, isEmpty);
      expect(r.restarts, 1);

      clock.elapse(const Duration(seconds: 1));
      r.question.heard('tamari', isFinal: false);
      expect(r.heard.last, 'how much tamari');

      clock.elapse(kAskPauseEndsQuestion - const Duration(milliseconds: 1));
      expect(r.sent, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(r.sent, ['how much tamari']);
      expect(r.stops, 1);
    });
  });

  test("a pause shorter than the app's keeps listening", () {
    fakeAsync((clock) {
      final r = _Run()..question.start();
      r.question.heard('start the', isFinal: false);
      clock.elapse(const Duration(seconds: 2));
      r.question.heard('start the simmer timer', isFinal: false);
      clock.elapse(const Duration(seconds: 2));
      expect(r.sent, isEmpty);
      clock.elapse(const Duration(seconds: 1));
      expect(r.sent, ['start the simmer timer']);
    });
  });

  test('a repeated partial does not hold the question open', () {
    fakeAsync((clock) {
      final r = _Run()..question.start();
      r.question.heard('open the aioli', isFinal: false);
      clock.elapse(const Duration(seconds: 2));
      r.question.heard('open the aioli', isFinal: false);
      clock.elapse(const Duration(milliseconds: 600));
      expect(r.sent, ['open the aioli']);
    });
  });

  test('silence before any word gives up after the first-word wait', () {
    fakeAsync((clock) {
      final r = _Run()..question.start();
      clock.elapse(kAskPauseEndsQuestion);
      r.question.sessionEnded();
      expect(r.sent, isEmpty);
      clock.elapse(kAskWaitForFirstWord);
      expect(r.sent, ['']);
    });
  });

  test('a lost mic ends the question with the words so far', () {
    fakeAsync((clock) {
      final r = _Run()..question.start();
      r.question.heard('how much salt', isFinal: false);
      r.question.sessionEnded(fatal: true);
      expect(r.sent, ['how much salt']);
      expect(r.restarts, 0);
    });
  });

  test('a tap finishes it once, and late results are ignored', () {
    fakeAsync((clock) {
      final r = _Run()..question.start();
      r.question.heard('make it 8', isFinal: false);
      r.question.finish();
      r.question.heard('make it 8 servings', isFinal: true);
      r.question.sessionEnded();
      clock.elapse(kAskListenFor);
      expect(r.sent, ['make it 8']);
      expect(r.restarts, 0);
    });
  });

  test('the question is capped at the longest listen', () {
    fakeAsync((clock) {
      final r = _Run()..question.start();
      for (var i = 1; i <= 30; i++) {
        r.question.heard('word ' * i, isFinal: false);
        clock.elapse(const Duration(seconds: 1));
      }
      expect(r.sent, hasLength(1));
    });
  });

  test('an answer that ends on a question asks back', () {
    expect(asksBack('Tamari in the sauce or the glaze?'), isTrue);
    expect(asksBack('Did you mean “step 3?”  '), isTrue);
    expect(asksBack('2 tbsp tamari — Ragù, serves 4.'), isFalse);
    expect(asksBack('Is it done? Taste it first.'), isFalse);
    expect(asksBack(''), isFalse);
  });
}
