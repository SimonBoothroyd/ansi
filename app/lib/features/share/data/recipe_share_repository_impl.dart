/// [RecipeShareRepository] over the server's `share_recipe` and
/// `unshare_recipe` functions and the `recipe_share` table.
///
/// The table is read here directly because it is not synced: members may read
/// their household's rows, and RLS keeps every other household's out. The two
/// writes are functions because a client may not write the table at all — the
/// server mints the token and checks the recipe is this household's.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/recipe_share_repository.dart';

class SupabaseRecipeShareRepository implements RecipeShareRepository {
  const SupabaseRecipeShareRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> share(String recipeId) async {
    final token = await _client.rpc<dynamic>(
      'share_recipe',
      params: {'p_recipe_id': recipeId},
    );
    if (token is! String || token.isEmpty) {
      throw StateError('share_recipe answered without a token');
    }
    return token;
  }

  @override
  Future<bool> unshare(String recipeId) async {
    final revoked = await _client.rpc<dynamic>(
      'unshare_recipe',
      params: {'p_recipe_id': recipeId},
    );
    return revoked == true;
  }

  @override
  Future<bool> isShared(String recipeId) async {
    final rows = await _client
        .from('recipe_share')
        .select('id')
        .eq('recipe_id', recipeId)
        .isFilter('deleted_at', null)
        .limit(1);
    return rows.isNotEmpty;
  }
}
