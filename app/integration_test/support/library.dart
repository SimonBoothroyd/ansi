/// Driving the Library screen: its header `⋯` menu and the per-book card the
/// fold chevron and the book `⋯` live in.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

/// Opens the Library header's `⋯` — Ingredients · Account · New book ·
/// Reorder books (0028 E6 moved the session and the sync line to `/account`).
/// `.first`: the header's is the first ellipsis in the tree; every book card
/// and section carries one of its own after it.
Future<void> openLibraryMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(FLucideIcons.ellipsis).first);
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
