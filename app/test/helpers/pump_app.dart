import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// Riverpod 3 exposes the `Override` type via the misc.dart barrel rather than
// the main one. `ProviderScope.overrides` is typed `List<Override>`.
import 'package:hooks_riverpod/misc.dart' show Override;

/// Test-only helpers for pumping a widget under a Riverpod scope.
extension PumpApp on WidgetTester {
  /// Pumps [child] inside a [ProviderScope] with optional [overrides], so
  /// widget tests can inject fakes for repository/provider dependencies.
  Future<void> pumpApp(Widget child, {List<Override> overrides = const []}) {
    return pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: Directionality(textDirection: TextDirection.ltr, child: child),
      ),
    );
  }
}
