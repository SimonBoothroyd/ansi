import 'package:ansi/features/share/domain/recipe_share_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recipeShareUrl', () {
    test('puts the token under /r/ on the share host', () {
      expect(
        recipeShareUrl('https://getansi.app', 'abc_DEF-123'),
        'https://getansi.app/r/abc_DEF-123',
      );
    });

    test('does not double a trailing slash on the host', () {
      expect(
        recipeShareUrl('https://getansi.app/', 'abc_DEF-123'),
        'https://getansi.app/r/abc_DEF-123',
      );
    });

    test('keeps a host that is not at the root, such as workers.dev', () {
      expect(
        recipeShareUrl('https://ansi-share.example.workers.dev', 't'),
        'https://ansi-share.example.workers.dev/r/t',
      );
    });
  });
}
