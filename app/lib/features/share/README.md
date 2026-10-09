# Feature: share

**Plan:** [0051 — a recipe's share link](../../../../docs/exec-plans/active/0051-recipe-share-link.md).

A recipe handed to someone outside the household as a link: a public,
read-only page of the recipe as it is now. This feature is the app's half —
the recipe page's ⋯ menu asks the server for the link and gives it to the
phone's share sheet, or takes it back. The page itself is served by an edge
function behind a Worker on the share host.

Nothing here is synced or stored on the device. The link is minted by the
server (`share_recipe`, migration 0054), which checks the recipe is this
household's; a client cannot write a share row. So every call is online, and
offline the one write door says "Couldn't share this recipe." rather than
queueing a link that does not work yet.

The menu offers **Share link** only when the build carries a share host
(`--dart-define=SHARE_BASE_URL=https://getansi.app`); a blank one hides it.
**Stop sharing** appears only while a link stands and the server has said so.

## Layout

```
share/
  domain/
    recipe_share_repository.dart   RecipeShareRepository (share · unshare ·
                                   isShared) · recipeShareUrl
  data/
    recipe_share_repository_impl.dart   the two functions and the table read
    share_providers.dart           the repository · shareBaseUrl ·
                                   recipeShared · handOffLink (the share
                                   sheet; the clipboard on the web)
  presentation/
    share_actions.dart             shareRecipeLink · stopSharingRecipe
```
