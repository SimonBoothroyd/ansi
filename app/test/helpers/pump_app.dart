import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
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

  /// Pumps [child] the way the real app hosts it: a `WidgetsApp` (for the
  /// overlays and directionality Forui's popovers and sheets need), the Ansi
  /// [FTheme], and — the reason this helper exists — one [FToaster].
  ///
  /// Any screen that calls `ref.write` (`lib/shared/write.dart`) raises its
  /// failure toast through `showFToast`, which throws a [FlutterError] when it
  /// cannot find an `FToasterState` ancestor. A test that pumps such a screen
  /// under a bare `FTheme` fails on the *toaster*, not on the behaviour it was
  /// written to check.
  Future<void> pumpAnsiApp(
    Widget child, {
    List<Override> overrides = const [],
  }) {
    return pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: ansiHostTheme(),
          home: FTheme(
            data: ansiThemeData(),
            child: FToaster(child: child),
          ),
        ),
      ),
    );
  }
}
