import 'package:ansi/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Result', () {
    test('Ok carries a value and maps', () {
      const r = Ok(2);
      expect(r.isOk, isTrue);
      expect(r.map((v) => v * 3), const Ok(6));
      expect(r.valueOrNull, 2);
    });

    test('Err carries a failure and short-circuits map', () {
      const r = Err<int>(Failure('x', 'nope'));
      expect(r.isOk, isFalse);
      expect(r.map((v) => v * 3), const Err<int>(Failure('x', 'nope')));
      expect(r.valueOrNull, isNull);
    });

    test('fold picks the right branch', () {
      const ok = Ok(1);
      const err = Err<int>(Failure('e', 'm'));
      expect(ok.fold((v) => 'ok', (f) => 'err'), 'ok');
      expect(err.fold((v) => 'ok', (f) => 'err'), 'err');
    });
  });
}
