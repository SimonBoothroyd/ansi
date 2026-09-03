/// Two writers put a recipe row into the database — the editor's
/// `saveRecipe` and the import's `commit` — and for a year they wrote
/// different column lists: the import wrote times the editor could not see,
/// the editor wrote shelf life and filing the import never carried (plan
/// 0025 #4). One header form now feeds both, and this pins the tail end of
/// that seam: the two `INSERT INTO recipe` statements name the same columns
/// in the same order, and the editor's UPDATE sets every one of them that an
/// update can.
///
/// Read off the source, because the cheapest test of "same column list" is
/// the column list. Adjacent string literals are joined by stripping the
/// quotes, which is exactly how Dart joins them.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _editor = 'lib/features/recipes/data/recipe_repository_impl.dart';
const _import = 'lib/features/import/data/import_repository_impl.dart';

List<String> _insertColumns(String path) {
  final source = File(path).readAsStringSync();
  const head = 'INSERT INTO recipe (';
  final start = source.indexOf(head);
  expect(start, isNonNegative, reason: '$path has no INSERT INTO recipe');
  final end = source.indexOf('VALUES', start);
  final joined = source
      .substring(start + head.length, end)
      .replaceAll(RegExp("['\r\n]"), '');
  return _names(joined.split(')').first);
}

List<String> _updateColumns(String path) {
  final source = File(path).readAsStringSync();
  const head = 'UPDATE recipe SET ';
  final start = source.indexOf(head);
  expect(start, isNonNegative, reason: '$path has no UPDATE recipe SET');
  final end = source.indexOf('WHERE id', start);
  final joined = source
      .substring(start + head.length, end)
      .replaceAll(RegExp("['\r\n]"), '')
      .replaceAll(' = ?', '');
  return _names(joined);
}

List<String> _names(String list) =>
    list.split(',').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();

void main() {
  test('the import commit and the editor save insert the same recipe '
      'columns, in the same order', () {
    final editor = _insertColumns(_editor);
    final import = _insertColumns(_import);
    // A sanity floor: if the extraction drifts, fail loudly rather than
    // pass over two empty lists.
    expect(editor, containsAll(['title', 'keeps_for_days', 'book_id']));
    expect(import, editor);
  });

  test('the editor UPDATE sets every inserted column an update can', () {
    final inserted = _insertColumns(_editor).toSet()
      ..removeAll(['id', 'household_id', 'created_at']);
    expect(_updateColumns(_editor).toSet(), inserted);
  });
}
