// The three faces reach the screen, or they do not — and the only way to know
// is to draw a control and read the style the engine was actually handed.
//
// This is the structural guard for one bug class: a text style that names no
// family. `TextStyle.fontFamilyFallback` answers for a glyph the face lacks,
// never for a face that was never named — a style with only a fallback list
// takes its primary family from the nearest DefaultTextStyle, so the same
// sentence is Inter inside a Forui surface and the Material host's own face
// outside one. The assertions below resolve the family on a button label, a
// menu item, a tab, a dialog and a bare app sentence, so a role that stops
// naming its face fails here rather than in a screenshot six weeks later.
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_modals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/forui_semantics.dart';

/// The family the engine would draw [text] in: the style on the painted span,
/// which is the merge of every [DefaultTextStyle] above it with the widget's
/// own.
String? familyOf(String text) {
  final spans = find
      .byType(RichText)
      .evaluate()
      .map((e) => e.widget as RichText)
      .where((rt) => rt.text.toPlainText() == text)
      .toList();
  expect(spans, hasLength(1), reason: 'expected exactly one "$text" on screen');
  return spans.single.text.style?.fontFamily;
}

/// The app as `app.dart` hosts it: the Material host under the Ansi [FTheme].
Widget _host(Widget child) => MaterialApp(
  theme: ansiHostTheme(),
  home: FTheme(data: ansiThemeData(), child: child),
);

void main() {
  test('the theme states the interface face rather than inheriting Forui’s '
      'default', () {
    expect(ansiThemeData().typography.fontFamily, ansiSansFamily);
  });

  test('every role names its own family, not just a fallback list', () {
    expect(ansiSans(size: 14).fontFamily, ansiSansFamily);
    expect(ansiSerif(size: AnsiType.row).fontFamily, 'Spectral');
    expect(ansiMono(size: 12).fontFamily, 'IBM Plex Mono');
    // And each keeps a stack behind it, for a glyph its own face lacks.
    expect(ansiSans(size: 14).fontFamilyFallback, contains(ansiSansFamily));
    expect(ansiSerif(size: AnsiType.row).fontFamilyFallback, contains('serif'));
    expect(ansiMono(size: 12).fontFamilyFallback, contains('monospace'));
  });

  testWidgets('a button, a menu item and a tab are all drawn in the interface '
      'face', (tester) async {
    filterForuiSemanticsAssertions();

    await tester.pumpWidget(
      _host(
        FScaffold(
          child: Column(
            children: [
              FButton(onPress: () {}, child: const Text('Save')),
              SizedBox(
                height: 140,
                child: FTabs(
                  children: const [
                    FTabEntry(label: Text('Recent'), child: SizedBox.shrink()),
                  ],
                ),
              ),
              FPopoverMenu(
                menuBuilder: (_, _, _) => [
                  FItemGroup(
                    children: [
                      FItem(title: const Text('Rename'), onPress: () {}),
                    ],
                  ),
                ],
                builder: (_, controller, _) => FButton(
                  onPress: controller.toggle,
                  child: const Text('More'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(familyOf('Save'), ansiSansFamily);
    expect(familyOf('Recent'), ansiSansFamily);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(familyOf('Rename'), ansiSansFamily);
  });

  testWidgets('a dialog keeps the two roles apart: a serif question over sans '
      'answers', (tester) async {
    filterForuiSemanticsAssertions();

    await tester.pumpWidget(
      _host(
        FScaffold(
          child: Builder(
            builder: (context) => FButton(
              onPress: () => askAnsi(
                context,
                title: 'Delete this book?',
                body: 'The recipes in it stay in the Library.',
                confirm: 'Delete',
              ),
              child: const Text('Ask'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();

    expect(familyOf('Delete this book?'), 'Spectral');
    expect(familyOf('Delete'), ansiSansFamily);
    expect(familyOf('Cancel'), ansiSansFamily);
  });

  testWidgets('app text holds its face outside a Forui surface, where the '
      'host would otherwise name one', (tester) async {
    // The regression this guard exists for. A Material ancestor sets a family
    // of its own (Roboto in a test binary, the platform's face on a device);
    // a style carrying only a fallback list would silently take it.
    await tester.pumpWidget(
      _host(
        Material(
          child: Column(
            children: [
              Text('interface', style: ansiSans(size: 14)),
              Text('Weeknight Curry', style: ansiSerif(size: AnsiType.row)),
              Text('300 g', style: ansiMono(size: 12)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(familyOf('interface'), ansiSansFamily);
    expect(familyOf('Weeknight Curry'), 'Spectral');
    expect(familyOf('300 g'), 'IBM Plex Mono');
  });
}
