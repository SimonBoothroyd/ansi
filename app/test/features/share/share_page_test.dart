/// The share page's renderer, over the payload fixture the edge function and
/// the bundle smoke test also read: a recipe whose sub-recipe is said in its
/// own word, with a note, a timer and a title that carries markup.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/features/share/page/share_page.dart';
import 'package:ansi/features/share/page/share_payload.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _payload() =>
    (jsonDecode(
              File(
                'test/features/share/testdata/share_payload.json',
              ).readAsStringSync(),
            )
            as Map)
        .cast<String, Object?>();

ShareTree _tree([void Function(Map<String, Object?>)? edit]) {
  final payload = _payload();
  edit?.call(payload);
  return ShareTree.fromPayload(payload);
}

void main() {
  group('the payload', () {
    test('reads the recipe and the sub-recipe it reaches, once each', () {
      final tree = _tree();
      expect(tree.root.title, 'Miso Noodles <spicy>');
      expect([for (final c in tree.components) c.id], ['mb']);
      expect(tree.root.groups.single.items, hasLength(3));
      expect(tree.components.single.yields.single.qty, 150);
    });

    test('with no recipe row, refuses rather than drawing nothing', () {
      expect(
        () => ShareTree.fromPayload(const {'recipes': <Object?>[]}),
        throwsFormatException,
      );
    });
  });

  group('the body', () {
    test('at the recipe’s own servings', () {
      final body = renderShareBody(_tree(), 2);
      expect(body, contains('<span class="amt">400 g</span>'));
      // The recipe's own word, and the amount it stands for.
      expect(body, contains('<span class="amt">2 blob (30 g)</span>'));
      expect(body, contains('<a href="#component-mb">Miso butter</a>'));
      expect(body, contains('<span class="note">, light</span>'));
      expect(body, contains('<span class="chip">400 g udon</span>'));
      // A 4–5 min range starts at its middle, as the app's timer does.
      expect(body, contains('data-seconds="270"'));
      expect(body, contains('<output aria-live="polite">2 servings</output>'));
      expect(body, contains('id="component-mb"'));
      expect(body, contains('makes 150 g'));
      expect(body, contains('Beat the butter and miso together.'));
      // A title is text, never markup.
      expect(body, contains('Miso Noodles &lt;spicy&gt;'));
      expect(body, isNot(contains('<spicy>')));
    });

    test('scaled: every amount and chip moves, the word with its amount', () {
      final body = renderShareBody(_tree(), 4);
      expect(body, contains('<span class="amt">800 g</span>'));
      expect(body, contains('<span class="amt">4 blob (60 g)</span>'));
      expect(body, contains('<span class="amt">2 tbsp</span>'));
      expect(body, contains('<span class="chip">800 g udon</span>'));
      expect(body, contains('4 servings'));
      expect(body, contains('data-servings="3"'));
      expect(body, contains('data-servings="5"'));
      // The sub-recipe is drawn as written.
      expect(body, contains('<span class="amt">100 g</span>'));
    });

    test('one serving offers no fewer', () {
      final body = renderShareBody(_tree(), 1);
      expect(body, contains('aria-label="Fewer servings" disabled'));
    });

    test('macros per serving, by the app’s own walk', () {
      // 400 g udon at 130 kcal/100 g = 520; 1 tbsp soy (14.79 ml at 1.2 g/ml,
      // 53 kcal/100 g) = 9.4; two 15 g blobs of a 150 g batch of butter and
      // miso (816 kcal) = 163.2. Over 2 servings: 346.
      final body = renderShareBody(_tree(), 2);
      expect(body, contains('<dt>kcal</dt><dd>346</dd>'));
      // Per serving, so scaling does not move it.
      expect(renderShareBody(_tree(), 6), contains('<dd>346</dd>'));
    });

    test('a line with no nutrition leaves no total, and says why', () {
      final tree = _tree((p) {
        final lines = p['lines']! as List;
        (lines[2] as Map)['ingredient_status'] = 'stub';
      });
      final body = renderShareBody(tree, 2);
      expect(body, contains('No nutrition total'));
      expect(body, isNot(contains('<dt>kcal</dt>')));
      expect(shareJsonLd(tree, url: 'u'), isNot(contains('nutrition')));
    });
  });

  group('the JSON-LD', () {
    final ld = shareJsonLd(_tree(), url: 'https://getansi.app/r/t');

    test('is a schema.org Recipe with what a cook needs', () {
      expect(ld['@type'], 'Recipe');
      expect(ld['name'], 'Miso Noodles <spicy>');
      expect(ld['url'], 'https://getansi.app/r/t');
      expect(ld['totalTime'], 'PT25M');
      expect(ld['recipeYield'], ['2 servings']);
      expect(ld['recipeIngredient'], [
        '400 g Udon',
        '2 blob (30 g) Miso butter',
        '1 tbsp Soy sauce, light',
        '100 g Butter',
        '50 g White miso',
      ]);
      expect((ld['nutrition']! as Map)['calories'], '346 kcal');
    });

    test('makes the sub-recipe first, then the dish', () {
      final sections = ld['recipeInstructions']! as List;
      expect(
        [for (final s in sections) (s as Map)['name']],
        ['Miso butter', 'Miso Noodles <spicy>'],
      );
      final dish = (sections.last as Map)['itemListElement']! as List;
      expect((dish.first as Map)['text'], 'Boil the 400 g udon for 4–5 min.');
    });
  });

  group('the document', () {
    test('carries the preview tags, the JSON-LD and the data', () {
      final html = renderSharePage(
        _tree(),
        url: 'https://getansi.app/r/t',
        bundleUrl: '/r/share_page.js',
        payloadJson: jsonEncode(_payload()),
      );
      expect(html, startsWith('<!doctype html>'));
      expect(html, contains('<title>Miso Noodles &lt;spicy&gt;</title>'));
      expect(html, contains('<meta name="robots" content="noindex">'));
      expect(
        html,
        contains('<meta property="og:url" content="https://getansi.app/r/t">'),
      );
      expect(html, contains('<script type="application/ld+json">'));
      expect(html, contains('<script id="ansi-share-data"'));
      expect(html, contains('<script src="/r/share_page.js" defer>'));
    });

    test('a title cannot close the script it is embedded in', () {
      final payload = _payload();
      ((payload['recipes']! as List).first as Map)['title'] =
          '</script><script>alert(1)</script>';
      final html = renderSharePage(
        ShareTree.fromPayload(payload),
        url: 'u',
        bundleUrl: 'b',
        payloadJson: jsonEncode(payload),
      );
      expect(html, isNot(contains('</script><script>alert(1)')));
      expect(html, contains(r'<\/script><script>alert(1)<\/script>'));
    });
  });
}
