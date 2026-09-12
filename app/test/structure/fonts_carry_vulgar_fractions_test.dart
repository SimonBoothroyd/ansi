/// The ruling `formatAmount` rests on, held by the fonts themselves.
///
/// The amount rule prints vulgar glyphs (`1½`, `⅔`). The reason it once did
/// NOT was a claim about the bundled faces — that they do not carry every one
/// of them, and a tofu box is worse than a slash. That claim is false, and a
/// claim about a binary asset is exactly the kind that rots silently: a font
/// swapped for a subset build would put tofu on every recipe page and no test
/// would notice.
///
/// So this reads each bundled `.ttf`'s own `cmap` table and asserts the nine
/// glyphs map to a glyph id. Pure Dart, no package: a font parser dependency
/// to check nine codepoints would be the heavier thing to trust.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The nine fractions `formatAmount` can print.
const _glyphs = ['½', '⅓', '⅔', '¼', '¾', '⅛', '⅜', '⅝', '⅞'];

void main() {
  final fonts =
      Directory('assets/fonts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.ttf'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the app bundles fonts to read', () {
    expect(fonts, isNotEmpty);
  });

  for (final font in fonts) {
    test('${font.uri.pathSegments.last} maps every vulgar fraction', () {
      final mapped = _mappedCodepoints(font.readAsBytesSync());
      for (final glyph in _glyphs) {
        expect(
          mapped.contains(glyph.runes.single),
          isTrue,
          reason: '$glyph is missing from ${font.uri.pathSegments.last}',
        );
      }
    });
  }
}

/// The codepoints [bytes]'s `cmap` maps to a non-zero glyph id, across every
/// format 4 (BMP) and format 12 (full-range) subtable it carries.
///
/// Only the codepoints asked about matter, so the walk collects the nine
/// rather than materialising a font's whole coverage.
Set<int> _mappedCodepoints(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final wanted = {for (final g in _glyphs) g.runes.single};
  final found = <int>{};

  final tableCount = data.getUint16(4);
  var cmapOffset = -1;
  for (var i = 0; i < tableCount; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag == 'cmap') cmapOffset = data.getUint32(record + 8);
  }
  if (cmapOffset < 0) return found;

  final subtableCount = data.getUint16(cmapOffset + 2);
  for (var i = 0; i < subtableCount; i++) {
    final record = cmapOffset + 4 + i * 8;
    final subtable = cmapOffset + data.getUint32(record + 4);
    switch (data.getUint16(subtable)) {
      case 4:
        found.addAll(_format4(data, subtable, wanted));
      case 12:
        found.addAll(_format12(data, subtable, wanted));
    }
  }
  return found;
}

/// A format 4 subtable's segment arrays, read for [wanted] only.
Set<int> _format4(ByteData data, int subtable, Set<int> wanted) {
  final found = <int>{};
  final segCountX2 = data.getUint16(subtable + 6);
  final endCodes = subtable + 14;
  final startCodes = endCodes + segCountX2 + 2;
  final idDeltas = startCodes + segCountX2;
  final idRangeOffsets = idDeltas + segCountX2;

  for (final code in wanted) {
    if (code > 0xFFFF) continue;
    for (var s = 0; s < segCountX2 ~/ 2; s++) {
      if (data.getUint16(endCodes + s * 2) < code) continue;
      if (data.getUint16(startCodes + s * 2) > code) break;
      final rangeOffset = data.getUint16(idRangeOffsets + s * 2);
      final int glyph;
      if (rangeOffset == 0) {
        glyph = (code + data.getInt16(idDeltas + s * 2)) & 0xFFFF;
      } else {
        final start = data.getUint16(startCodes + s * 2);
        final at = idRangeOffsets + s * 2 + rangeOffset + (code - start) * 2;
        if (at + 1 >= data.lengthInBytes) break;
        final raw = data.getUint16(at);
        glyph = raw == 0 ? 0 : (raw + data.getInt16(idDeltas + s * 2)) & 0xFFFF;
      }
      if (glyph != 0) found.add(code);
      break;
    }
  }
  return found;
}

/// A format 12 subtable's groups, read for [wanted] only.
Set<int> _format12(ByteData data, int subtable, Set<int> wanted) {
  final found = <int>{};
  final groups = data.getUint32(subtable + 12);
  for (var g = 0; g < groups; g++) {
    final group = subtable + 16 + g * 12;
    final start = data.getUint32(group);
    final end = data.getUint32(group + 4);
    final startGlyph = data.getUint32(group + 8);
    for (final code in wanted) {
      if (code < start || code > end) continue;
      if (startGlyph + (code - start) != 0) found.add(code);
    }
  }
  return found;
}
