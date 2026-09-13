/// What the photo door is in a browser: files in, no camera, no cropper.
///
/// Both halves are injected rather than read off `kIsWeb`, because the VM
/// these tests run on is never the web — a branch nobody can reach in a test
/// is a branch nobody can hold.
library;

import 'package:ansi/features/import/data/photo_intake.dart';
import 'package:ansi/features/import/presentation/import_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('cropSeam', () {
    test('on the web the page passes through untouched', () async {
      final crop = cropSeam(web: true);
      expect(
        await crop('blob:https://ansi.example/8f2c-1'),
        'blob:https://ansi.example/8f2c-1',
      );
    });

    test('a web import is every page chosen, in order, uncropped', () async {
      final service = PhotoIntakeService(
        pickImages: (_) async => ['blob:a', 'blob:b'],
        cropImage: cropSeam(web: true),
      );
      expect(await service.pickAndCrop(PhotoSource.library), [
        'blob:a',
        'blob:b',
      ]);
    });
  });

  group('ImportPhotoDoors', () {
    testWidgets('a phone offers the camera and the library', (tester) async {
      await tester.pumpAnsiApp(ImportPhotoDoors(onPick: (_) {}, web: false));
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose photos'), findsOneWidget);
    });

    testWidgets('a browser offers files, and says the crop is a phone job', (
      tester,
    ) async {
      final picked = <PhotoSource>[];
      await tester.pumpAnsiApp(ImportPhotoDoors(onPick: picked.add, web: true));

      expect(find.text('Take a photo'), findsNothing);
      expect(find.text('Choose image files'), findsOneWidget);
      expect(
        find.textContaining('cropping and rotating is a phone job'),
        findsOneWidget,
      );

      await tester.tap(find.text('Choose image files'));
      await tester.pumpAndSettle();
      expect(picked, [PhotoSource.library]);
    });
  });
}
