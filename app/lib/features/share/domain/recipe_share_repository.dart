/// A recipe's share link: a public, read-only page addressed by a token the
/// server mints (pure Dart).
///
/// Every call here is a server call, not a local write. The share row is not
/// synced, so there is nothing to queue: offline, each one throws, and a link
/// that does not work yet is never handed to the share sheet.
library;

abstract interface class RecipeShareRepository {
  /// The recipe's live link token, minted when there is none.
  ///
  /// The same token while the link stands, so sharing twice sends the same
  /// URL. Throws when the server cannot be reached or refuses the recipe (not
  /// this household's, or deleted).
  Future<String> share(String recipeId);

  /// Revokes the recipe's live link. True when one was revoked, false when
  /// there was none. Throws when the server cannot be reached or refuses.
  Future<bool> unshare(String recipeId);

  /// Whether the recipe has a live link. Throws when the server cannot be
  /// reached; a caller that cannot tell offers no *Stop sharing*.
  Future<bool> isShared(String recipeId);
}

/// The public URL of a share [token] under [base], the share host's origin
/// (`https://getansi.app`). A trailing slash on [base] is not doubled.
String recipeShareUrl(String base, String token) {
  final origin = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$origin/r/$token';
}
