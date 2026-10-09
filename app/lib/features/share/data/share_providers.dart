/// Riverpod wiring for a recipe's share link: the repository, the share host,
/// whether a recipe has a live link, and the hand-off to the platform.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/env.dart';
import '../../../core/sync/session.dart';
import '../domain/recipe_share_repository.dart';
import 'recipe_share_repository_impl.dart';

part 'share_providers.g.dart';

@Riverpod(keepAlive: true)
RecipeShareRepository recipeShareRepository(Ref ref) =>
    SupabaseRecipeShareRepository(ref.watch(supabaseClientProvider));

/// The share host's origin, or blank when this build offers no share link.
@Riverpod(keepAlive: true)
String shareBaseUrl(Ref ref) => Env.shareBaseUrl;

/// Whether [recipeId] has a live link, asked of the server when the page's
/// menu is built. An error means the page could not ask.
@riverpod
Future<bool> recipeShared(Ref ref, String recipeId) =>
    ref.watch(recipeShareRepositoryProvider).isShared(recipeId);

/// What became of a link handed to the platform.
enum LinkHandOff {
  /// The share sheet took it, or was dismissed — either way it was offered.
  offered,

  /// It was copied, because this platform has no share sheet to offer.
  copied,
}

/// Hands [url] to the platform: the share sheet on a phone, the clipboard in a
/// browser. [origin] anchors the sheet's popover on an iPad.
typedef HandOffLink =
    Future<LinkHandOff> Function({
      required String url,
      required String subject,
      Rect? origin,
    });

@Riverpod(keepAlive: true)
HandOffLink handOffLink(Ref ref) =>
    ({required url, required subject, origin}) async {
      // A browser without `navigator.share` gets a `mailto:` from the plugin,
      // which is not what a person asked for; the clipboard is.
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: url));
        return LinkHandOff.copied;
      }
      await SharePlus.instance.share(
        ShareParams(
          uri: Uri.parse(url),
          subject: subject,
          sharePositionOrigin: origin,
        ),
      );
      return LinkHandOff.offered;
    };
