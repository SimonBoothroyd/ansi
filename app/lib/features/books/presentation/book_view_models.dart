/// Riverpod ViewModels for the books UI.
///
/// [library] is a thin stream off the repository. Mutations don't need their
/// own notifier — views call the keep-alive `bookRepositoryProvider` directly,
/// which stays valid across the async gaps a dialog introduces (a short-lived
/// notifier would be disposed before its callback ran).
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/book_providers.dart';
import '../domain/book.dart';

part 'book_view_models.g.dart';

/// Every book with its sections and filed recipes, newest recipes first.
@riverpod
Stream<List<Book>> library(Ref ref) =>
    ref.watch(bookRepositoryProvider).watchLibrary();
