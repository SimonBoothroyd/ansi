# Navigation — the shell, the back rule, the root-navigator rule

How a screen in Ansi gets on stage and how it leaves. Traced against the code
(design board: **Navigation · v2**).

Four tabs are the app's loop — **Library → Week → Cook → Shop**. Everything
else is a page pushed over them.

---

## 1. One bar, above four branches

`app/lib/core/router/app_router.dart` declares a **`StatefulShellRoute`** whose
four branches are the four tab roots (`/`, `/week`, `/cook`, `/shop`). Its
builder is `AnsiTabShell` (`app/lib/shared/ansi_tab_shell.dart`), which owns the
single `FScaffold(footer: AnsiBottomNav(...))`.

**The bar is one widget instance, and a tab switch cannot move it.** Switching a
tab changes an index *inside* the shell; the root Navigator's page list does not
change, so no route transition runs. Before this, every tab screen built its own
`FScaffold.footer` and a switch was a `context.go` that replaced the whole page —
two copies of the bar crossing over each other, always in the "forward"
direction whichever way you had moved along the bar.

Three consequences fall out of the structure rather than being features:

- **Each tab keeps its own Navigator, scroll offset and view state.** The Week's
  per-person lens is a filter the user *chose*; checking the cook plan does not
  discard it.
- **Each tab has its own history**, which is what makes a back rule expressible
  at all (§3).
- **All four branches stay mounted.** They read watched PowerSync queries, so an
  offstage tab keeps updating from the local database instead of going stale.

`StatefulShellRoute`, not the `.indexedStack` convenience constructor: that one
hard-wires its container and leaves no hook for the cross-fade.

## 2. The cross-fade — the only motion in a tab switch

`crossFadeBranchContainer` → `_CrossFadeBranches`, same file. The spec, exactly:

| | |
|---|---|
| duration | **120 ms** (`kTabFade`) |
| what moves | **nothing** — opacity only, zero translation, zero scale |
| curves | `easeOut` on the incoming branch, `easeIn` on the outgoing |
| the bar | completely static: it does not fade, move or rebuild |
| the bar item | the selected icon and label tick `mutedForeground → primary`, 400 → 700 |

A slide promises "this came from over there and you can send it back". That is
true of a pushed page and false of a sibling tab — which is why a directional
tab transition reads as wrong half the time. **Directionless for siblings,
directional for depth.** Setting `kTabFade` to `Duration.zero` is the hard-cut
comparison, and it is a one-constant change with no structural consequence.

The branch children keep a fixed slot in a `Stack` and are never reordered —
reordering them would lose element identity, and the tab state with it.

**A tab you are not looking at is `Offstage`** once the fade has settled (the
current branch and, while the fade runs, the outgoing one stay on stage). This
is not an optimisation: an invisible-but-onstage branch still answers hit tests,
still appears in the semantics tree a screen reader walks, and still matches a
default `find.*` in a test — the three tabs you are not looking at would answer
for text on the one you are. `RenderOffstage` still lays its child out with the
same constraints, so scroll offsets and view state survive untouched.

## 3. What back does, where

The rule is **stated**, not inherited from whatever a `context.go` left on the
stack. `AnsiTabShell` holds one `PopScope`: `canPop` is true only on the Library
branch, and an intercepted pop is spent on `goBranch(0)`.

| You are on… | Android back (button or edge gesture) | iOS left-edge swipe |
|---|---|---|
| **Library tab** | leaves the app — this is home | nothing (no gesture at a stack root) |
| **Week · Cook · Shop tab** | → the **Library tab**; a second back leaves | nothing |
| **A pushed page** (recipe · editor · import · ingredients) | pops to the tab under it | works — interactive, tracks the finger |
| **A page landed on after a save / import commit** | pops to where it was opened from | works |
| **A page landed on after a delete** | leaves the app — it *is* the Library tab now | n/a |
| **A modal sheet or dialog** | dismisses it | the sheet's own downward drag |
| **An open popover menu** | n/a — the menu closes itself the moment an item is chosen | n/a |
| **A cold deep link straight to a recipe** | leaves the app — there is genuinely nothing behind it | nothing, correctly |

Leaving takes **two** backs from any tab, and exactly two. Not a full tab
history: Library→Week→Library→Week is four backs to leave and the user cannot
see how deep they are, which is why Android moved away from that.

`android:enableOnBackInvokedCallback="true"` is set on `<application>`
(`app/android/app/src/main/AndroidManifest.xml`). Flutter requires that opt-in
and it is absent from Flutter's own app template, so without it
`PredictiveBackPageTransitionsBuilder` always falls through to the
`FadeForwards` fallback. With it, a pop runs the real Android-U predictive
transition, and a back at the Library tab previews the launcher — leaving is
something the user watches happen rather than something that happens to them.

### Pushed pages stay top-level

`/recipes/new`, `/recipes/:id`, `/recipes/:id/edit`, `/import`, `/ingredients`,
`/ingredients/:id` are **siblings of the shell**, not children of a branch. They
are pushed on the root Navigator, so they cover the bar and keep each platform's
own push transition and back gesture. `/recipes/:id` is reachable from four
places in three different tabs; nesting it would mean either duplicating it per
branch or teleporting the user to the Library when they tap a recipe in Cook.

The bar being gone inside a recipe is the honest signal that you have left the
tab loop — the same rule the Ingredients manager already locked.

### Post-action navigation replaces; it does not flatten

After a save or an import commit the app calls **`context.pushReplacement`**, so
the top page is swapped and whatever it was opened from stays underneath. A
`context.go` there replaces the whole match list with one page: back left the
app, and the iOS edge swipe vanished on a page that looked exactly like a pushed
one.

The one exception is the **delete** case (`recipe_view.dart`), which keeps
`context.go('/')`. That page is pushed above the whole shell and the shell is
the bottom of the root stack, so `go('/')` lands on the Library branch exactly
there. A `pushReplacement('/')` would stack a *second* shell page over the first.

## 4. Modals open on the root navigator

Under the shell, `Navigator.of(context)` inside a tab screen is the **branch**
Navigator, and Forui's `showFSheet`/`showFDialog` both default to
`useRootNavigator: false`. A modal opened that way is pushed inside the branch:
its barrier stops at the branch's bounds and **the bottom nav bar stays lit and
tappable beside it**.

So every modal goes through one wrapper each —
**`showAnsiSheet` / `showAnsiDialog`** (`app/lib/shared/ansi_modals.dart`) —
which set the root navigator, and for sheets bake in the geometry all of them
asked for anyway (bottom-up, no height cap, safe-area padded).

`Navigator.of(context).pop(result)` from inside a modal still dismisses the
modal: it is the nearest route either way. Only the owning Navigator changed.

## 5. One tap, one page

Tap-driven navigation goes through `context.pushOnce` / `context.goOnce`
(`app/lib/shared/guarded_navigation.dart`): a push whose target is already the
router's top location is dropped, so a row hit twice before the first transition
paints opens one page. The dedupe is deliberately narrow — **same location
only** — so no tap that leads somewhere else is ever swallowed.

A menu item inside an `FPopoverMenu` **hides its popover before it navigates**.
Forui's `FItem` does not do this on its own and the menu content sits inside the
popover's own `TapRegion` group, so choosing an item is not an "outside tap".
Pushing first would leave the overlay parented to a page that is now underneath
— which is how you come back to a menu that is still open.

## 6. The auth gate is untouched by all of it

`/sign-in` and `/connecting` stay top-level siblings of the shell, so they render
on the root Navigator with no bar. The gate is a top-level `redirect` reading
`state.matchedLocation`, which is unchanged for a branch route — `/week` still
matches as `/week` — and the `?from=` round-trip still restores a deep link,
into the right tab. Keeping the Library at `/` rather than renaming it
`/library` is deliberate: every existing link, every `?from=` in flight and the
redirect's own `loc == '/'` case keep working untouched.

A cold deep link to a pushed page lands on the root Navigator with **no shell
page beneath it**, so `canPop()` is false and the recipe header's
`canPop() ? pop() : go('/')` fallback is doing real work. That is the only
remaining case where a pushed page has no back gesture, and it is the correct
one.

## 7. What holds the rules

- `app/test/shared/ansi_tab_shell_test.dart` — the two back rules (asserted
  against the platform channel, so "leaves the app" is observed rather than
  inferred), re-tap-to-root, offstage-but-mounted, state across a switch.
- `app/test/shared/ansi_modals_test.dart` — each modal form opens on the root
  navigator while the branch's stays empty, plus a **structural** test that
  fails the build if anything under `lib/` calls Forui's own
  `showFSheet`/`showFDialog`.
- `app/test/shared/guarded_navigation_test.dart` — the dedupe contract, plus a
  **structural** test that fails on a bare `context.push`/`go`/`pushReplacement`
  in a view, with a named exception list for the post-action landings.
- `app/integration_test/app_test.dart` (`make test-sim`, local-only) — drives
  the real bar on a simulator; `backToShell`'s predicate is "the nav bar is in
  the tree", which holds precisely because pushed pages cover the shell.
