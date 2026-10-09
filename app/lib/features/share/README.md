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

## The public page

`page/` is the page itself, in the app's own Dart and compiled to JS by
`make share-bundle` (`scripts/share_bundle.sh`). One bundle serves both ends:
the edge function renders the whole document with it — so the JSON-LD and a
link preview are in the served HTML — and the browser runs the servings
stepper and the method's timers with it. It reads the database's own rows
(`ShareTree.fromPayload`) through `recipes/domain/recipe_rows.dart` and
prints through the recipe page's own scaling, amounts, method fold and macro
walk, so a number on the page is the number in the app. Nothing under `page/`
may import Flutter: the compile refuses it, and CI compiles it.

`test/features/share/testdata/share_payload.json` is the payload contract by
example — the rows the edge function must select.

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
  page/                            PURE DART, compiled to JS
    share_payload.dart             ShareTree: the rows → the recipe and the
                                   sub-recipes it reaches
    share_page.dart                renderSharePage · renderShareBody ·
                                   shareJsonLd · shareAmountOf
    share_page_main.dart           the bundle's entry: ansiSharePage for the
                                   server; the stepper and timers in a browser
```
