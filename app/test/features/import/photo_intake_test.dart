import 'dart:typed_data';

import 'package:ansi/features/import/data/photo_intake.dart';
import 'package:ansi/features/import/data/remote_import_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('PhotoIntakeService.pickAndCrop', () {
    test('crops each picked page, in pick order', () async {
      final service = PhotoIntakeService(
        pickImages: (_) async => ['/a.jpg', '/b.jpg'],
        cropImage: (p) async => p.replaceAll('.jpg', '.cropped.jpg'),
      );
      expect(await service.pickAndCrop(PhotoSource.library), [
        '/a.cropped.jpg',
        '/b.cropped.jpg',
      ]);
    });

    test('asks the picker for the source the caller chose', () async {
      final asked = <PhotoSource>[];
      final service = PhotoIntakeService(
        pickImages: (source) async {
          asked.add(source);
          return ['/shot.jpg'];
        },
        cropImage: (p) async => p,
      );
      expect(await service.pickAndCrop(PhotoSource.camera), ['/shot.jpg']);
      expect(await service.pickAndCrop(PhotoSource.library), ['/shot.jpg']);
      expect(asked, [PhotoSource.camera, PhotoSource.library]);
    });

    test('drops just the page the user cancels in the cropper', () async {
      final service = PhotoIntakeService(
        pickImages: (_) async => ['/a.jpg', '/b.jpg', '/c.jpg'],
        cropImage: (p) async => p == '/b.jpg' ? null : p,
      );
      expect(await service.pickAndCrop(PhotoSource.library), [
        '/a.jpg',
        '/c.jpg',
      ]);
    });

    test('nothing picked → empty (the caller starts no import)', () async {
      final service = PhotoIntakeService(
        pickImages: (_) async => <String>[],
        cropImage: (p) async => p,
      );
      expect(await service.pickAndCrop(PhotoSource.library), isEmpty);
    });

    test('camera dismissed → empty, and the cropper never opens', () async {
      var cropped = 0;
      final service = PhotoIntakeService(
        pickImages: (_) async => <String>[],
        cropImage: (p) async {
          cropped++;
          return p;
        },
      );
      expect(await service.pickAndCrop(PhotoSource.camera), isEmpty);
      expect(cropped, 0);
    });

    test('every page cancelled → empty', () async {
      final service = PhotoIntakeService(
        pickImages: (_) async => ['/a.jpg', '/b.jpg'],
        cropImage: (_) async => null,
      );
      expect(await service.pickAndCrop(PhotoSource.library), isEmpty);
    });
  });

  group('downscaleForUpload', () {
    test('shrinks an oversized page so its longest edge hits the cap', () {
      final bytes = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 3000, height: 2000)),
      );
      final decoded = img.decodeImage(downscaleForUpload(bytes))!;
      expect(decoded.width, 1568); // longest edge capped
      expect(decoded.height, lessThan(2000));
    });

    test('leaves an already-small page untouched (same bytes)', () {
      final bytes = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 800, height: 600)),
      );
      expect(downscaleForUpload(bytes), same(bytes));
    });

    test('returns the original bytes for undecodable input', () {
      final junk = Uint8List.fromList([1, 2, 3, 4]);
      expect(downscaleForUpload(junk), same(junk));
    });
  });
}
