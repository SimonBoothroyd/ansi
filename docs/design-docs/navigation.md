# Navigation — the shell, the back rule, the root-navigator rule

How a screen in Ansi gets on stage and how it leaves. Traced against the code
(design board: **Navigation · v2**).

Four tabs are the app's loop — **Library → Week → Cook → Shop**. Everything
else is a page pushed over them.

**On a wide window the loop stands beside the content instead of under it.**
From `lg` up an outer `ShellRoute` wraps the tab shell *and* every pushed page,
and its builder draws the four destinations as a sidebar (a 64 px icon rail with
tooltips below `xl`), with Account as its footer door — the only household door
there, so the Library's header does not draw a second one. It is drawn outside
the navigator that holds the pages, so a push does not animate it, duplicate it
or lose it. On a pushed page it goes **neutral**: nothing lit, because nothing
in the loop is where you are, and the page's own header chevron is the way back.
That is the same sentence the phone says by taking the bar away, in the one form
a sidebar can say it. Widths, forms and the full-pane opt-out:
[`wide-screen.md`](./wide-screen.md).

---

## 1. One bar, above four branches

`app/lib/core/router/app_router.dart` declares a **`StatefulShellRoute`** whose
four branches are the four tab roots (`/`, `/week`, `/cook`, `/shop`). Its
builder is `AnsiTabShell` (`app/lib/shared/ansi_tab_shell.dart`), which owns the
single `FScaffold(footer: AnsiBottomNav(...))`.

**The bar is one widget instance, and a tab switch cannot move it.** Switching a
tab changes an index *inside* the shell; the shell Navigator's page list does
not change, so no route transition runs. Before this, every tab screen built its own
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
| the bar item | the selected icon and label tick `mutedForeground → herbDeep`, 400 → 700 (plan 0025 D7d: `ansi_theme.dart` overrides only the selected variant's colour — 9.34:1 on the bar, 1.88:1 from the unselected — because on Cook and Shop the lit tab is the only thing naming the screen) |

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
| **The ingredient page while it is being EDITED** | leaves the editing posture, back onto the row's fact sheet — the same step the header chevron takes | held by that mode, so it resumes on the fact sheet one tap away |
| **A page landed on after an import commit or a NEW recipe's save** | pops to where it was opened from — the page replaced the flow that made it | works |
| **The recipe page after saving an EXISTING recipe** | the editor has popped back onto it; back pops to where the recipe was opened from | works |
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
`/ingredients/new`, `/ingredients/:id` and `/account` are **siblings of the tab
shell**, not children of a branch. They are pushed on the shell Navigator — the
one the outer shell owns, holding the tab shell and every page over it — so they
cover the bar and keep each platform's own push transition and back gesture. `/recipes/:id` is reachable from four
places in three different tabs; nesting it would mean either duplicating it per
branch or teleporting the user to the Library when they tap a recipe in Cook.
`/ingredients/:id` is in the same position: the manager's rows, the import
review's matched line, a recipe page's macro marker and — the plainest door —
an ingredient's own **name** on a recipe line all push it, from wherever the
reader happens to be.

It carries **two postures over one route**, the split `/recipes/:id` has
against `/recipes/:id/edit` — except that here the posture is page state
rather than a second route, so switching costs no push and back means one
thing. A row opens as a **fact sheet**, and `⋯ ▸ Edit` turns it into the form;
Save, Mark complete and back all put the form down onto the fact sheet again.
`?edit=1` opens it in the form instead, and a **door that exists to change a
field** hands it over: a recipe page's macro-panel fix marker, the import
review's piece-weight door, and the manager's "needs fleshing out" band. The
plain doors — a manager row, an ingredient's name on a recipe line — read.
`/ingredients/new` is always the form and is the one exit that still leaves
the page: it has no fact sheet behind it, so it **pops with the row it made**,
which is what the picker that pushed it awaits (below).

The bar being gone inside a recipe is the honest signal that you have left the
tab loop — the same rule the Ingredients manager already locked.

### Post-action navigation replaces; it does not flatten

After a **new** recipe's save or an import commit the app calls
**`context.pushReplacement`**, so the top page is swapped and whatever it was
opened from stays underneath. A `context.go` there replaces the whole match
list with one page: back left the app, and the iOS edge swipe vanished on a
page that looked exactly like a pushed one.

Saving an **existing** recipe **pops** instead. The rule is *editing returns
you to where you opened the editor; creating lands you on the thing you made*.
The editor was pushed over the recipe page, which is a watched query and
already shows the save; a replace there would stack a second copy of that
page over the first — `[shell, recipe, recipe]` — and cost a second back to
get past it. (Opened from somewhere else — Cook's gap card, the "set yield"
sub-editor — the pop returns there, which is still the right answer.)

The one exception is the **delete** case (`recipe_view.dart`), which keeps
`context.go('/')`. That page is pushed above the whole shell and the shell is
the bottom of the root stack, so `go('/')` lands on the Library branch exactly
there. A `pushReplacement('/')` would stack a *second* shell page over the first.

## 4. Modals open on the shell navigator

Under the shell, `Navigator.of(context)` inside a tab screen is the **branch**
Navigator, and Forui's `showFSheet`/`showFDialog` both default to
`useRootNavigator: false`. A modal opened that way is pushed inside the branch:
its barrier stops at the branch's bounds and **the bottom nav bar stays lit and
tappable beside it**.

So every modal goes through one wrapper each —
**`showAnsiSheet` / `showAnsiDialog`** (`app/lib/shared/ansi_modals.dart`) —
which pin it to the app's **shell** navigator (`ansiShellNavigatorKey`), the one
that holds the tab shell and every pushed page, and for sheets bake in the
geometry all of them asked for anyway (bottom-up, no height cap, safe-area
padded). `showAnsiSheet` also decides the modal's *form*: a bottom sheet on a
phone, a centred dialog from medium up ([`wide-screen.md`](./wide-screen.md)
§6), with the same builder and the same return value either way.

**The shell navigator, not the root above it.** A modal on the root would cover
the sidebar too, but it would also sit above the pushed pages — and a picker
that pushes the flesh-out form over its own surface and awaits the row it made
(§5) needs that form to land *on* the picker. A page and a modal stack in a
knowable order only when they share a navigator, so they do; the cost is that on
a wide window the barrier stops at the content pane and the sidebar stays
clickable beside an open dialog.

`Navigator.of(context).pop(result)` from inside a modal still dismisses the
modal: it is the nearest route either way. Only the owning Navigator changed.


### A sheet that closes itself pops once

A modal on the shell navigator sits directly above the tab shell's one page, so
a second pop is no longer a harmless no-op: it takes the shell with it, and
go_router asserts *"popped the last page off the stack"*. The trap is a sheet
that closes itself when its data disappears **and** also pops explicitly from
the action that removed it. Rule: an auto-dismiss fires only while the sheet is
still the current route —

```dart
if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop();
```

— and the explicit pop stays.

**No sheet in the app is currently in this shape.** The reference case was the
Week's `entry_sheet.dart`, which held both a live view of one plan entry and a
`Remove from the week` action; week v3 (E4) deleted it, and the removal moved
onto the row's own `−` where there is no sheet to pop. Its replacement,
`meal_editor_sheet.dart`, draws nothing when its entry vanishes and never pops
itself — one half of the trap, so the two halves can no longer meet.

The rule stays written down because the shape is easy to reintroduce: the
moment a sheet gains *both* a live read of a row and the action that deletes
that row, it is back. Pair it with a widget test that removes the row while
the sheet is open.


### A tab root leaves the keyboard inset to the shell

Forui's `FScaffold` shrinks its content by `MediaQuery.viewInsets.bottom`
while `resizeToAvoidBottomInset` is true (its default). Under the shell every
tab screen's scaffold is nested inside the shell's, so the same inset would be
subtracted twice — and on Android the inset can outlive the sign-in keyboard,
which left the Cook tab's list a few lines tall on the owner's Pixel
(2026-09-03; iOS never showed it). Rule: the four tab roots pass
`resizeToAvoidBottomInset: false`; the shell's scaffold owns the inset. Held by
`test/structure/tab_root_scaffold_test.dart`.

## 5. One tap, one page

Tap-driven navigation goes through `context.pushOnce` / `context.goOnce`
(`app/lib/shared/guarded_navigation.dart`): a push whose target is already the
router's top location is dropped, so a row hit twice before the first transition
paints opens one page. The dedupe is deliberately narrow — **same location
only** — so no tap that leads somewhere else is ever swallowed.

`pushOnce` is fire-and-forget on purpose: a tap that opens a page has nothing
to wait for. The one flow that genuinely continues after a page uses
`context.pushOnceFor<T>` — same guard, but it resolves with what the page pops.
That flow is the add-new chain (plan 0025 D3): a picker sheet has just created
an ingredient, pushes the flesh-out form *over its own sheet*, awaits back, and
only then resolves with the re-read row. It works because go_router inserts a
new page above a pageless sheet and returns to that sheet on pop — pinned by
the contract test — so the sheet is still there to resolve.

A menu item inside an `FPopoverMenu` **hides its popover before it navigates**.
Forui's `FItem` does not do this on its own and the menu content sits inside the
popover's own `TapRegion` group, so choosing an item is not an "outside tap".
Pushing first would leave the overlay parented to a page that is now underneath
— which is how you come back to a menu that is still open.

## 6. The auth gate is untouched by all of it

`/sign-in` and `/connecting` stay top-level siblings of the outer shell, so they
render on the root Navigator with no bar and no sidebar. The gate is a top-level `redirect` reading
`state.matchedLocation`, which is unchanged for a branch route — `/week` still
matches as `/week` — and the `?from=` round-trip still restores a deep link,
into the right tab. Keeping the Library at `/` rather than renaming it
`/library` is deliberate: every existing link, every `?from=` in flight and the
redirect's own `loc == '/'` case keep working untouched.

A cold deep link to a pushed page lands on the shell Navigator with **no tab
shell page beneath it**, so `canPop()` is false and the recipe header's
`canPop() ? pop() : go('/')` fallback is doing real work. That is the only
remaining case where a pushed page has no back gesture, and it is the correct
one.

## 7. What holds the rules

- `app/test/shared/ansi_tab_shell_test.dart` — the two back rules (asserted
  against the platform channel, so "leaves the app" is observed rather than
  inferred), re-tap-to-root, offstage-but-mounted, state across a switch.
- `app/test/shared/ansi_modals_test.dart` — each modal form opens above the
  branch while the branch's own navigator stays empty, the sheet/dialog split
  and its geometry, plus a **structural** test that fails the build if anything
  under `lib/` calls Forui's own `showFSheet`/`showFDialog`.
- `app/test/shared/ansi_wide_shell_test.dart` — the three chrome forms, the
  neutral sidebar on a pushed page, the back rules asserted again from inside
  the outer shell, a page pushed from inside a modal landing on it, and a
  **structural** test that every pushed page draws its own back control.
- `app/test/shared/guarded_navigation_test.dart` — the dedupe contract, plus a
  **structural** test that fails on a bare `context.push`/`go`/`pushReplacement`
  in a view, with a named exception list for the post-action landings.
- `app/integration_test/` (`make test-sim`, local-only; `backToShell` lives in
  `support/editor.dart`) — drives the real bar on a simulator;
  `backToShell`'s predicate is "the nav bar is in
  the tree", which holds precisely because pushed pages cover the shell.

---

## 8. What was refused, and why it stays refused

These are the alternatives that keep being proposed. Each was weighed once.

- **No per-screen bars, and no `NoTransitionPage`.** Hosting a bar per screen,
  or suppressing the push animation to hide the seam, treats the symptom: *it
  hides the slide without fixing anything behind it*, and the stack is still
  wrong underneath.
- **No fifth tab.** The four tabs are the loop — library, week, cook, shop. A
  vocabulary is reference data reached from the shelf it belongs to, not a
  destination of its own.
- **No swipe between tabs.** It would eat the iOS edge-swipe-back, which is
  the gesture every pushed page in the app depends on.
- **The line under all three:** *a slide is only honest when something can be
  dragged back the way it came.* A screen that animates in like a push must be
  poppable like one; anything else teaches a gesture that then fails.
