/// The one public door of the barcode path. This test IS the contract lane M
/// wires to at merge: one import, one await, an [IngredientDraft] or null.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/ingredients/barcode/barcode_add.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../helpers/forui_semantics.dart';

const _foundBody = '''
{"code":"3017620422003","status":1,"product":{"code":"3017620422003",
"product_name":"Nutella","brands":"Nutella, Ferrero","quantity":"",
"nutrition_data_per":"100g","nutriments":{"energy-kcal_100g":539,
"proteins_100g":6.3,"carbohydrates_100g":57.5,"fat_100g":30.9}}}
''';

/// A host with a button that opens the surface exactly the way the
/// New-ingredient form's Source ▸ Barcode segment will.
Widget _host({
  required OffLookup lookup,
  required void Function(IngredientDraft?) onResult,
}) => MaterialApp(
  home: FTheme(
    data: ansiThemeData(),
    child: FScaffold(
      child: Builder(
        builder: (context) => FButton(
          onPress: () async {
            onResult(
              await scanBarcodeForDraft(
                context,
                lookup: lookup,
                cameraPane: (_, _) => const SizedBox.shrink(),
              ),
            );
          },
          child: const Text('Barcode'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('resolves with the draft the surface produced', (tester) async {
    filterForuiSemanticsAssertions();
    var called = false;
    IngredientDraft? result;
    await tester.pumpWidget(
      _host(
        lookup: OffLookup(
          client: MockClient((_) async => http.Response(_foundBody, 200)),
        ),
        onResult: (d) {
          called = true;
          result = d;
        },
      ),
    );

    await tester.tap(find.text('Barcode'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3017620422003');
    await tester.pump();
    await tester.tap(find.text('Look up'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result!.suggestedName, 'Nutella');
    expect(result!.sourceValue, 'off:3017620422003');
    expect(result!.attribution, 'Open Food Facts · ODbL');
    // Prefilled, never complete (D1): the caller still has to confirm, and
    // the draft brought no density to confirm with.
    expect(result!.densityGPerMl, isNull);
  });

  testWidgets('resolves null when the surface is closed empty', (tester) async {
    filterForuiSemanticsAssertions();
    var called = false;
    IngredientDraft? result;
    await tester.pumpWidget(
      _host(
        lookup: OffLookup(
          client: MockClient((_) async => http.Response(_foundBody, 200)),
        ),
        onResult: (d) {
          called = true;
          result = d;
        },
      ),
    );

    await tester.tap(find.text('Barcode'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.x));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, isNull);
  });
}
