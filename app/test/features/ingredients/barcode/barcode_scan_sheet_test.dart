/// The scan surface, driven headless down the **typed-number path** — the
/// same path the iOS Simulator walks, and the reason the board insists that
/// field is permanent (plan 0020 D3).
///
/// The camera itself is never fought here: [BarcodeScanSheet.cameraPane] is
/// injected, standing in for the plugin's preview. Each test's pane is a
/// plain widget, so what is under test is the sheet's own logic — debounce,
/// the three failure states, and what it resolves with.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mise/core/theme/mise_theme.dart';
import 'package:mise/features/ingredients/barcode/barcode_add.dart';
import 'package:mise/features/ingredients/barcode/barcode_scan_sheet.dart';
import 'package:mise/features/ingredients/barcode/off_lookup.dart';

const _foundBody = '''
{"code":"7394376616020","status":1,"product":{"code":"7394376616020",
"product_name":"Ruokaan Fraiche","brands":"Oatly","quantity":"200ml",
"nutrition_data_per":"100ml","nutriments":{"energy-kcal_100g":177,
"proteins_100g":1,"carbohydrates_100g":9,"fat_100g":15}}}
''';

const _code = '7394376616020';

/// Answers every request with a found product.
OffLookup _finds() =>
    OffLookup(client: MockClient((_) async => http.Response(_foundBody, 200)));

/// Forui's own widgets trip a framework semantics assertion in this harness;
/// the sibling sheet test filters it the same way.
void _filterSemanticsAssertions() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

/// Reports [code] to the sheet when tapped — the stand-in for the detector
/// seeing a barcode. Tapping twice is a detector firing on two consecutive
/// frames, which is what the debounce exists for.
class _TapToScan extends StatelessWidget {
  const _TapToScan({required this.onCode, required this.code});

  final ValueChanged<String> onCode;
  final String code;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onCode(code),
    child: const ColoredBox(color: Color(0xFF000000)),
  );
}

/// Collects what the sheet resolved with, and how often.
class _Resolver {
  IngredientDraft? draft;
  int count = 0;

  void call(IngredientDraft d) {
    draft = d;
    count++;
  }
}

/// Pumps the sheet's contents directly rather than through `showFSheet`, so
/// the resolved draft is observable and the tree stays small.
Future<void> _pump(
  WidgetTester tester, {
  required OffLookup lookup,
  _Resolver? resolver,
  BarcodeCameraPane? cameraPane,
}) async {
  _filterSemanticsAssertions();
  await tester.pumpWidget(
    MaterialApp(
      home: FTheme(
        data: miseThemeData(),
        child: FScaffold(
          child: BarcodeScanSheet(
            lookup: lookup,
            cameraPane: cameraPane ?? (_, _) => const SizedBox.shrink(),
            onResolved: resolver == null ? (_) {} : resolver.call,
            onDismiss: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _typeAndLookUp(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField), code);
  await tester.pump();
  await tester.tap(find.text('Look up'));
  // pumpAndSettle, not pump: Forui's buttons run a press animation, and a
  // still-ticking timer fails the test binding's teardown invariants.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the typed field is always there, beside the camera', (
    tester,
  ) async {
    await _pump(tester, lookup: _finds());

    // The no-permission, scuffed-label and simulator path — permanent, not
    // revealed by a failure (board frame d).
    expect(find.text('OR TYPE THE NUMBER'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('line up the barcode'), findsOneWidget);
    // The ODbL credit rides with anything OFF supplies.
    expect(
      find.text('Product data from Open Food Facts · ODbL'),
      findsOneWidget,
    );
  });

  testWidgets('a typed code resolves with a prefilled draft — and nothing '
      'about it says complete', (tester) async {
    final resolver = _Resolver();
    await _pump(tester, lookup: _finds(), resolver: resolver);

    await _typeAndLookUp(tester, _code);

    expect(resolver.count, 1);
    final draft = resolver.draft!;
    expect(draft.suggestedName, 'Ruokaan Fraiche');
    expect(draft.sourceValue, 'off:$_code');
    expect(draft.macrosBasis.dbValue, 'ml');
    expect(draft.densityGPerMl, isNull);
  });

  testWidgets('the Look up button stays dead until the digits are a barcode', (
    tester,
  ) async {
    await _pump(tester, lookup: _finds());

    await tester.enterText(find.byType(TextField), '739437');
    await tester.pump();

    expect(find.text('a barcode is 8 to 14 digits'), findsOneWidget);
    expect(
      tester.widget<FButton>(find.byType(FButton)).onPress,
      isNull,
      reason: 'a short code must not be spent against the 15/min budget',
    );
  });

  group('the three failure states land back on this surface', () {
    testWidgets('camera off — the honest message, and the typed field still '
        'finishes the job', (tester) async {
      final resolver = _Resolver();
      await _pump(
        tester,
        lookup: _finds(),
        resolver: resolver,
        // Exactly what the plugin's errorBuilder renders on a denied
        // permission — the real widget, not a mock of the copy.
        cameraPane: (_, _) => const CameraOffNotice(permissionDenied: true),
      );

      expect(find.text("Mise can't open the camera"), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.textContaining('both end in the same place'), findsOneWidget);

      // The point of the state: it is not a dead end.
      await _typeAndLookUp(tester, _code);
      expect(resolver.draft?.suggestedName, 'Ruokaan Fraiche');
    });

    testWidgets('unknown barcode — offers a blank draft carrying the code, '
        'never a half-invented one', (tester) async {
      final resolver = _Resolver();
      await _pump(
        tester,
        resolver: resolver,
        lookup: OffLookup(
          client: MockClient((_) async => http.Response('{"status":0}', 404)),
        ),
      );

      await _typeAndLookUp(tester, _code);

      expect(find.text("$_code isn't in Open Food Facts"), findsOneWidget);
      expect(
        resolver.count,
        0,
        reason: 'a failure resolves nothing on its own',
      );

      await tester.tap(find.text('Add it by hand'));
      await tester.pumpAndSettle();

      final draft = resolver.draft!;
      expect(draft.barcode, _code);
      expect(draft.suggestedName, '');
      expect(draft.macros, isNull);
      expect(draft.source, DraftSource.manual);
    });

    testWidgets('offline — says so, and Try again spends a second request '
        'that succeeds', (tester) async {
      final resolver = _Resolver();
      var attempts = 0;
      await _pump(
        tester,
        resolver: resolver,
        lookup: OffLookup(
          client: MockClient((_) async {
            attempts++;
            if (attempts == 1) {
              throw http.ClientException('Network is unreachable');
            }
            return http.Response(_foundBody, 200);
          }),
        ),
      );

      await _typeAndLookUp(tester, _code);

      expect(find.text("Can't reach Open Food Facts"), findsOneWidget);
      expect(
        find.textContaining('Everything else on the form works offline'),
        findsOneWidget,
      );

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(resolver.draft?.suggestedName, 'Ruokaan Fraiche');
    });
  });

  testWidgets('the detector firing on every frame spends one request', (
    tester,
  ) async {
    final resolver = _Resolver();
    var requests = 0;
    await _pump(
      tester,
      resolver: resolver,
      lookup: OffLookup(
        client: MockClient((_) async {
          requests++;
          return http.Response(_foundBody, 200);
        }),
      ),
      cameraPane: (_, onCode) => _TapToScan(onCode: onCode, code: _code),
    );

    final pane = find.byType(_TapToScan);
    await tester.tap(pane);
    await tester.tap(pane, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(pane, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(requests, 1, reason: 'single-fire on the same code');
    expect(resolver.count, 1, reason: 'and one draft, not three');
  });
}
