/// Riverpod wiring for the books data layer.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../domain/book_repository.dart';
import 'book_repository_impl.dart';

part 'book_providers.g.dart';

@Riverpod(keepAlive: true)
BookRepository bookRepository(Ref ref) => SqliteBookRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
);
