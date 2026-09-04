/// The seam plan 0025 #4 pins: ONE header form, TWO hosts. The form declares
/// its section list once (`kRecipeHeaderSections`), and both hosts — the
/// editor's notifier and the import review's controller — are asserted to
/// render every entry, so a section added to one cannot silently miss the
/// other (which is exactly how the review came to lack shelf life). The
/// host-contract half runs every setter against both hosts and reads the
/// result back off the `Recipe` each exposes.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/presentation/recipe_header_form.dart';
import 'package:ansi/features/recipes/presentation/recipe_view_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_import_repository.dart';
import '../../helpers/forui_semantics.dart';

const _books = [
  Book(id: 'b1', name: 'Our Cookbook'),
  Book(id: 'b2', name: 'Weeknights'),
];

/// A container holding both hosts over the same fakes, so the two halves of
/// every test below run against the same world.
ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      recipeRepositoryProvider.overrideWithValue(FakeRecipeRepo(null)),
      bookRepositoryProvider.overrideWithValue(
        const FakeBookRepository(_books),
      ),
      importRepositoryProvider.overrideWithValue(
        FakeImportRepo(
          const ReconciliationPayload(
            title: 'Weeknight Curry',
            servingsBase: 4,
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<RecipeHeaderHost> _editorHost(ProviderContainer container) async {
  // Held for the test's life: the editor is autoDispose, and a host that
  // vanished between two setters would be the test's bug, not the seam's.
  container.listen(recipeEditorProvider(null), (_, _) {});
  await container.read(recipeEditorProvider(null).future);
  return container.read(recipeEditorProvider(null).notifier);
}

Future<RecipeHeaderHost> _importHost(ProviderContainer container) async {
  container.listen(importControllerProvider, (_, _) {});
  final controller = container.read(importControllerProvider.notifier);
  await controller.startImport(const ImportFromUrl('x'));
  return controller;
}

/// Both hosts, by name, so a failure says which one dropped a section.
final _hosts = <String, Future<RecipeHeaderHost> Function(ProviderContainer)>{
  'the recipe editor': _editorHost,
  'the import review': _importHost,
};

Widget _form(ProviderContainer container, RecipeHeaderHost host) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: FScaffold(
            child: ListView(children: [RecipeHeaderForm(host: host)]),
          ),
        ),
      ),
    );

void main() {
  group('every section in kRecipeHeaderSections renders under', () {
    for (final MapEntry(key: name, value: hostOf) in _hosts.entries) {
      testWidgets(name, (tester) async {
        filterForuiSemanticsAssertions();
        tallSurface(tester);
        final container = _container();
        final host = await hostOf(container);
        await tester.pumpWidget(_form(container, host));
        await tester.pumpAndSettle();

        for (final section in kRecipeHeaderSections) {
          expect(
            find.text(section.label),
            findsOneWidget,
            reason: '$name does not render ${section.label}',
          );
        }
        // The rows inside the sections that were missing at review before
        // this seam existed — not just the eyebrows.
        expect(find.text('Keeps in the fridge'), findsOneWidget);
        expect(find.text('Freezes'), findsOneWidget);
        expect(find.text('Cook'), findsOneWidget);
        expect(find.text('Total'), findsOneWidget);
        // 0028 E9: FILE UNDER is one line stating where the recipe lives —
        // the recipe page's own eyebrow — not two selects to answer.
        expect(find.text('OUR COOKBOOK · UNSECTIONED'), findsOneWidget);
        expect(find.text('change'), findsOneWidget);
      });
    }
  });

  group('FILE UNDER is a fact you can change (0028 E9), on', () {
    for (final MapEntry(key: name, value: hostOf) in _hosts.entries) {
      testWidgets(name, (tester) async {
        filterForuiSemanticsAssertions();
        tallSurface(tester);
        final container = _container();
        final host = await hostOf(container);
        await tester.pumpWidget(_form(container, host));
        await tester.pumpAndSettle();

        // The line opens the picker rather than being one: the two selects
        // are absent until asked for.
        expect(find.text('Weeknights'), findsNothing);

        await tester.tap(find.text('OUR COOKBOOK · UNSECTIONED'));
        await tester.pumpAndSettle();
        expect(find.text('File under'), findsOneWidget);

        // And it still writes — the reason E9 demoted the control instead of
        // deleting it: this same form renders for every existing recipe, and
        // two creation doors have no shelf to inherit.
        await tester.tap(find.text('Our Cookbook').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Weeknights').last);
        await tester.pumpAndSettle();
        expect(host.header.bookId, 'b2');
      });
    }
  });

  group('every setter round-trips into the Recipe the host exposes, on', () {
    for (final MapEntry(key: name, value: hostOf) in _hosts.entries) {
      test(name, () async {
        final container = _container();
        final host = await hostOf(container);

        host
          ..setTitle('Weeknight Chicken Curry')
          ..setServings(6)
          ..setYield(250, g)
          ..setSecondYield(16, tbsp)
          ..setCookTime(35 * 60)
          ..setTotalTime(70 * 60)
          ..setKeepsForDays(4)
          ..setFreezable(true)
          ..setFreezerDays(30)
          ..setBook('b2')
          ..setSection('s1');

        final h = host.header;
        expect(h.title, 'Weeknight Chicken Curry');
        expect(h.servingsBase, 6);
        expect(h.yields, [(qty: 250.0, unit: g), (qty: 16.0, unit: tbsp)]);
        expect(h.cookTimeSeconds, 2100);
        expect(h.totalTimeSeconds, 4200);
        expect(h.keepsForDays, 4);
        expect(h.freezable, isTrue);
        expect(h.freezerDays, 30);
        expect(h.bookId, 'b2');
        expect(h.sectionId, 's1');

        // The shared rules hold on this host too: a book move clears the
        // section, and un-freezing drops the freezer window.
        host
          ..setBook('b1')
          ..setFreezable(false);
        expect(host.header.sectionId, isNull);
        expect(host.header.freezerDays, isNull);
      });
    }
  });
}
