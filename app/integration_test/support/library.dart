/// Driving the Library screen: its header `⋯` menu and the per-book card the
/// fold chevron and the book `⋯` live in.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

/// Opens `/account` from the Library header (0028 E1/E6) — the one control
/// left up there, and a link rather than a menu: the household, this device
/// and the session all live on the page it opens.
Future<void> openAccount(WidgetTester tester) async {
  await tester.tap(find.byIcon(FLucideIcons.users));
  await tester.pumpAndSettle();
}

/// The Ingredients shelf at the foot of the library (0028 E5) — a card like a
/// book's, so it is found by its name and opened by tapping it.
Future<void> openIngredientsShelf(WidgetTester tester) async {
  await tester.tap(find.text('Ingredients'));
  await tester.pumpAndSettle();
}

/// The book card for [name] — the nearest `ClipRRect` above the herb header's
/// title, which is the card's own clip (the host tests scope on the same
/// widget). A search result row prints `Book · Section` in ONE text widget,
/// so the exact title finder never matches it.
Finder bookCard(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(ClipRRect)).first;

/// Opens the `⋯` of the book card for [name]. `.first`: the book header's
/// menu comes before any of its sections' in the card.
Future<void> openBookMenu(WidgetTester tester, String name) async {
  await tester.tap(
    find
        .descendant(
          of: bookCard(name),
          matching: find.byIcon(FLucideIcons.ellipsis),
        )
        .first,
  );
  await tester.pumpAndSettle();
}
