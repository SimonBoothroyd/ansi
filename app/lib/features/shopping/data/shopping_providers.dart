/// Riverpod wiring for the shopping-list data layer.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../domain/shopping_repository.dart';
import 'shopping_repository_impl.dart';

part 'shopping_providers.g.dart';

@Riverpod(keepAlive: true)
ShoppingRepository shoppingRepository(Ref ref) => SqliteShoppingRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
);
