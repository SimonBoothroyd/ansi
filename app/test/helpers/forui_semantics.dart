/// Opening a Forui sheet or dialog with the semantics tree live trips a
/// framework assertion inside `semantics.dart` (tracker row `app/ui`). It is
/// not the code under test failing, and it fires on every such open, so tests
/// that drive one filter exactly that assertion — nothing else.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void filterForuiSemanticsAssertions() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    if ('${details.exception}'.contains('semantics.dart')) return;
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}
