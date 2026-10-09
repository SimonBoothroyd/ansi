/// The two things a recipe page's menu does with a share link: hand it to the
/// platform, and take it back.
///
/// Both are server calls through the one write door, so offline says
/// "Couldn't share this recipe." rather than queueing a link that does not
/// work yet. Everything after an await goes through the container and host
/// captured before it.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_toast.dart';
import '../../../shared/write.dart';
import '../data/share_providers.dart';
import '../domain/recipe_share_repository.dart';

/// Asks the server for [recipeId]'s link — the standing one, or a new one —
/// and offers it through the share sheet, or copies it where there is none.
///
/// [anchor] is the widget the sheet should point at on an iPad: the menu's
/// trigger.
Future<void> shareRecipeLink(
  BuildContext context, {
  required String recipeId,
  required String title,
  required String base,
  BuildContext? anchor,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);
  final origin = _boundsOf(anchor ?? context);
  final repository = container.read(recipeShareRepositoryProvider);
  final handOff = container.read(handOffLinkProvider);
  final outcome = await container.write(host, 'share this recipe', () async {
    final token = await repository.share(recipeId);
    container.invalidate(recipeSharedProvider(recipeId));
    return handOff(
      url: recipeShareUrl(base, token),
      subject: title,
      origin: origin,
    );
  });
  if (outcome == LinkHandOff.copied) {
    // The host outlives the menu — see [hostContextOf].
    // ignore: use_build_context_synchronously
    showAnsiCopiedToast(host.context, what: 'Link');
  }
}

/// Asks before revoking [recipeId]'s link, then revokes it. Anyone holding
/// the old link finds nothing; a later share mints a new one.
Future<void> stopSharingRecipe(
  BuildContext context, {
  required String recipeId,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);
  final repository = container.read(recipeShareRepositoryProvider);
  final ok = await askAnsi(
    context,
    title: 'Stop sharing this recipe?',
    body:
        'Anyone who opens the link will find nothing there. Sharing again '
        'makes a new link.',
    confirm: 'Stop sharing',
    destructive: true,
  );
  if (!ok) return;
  await container.write(
    host,
    'stop sharing this recipe',
    () => repository.unshare(recipeId),
  );
  container.invalidate(recipeSharedProvider(recipeId));
}

Rect? _boundsOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
