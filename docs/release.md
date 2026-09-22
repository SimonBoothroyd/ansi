# Release + deploy runbook

How a change on `main` becomes (a) an installed app on our phones and (b) the
schema and functions running on Supabase Cloud. Companion to
[`cloud-setup.md`](./cloud-setup.md), which is about *standing the cloud up*;
this file is about *shipping to it repeatedly*.

Two workflows do the mechanical parts:

- [`.github/workflows/release.yml`](../.github/workflows/release.yml) — app
  builds, triggered by pushing a `v*` tag.
- [`.github/workflows/deploy-supabase.yml`](../.github/workflows/deploy-supabase.yml)
  — migrations + edge function, triggered by a manual button.

> **Where this stands (2026-09-01).** The one-time setup below is **done**, and
> this file is a runbook, not a status page — read the setup sections to
> understand a mechanism or to rebuild it, not as a to-do list.
>
> - Repo: `github.com/SimonBoothroyd/ansi`, public. All four signing secrets,
>   both Supabase deploy secrets, the PowerSync deploy token, and the five
>   endpoint secrets (§2.3, §4.1) are set.
> - **Play is deliberately not used** (owner decision, 2026-09-03: the console
>   walk in §3a became a form-filling nightmare and was abandoned).
>   `PLAY_SERVICE_ACCOUNT_JSON` is intentionally unset, so `play-internal`
>   skips on every tag by design and the phones install the signed APK from
>   the GitHub Release (§3b's sideload fallback is the primary path). §3a
>   stays in this file as the record of what it would take, not as a to-do.
> - The Gradle signing block is committed (§1).
> - Play Console: the account exists, the **Ansi** app is created under the
>   permanent package `io.ansi.app`, the internal track and its tester list are
>   configured, and §3a's one-time walk is complete. **Do not walk §3a again** —
>   a second app under a different package can never update the installed one.
> - Tags shipped: one row per tag in [§3d](#3d-tags-shipped), append-only.

## What syncs how

Not everything is automated, and the split is deliberate: anything that can
mutate live household data stays a human act.

| What | How it ships | Trigger |
|------|--------------|---------|
| Android APK + AAB | `release.yml` → GitHub Release assets | `git push origin v0.1.0` |
| The phones | the signed APK from that GitHub Release, sideloaded (Play is deliberately unused — see the note above; §3a records what it would take) | same tag push |
| iOS build | `release.yml` → unsigned `.app` **artifact** (compile proof only, see §3) | same tag push |
| Migrations (`supabase/migrations/`) | `deploy-supabase.yml` → `supabase db push` | Actions → Run workflow |
| `import-recipe` edge function | `deploy-supabase.yml` → `supabase functions deploy` | same run |
| `import-receipt` edge function | `deploy-supabase.yml` → `supabase functions deploy` (same step, deployed by name beside it) | same run |
| `read-label` edge function | `deploy-supabase.yml` → `supabase functions deploy` (same step, deployed by name beside them) | same run |
| PowerSync sync streams ([`docker/powersync-cloud.streams.yaml`](../docker/powersync-cloud.streams.yaml)) | `deploy-supabase.yml` → `powersync deploy sync-config` | same run — also re-run after any cloud `db reset` |
| Function secrets (`ANTHROPIC_API_KEY`, `IMPORT_ALLOWED_HOUSEHOLDS` — one pair, read by all three model functions) | `supabase secrets set` | **human**, [cloud-setup §3b](./cloud-setup.md) |
| Template vocab reseed | `deploy-supabase.yml` → `seed_vocab.sql` → `seed_usda.sql` → `seed_usda_index.sql`, in that order | Actions → Run workflow with **`reseed_template`** ticked (re-runnable since migration `0020`) |
| Rolling a reseed onto existing households | [`supabase/rollout_ingredient_refresh.sql`](../supabase/rollout_ingredient_refresh.sql) (`ingredient` columns) + [`supabase/rollout_measure_refresh.sql`](../supabase/rollout_measure_refresh.sql) (measures), preview then run | **human**, [cloud-setup §2b](./cloud-setup.md) |
| Dashboard settings (auth hook, JWT audience, public sign-up) | Dashboards | **human**, cloud-setup's checklist |

**Order matters.** `db push` runs before an app build that writes new columns
reaches a device — a client writing a column the cloud schema lacks gets
`PGRST204`, and PowerSync then retries that upload forever, wedging sync
entirely rather than failing one row (cloud-setup §3b). So: deploy Supabase
first, tag the app second.

---

## 1. Prerequisite — the Gradle signing block

**Done.** `app/android/app/build.gradle.kts` carries the release signing block
on `main` (landed in `ee768e6`, "release signing + the permanent Play identity
io.ansi.app"), so `release.yml`'s first guard step passes. Keep it there: the
guard fails on purpose without it, because a `--release` build missing the
block is silently signed with the **debug** key — it installs fine and can then
never update a real install.

The block the pipeline is written against reads `android/key.properties` and
falls back to debug when it is absent:

```kotlin
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
```

…with a `release` signing config consuming exactly four keys — `storeFile`,
`storePassword`, `keyAlias`, `keyPassword` — and `buildTypes.release` selecting
it only when the file was found. `applicationId` is `io.ansi.app` (the permanent
Android identity, matching the OAuth deep-link scheme; changing it orphans every
installed copy).

Commit that file, then continue.

## 2. Configure the app-release secrets

### 2.1 Create the upload keystore (once, on your machine)

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**Back this file up somewhere durable.** Lose it and you can never ship an
update that existing installs will accept — the signature is the app's identity.
It is gitignored territory; it never enters the repo.

### 2.2 Base64 it

GitHub secrets hold text, so the keystore travels as base64:

```bash
# macOS
base64 -i ~/upload-keystore.jks | tr -d '\n' > /tmp/keystore.b64
# Linux
base64 -w0 ~/upload-keystore.jks > /tmp/keystore.b64
```

### 2.3 Set the secrets

Seven **secrets** — four for signing, three for the app's endpoints.
Placeholders below — substitute your real values.

```bash
# --- secrets: the signing material ---
gh secret set ANDROID_KEYSTORE_B64 < /tmp/keystore.b64
gh secret set ANDROID_KEYSTORE_PASSWORD   # prompts; the -storepass you chose
gh secret set ANDROID_KEY_ALIAS           # prompts; "upload" above
gh secret set ANDROID_KEY_PASSWORD        # prompts; the -keypass you chose

# --- secrets: the app's compile-time config ---
gh secret set SUPABASE_URL      --body 'https://<ref>.supabase.co'
gh secret set SUPABASE_ANON_KEY --body 'sb_publishable_…'
gh secret set POWERSYNC_URL     --body 'https://<id>.powersync.journeyapps.com'

rm /tmp/keystore.b64
```

A fifth secret, `PLAY_SERVICE_ACCOUNT_JSON`, enables the Play internal-track
upload. It is set at the end of the one-time console walk in §3a, because it
does not exist until you have created the service account there. Everything in
this section works without it.

**Why secrets for those three, when none of them is secret.** They are the
same `--dart-define`s `make run` passes, and the Supabase publishable key *is*
the anon key, public by design — it ships inside every APK, and RLS is the
actual protection (`app/lib/core/config/env.dart`,
[`SECURITY.md`](./SECURITY.md)). But the repo is public and the values name one
household's own project, so they are secrets for the masking: a secret never
prints in a log, a variable does. The cost is that "which project did this
build point at?" is answered from the secrets page, not the run page.

**Why four individual signing secrets rather than one `key.properties` blob.**
A blob would have to carry `storeFile`, and that path is a *runner* detail, not
yours — the workflow writes the keystore to `$RUNNER_TEMP` and fills in the
absolute path itself. (Gradle resolves a relative `storeFile` against
`android/app/`, not `android/`, so guessing it wrong is a silent "keystore not
found".) Splitting them also lets the guard step name the one you forgot.

### 2.4 What the guard checks

`release.yml`'s first job fails in ~15 seconds, before any SDK is fetched, if:

1. `app/android/app/build.gradle.kts` has no `key.properties` block (§1), or
2. any of the seven secrets above is empty — it prints the exact
   `gh secret set` lines for the missing ones.

Both failures otherwise produce a build that *succeeds* and ships the wrong
thing: a debug-signed APK, or an app compiled in local/dev mode pointing at
nothing.

It also *probes* for `PLAY_SERVICE_ACCOUNT_JSON`, but **never fails on it**.
Play is an additive delivery channel: without the key you still get a signed
APK and AAB on the Release, and only the phone-auto-update leg is skipped. The
guard prints a notice saying so and pointing at §3a.

## 3. Cut a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

That runs four jobs:

| Job | Runner | Does | Output |
|-----|--------|------|--------|
| `guard` | ubuntu | §2.4 checks only | pass/fail, plus the Play notice |
| `android` | ubuntu | decode keystore → write `android/key.properties` → `flutter build apk --release --target-platform android-arm64` (the phones are Pixels; one ABI, about 35 MB instead of a 94 MB fat APK) + `appbundle --release` (every ABI) with the three dart-defines | `ansi-v0.1.0.apk` + `ansi-v0.1.0.aab` on the **GitHub Release** for the tag, and an `android-release` artifact |
| `play-internal` | ubuntu | uploads that same AAB to the Play **internal** track (§3a) — **skipped by design** on every tag, since `PLAY_SERVICE_ACCOUNT_JSON` is deliberately unset | nothing, today |
| `ios` | macOS | `flutter build ios --release --no-codesign` | unsigned `Runner.app` **artifact** |

`android` needs `guard`. `play-internal` needs both, and is **skipped** (not
failed) when `PLAY_SERVICE_ACCOUNT_JSON` is absent or when the run isn't a tag.
`ios` needs nothing, so an expired signing secret never costs you the compile
signal.

`play-internal` re-uses the artifact `android` produced rather than rebuilding
— the binary on the Release and the binary on Play are byte-identical for a
given tag.

**Why iOS is a compile proof and nothing more.** Ansi is a two-person household
app installed from Xcode, not from the App Store. Real iOS signing in CI means
an Apple Developer account, a distribution certificate and provisioning profile
in secrets, a temporary keychain, and an export-options plist — a pile of
expiring machinery to produce an `.ipa` nobody installs. The job proves the
release configuration still compiles and stops there. The `.app` is unsigned, so
it is an artifact, never a Release asset.

CI sets `versionName` from the tag and `versionCode` from the run number — see
§3c, which is the rule you must not break by hand.

**Re-running a tag.** The publish step is re-runnable: if a Release already
exists for the tag it uploads with `--clobber` instead of failing. To rebuild
from different code you must move the tag (`git tag -f`, `git push -f origin
v0.1.0`) — which is a rewrite, so prefer a new patch tag.

**Rehearsing without a tag.** Actions → release → Run workflow. Everything runs
except the Release publish and the Play upload (both are gated on the ref being
a tag); the builds land as artifacts.

### 3a. One-time: Google Play internal testing

Goal: the Pixel updates itself from Play when you push a tag, with no APK
sideloading. This is a **one-time console walk**. Budget half an hour.

**Before you start, two things must be true:**

- **The Gradle signing block is committed** (§1 — satisfied since `ee768e6`).
  Still the hard prerequisite: Play binds your app to a signing identity on
  first upload.
- **The first AAB must be uploaded by hand.** The Play Developer API refuses to
  create a release for an app that has never had a binary in the console. So the
  API-driven pipeline cannot bootstrap itself; step 6 below does that once.

---

**1. Create the developer account.** <https://play.google.com/console/signup> —
one-time **$25**, personal account is fine. Expect an identity check that can
take a day or two; nothing below works until it clears.

**2. Create the app.** Play Console → **All apps → Create app**.

| Field | Value |
|---|---|
| App name | `Ansi` |
| Default language | your preference |
| App or game | App |
| Free or paid | Free |

Then Play Console → **Dashboard → set up your app** and work the declarations
(privacy policy, ads, content rating, target audience, data safety). They are
required even for a private internal-testing app — do the minimum honestly.

> **The package name is set by your first upload, not by a form**, and it is
> permanent. It must be exactly **`io.ansi.app`** — the `applicationId` in
> `app/android/app/build.gradle.kts`. A mismatch creates a *different app* that
> can never update the one on the phone.

**3. Enrol in Play App Signing.** This happens automatically on first upload for
new apps; confirm it at **Test and release → Setup → App signing**.

How this connects to the keystore from §2.1: with Play App Signing, **your
keystore becomes the *upload* key, not the app-signing key.** You sign the AAB
with it, Play verifies that signature, then re-signs the app with a key Google
holds for distribution. So it is one story, not two:

- `ANDROID_KEYSTORE_B64` and friends (§2.3) — still exactly what CI signs with.
- Lose that keystore and it is **recoverable**: you can register a new upload
  key with Play support. (Without Play App Signing, losing it would end the
  app's update path forever — which is why enrolling is the right call.)

**4. Create the internal testing track.** Play Console → **Test and release →
Testing → Internal testing → Testers** tab → **Create email list**. Add both
household emails — they must be the **Google accounts the phones sign in with**.

**5. Send the opt-in link.** Same screen → **Copy link** under "How testers join
your test". Open it on the Pixel, signed in as a tester, and accept. **This
opt-in is one-time and mandatory** — until it is accepted, Play shows the app as
unavailable no matter how many releases you push.

**6. The bootstrap upload (once).** Build the first AAB, then upload it by hand:

> **Use the CI artifact, not a laptop build.** Push a tag (or run the workflow
> manually), open the run, download the `android-release` artifact, and upload
> the `.aab` from it. That way the very first binary has the same provenance and
> the same versionCode sequence as every later one. A laptop build would carry
> pubspec's `+1` and burn a low versionCode CI then has to climb past (§3c).

Play Console → **Test and release → Testing → Internal testing → Create new
release** → upload the `.aab` → **Next → Save and publish**.

**7. API access.** Now wire the pipeline up.

1. Play Console → **Setup → API access**.
2. Link a Google Cloud project (**Create new project** is fine).
3. **Create service account** — this bounces you to the Cloud console:
   **IAM & Admin → Service accounts → Create service account**. Name it
   something like `play-ci`. No Cloud roles are needed. Create it.
4. On that service account → **Keys → Add key → Create new key → JSON**. It
   downloads once. Treat it as a credential.
5. Back in Play Console → **API access** → **Refresh service accounts**, find it,
   → **Manage Play Console permissions** → grant **Release manager** on the Ansi
   app (app-level, not account-wide) → **Invite user**.
6. Hand it to CI:

```bash
gh secret set PLAY_SERVICE_ACCOUNT_JSON < ~/Downloads/play-service-account.json
rm ~/Downloads/play-service-account.json
```

Permissions can take a few minutes to propagate; a first upload that 401s
immediately after step 5 usually just needs a re-run.

### 3b. The recurring flow

From here on it is the same one command as everything else:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

→ `guard` → `android` builds and signs → `play-internal` uploads the AAB to the
internal track as release `v0.2.0`, status `completed` → **Play notifies the
Pixel and it updates itself.**

Internal-track releases go live in **minutes, usually with no review** (that is
the whole point of the internal track versus closed/open testing). If the phone
is slow to notice, open the Play Store → **Manage apps & device** → pull to
refresh.

The GitHub Release still gets the APK too, so sideloading remains available as a
fallback that needs nothing from Google.

### 3c. The versionCode rule

**Play permanently rejects a `versionCode` it has already seen.** The number
must strictly increase, forever, across every upload for `io.ansi.app`.

pubspec's `version: 0.1.0+1` cannot carry that: `flutter.versionCode` reads the
`+N`, a hand-edited constant nobody remembers to bump.

> **The rule: `versionCode` = the `release` workflow's run number.**
> CI passes `--build-number=${{ github.run_number }}`. It increments on every
> run, never repeats, never goes backwards.

`versionName` is cosmetic (it is what Play displays) and tracks the tag:
`v0.2.0` → `0.2.0`. On a dispatch rehearsal there is no tag, so pubspec's stands.

Two ways to break this, both avoidable:

- **Never upload a locally built AAB to Play.** It carries pubspec's `+N` and
  burns a low versionCode CI must then climb past. This is why §3a step 6
  bootstraps from the CI artifact.
- **Never rename `.github/workflows/release.yml`.** `run_number` is per-file and
  would restart at 1 — every subsequent upload would be rejected as a duplicate.

You do not need to bump `pubspec.yaml` for a release any more; the tag is the
version of record. Keeping pubspec roughly in step is still tidy for local
builds, but nothing enforces it.

### 3d. Tags shipped

Append-only: one row per tag, newest last. Every tag since `v0.4.0` has put a
signed APK and AAB on its GitHub Release, with `play-internal` skipped by
design; through `v0.14.0` the APK was a fat build (88–94 MB) and from the next
tag it is arm64-only (about 35 MB). The AAB (76–83 MB) keeps every ABI. "Deploy" is the deploy-supabase run that
went first when the tag needed one.

| Tag | Date | What | Runs |
|-----|------|------|------|
| `v0.1.0` | 2026-09-01 | The first tagged build | — |
| `v0.2.0` | 2026-09-03 | The polish pass (plan 0022) — guard · android · ios green, the first signed APK + AAB on a Release | — |
| `v0.3.0` | 2026-09-03 | Field test round two (plan 0024) | — |
| `v0.4.0` | 2026-09-03 | Field test round three (plan 0025) | release 33758932599 |
| `v0.5.0` | 2026-09-04 | The state-of-the-world sweep (plan 0030), after the 0026–0031 cloud push | release 33903706382 |
| `v0.5.1` | 2026-09-04 | The import review fixes from the wild-garlic hunt; no migrations | release 33912875394 |
| `v0.6.0` | 2026-09-05 | Field test round five — seven plans built in parallel lanes; after the 0032–0034 cloud push | release 33961427290 · deploy 33961320740 |
| `v0.7.0` | 2026-09-08 | Field test round six — the four owner notes, the all-to-all unit rule and the vocabulary unit audit; shipped onto a cloud database **rebuilt from scratch** (owner call, cloud-setup §2c) | release 34237807444 · deploy 34237512787 |
| `v0.8.0` | 2026-09-08 | The piece weight — ADR-0015, plan 0042; after the 0039 cloud push with the template reseed ticked | release 34275484036 · deploy 34274932829 |
| `v0.9.0` | 2026-09-08 | Four owner notes built in parallel lanes — a camera door on the import form, an ingredient's name on a recipe line opens its page, a chip's new word keeps the sentence's case, a ⋯ toggle prints each line's macros; no migrations | release 34284901170 |
| `v0.10.0` | 2026-09-08 | The ingredient page reads before it edits — a fact sheet with Edit behind ⋯ — every default-unit chip live with the stranded refusal as the one gate, one density note instead of two, and typed names tidied when a field is left (Title Case for ingredients, a told suggestion with keep-the-old-word); no migrations | release 34300128198 |
| `v0.11.0` | 2026-09-09 | Five owner notes on v0.10.0 — chips take the sentence's case across every word and every name kind is Title Case, the default-unit row shows only what the row can say with one note for the rest, a new ingredient saves complete or not at all, a beverage's barcode label lands per 100 ml, and a photo import waits as long as the function can run behind a stage ladder; the two smoke files red on main green again; edge function redeployed first, no migrations | release 34411719268 · deploy 34409373514 |
| `v0.11.1` | 2026-09-09 | A UPC-A typed as the pack prints it — ten middle digits — is completed with its number-system and check digits instead of refused; no cloud step | release 34413971735 |
| `v0.11.2` | 2026-09-09 | A pack quantity with a stray comma and a label served by the cup no longer read as per 100 ml; no cloud step | release 34414628238 |
| `v0.12.0` | 2026-09-09 | The serving redrawn — the per-serving row loses its free-text field and takes any kitchen unit, the density sentence takes an amount and is the one place a density is stated, the serving is kept as a measure so the page prints the label's figures first, a scan seeds that serving from the pack's bracket, and fibre is the optional fifth macro — a total states it only when every line did; no cloud step (the seed's fibre reaches households on the next template reseed + rollout) | release 34423455276 |
| `v0.12.1` | 2026-09-09 | The macro fields as one sentence of inline slots, a scan with a printed serving landing in per-serving mode with the pack's figures, a nudge on a scanned per-100 row that names no serving, kcal whole and grams to one decimal wherever printed, and flame and wheat glyphs in the dense macro lines; no cloud step | release 34431917413 |
| `v0.12.2` | 2026-09-09 | The serving row at the same inline height as the figures, its unit picker sized to its word, and a gap between the two; no cloud step | release 34433442728 |
| `v0.12.3` | 2026-09-10 | The unit picker at the inline height, a stated density staying folded, and a scan naming a row whose only stamp was a borrowed density; no cloud step | release 34470260590 |
| `v0.13.0` | 2026-09-11 | Field test round seven — eight parallel lanes: kitchen fractions, one amount-and-unit control, measures renamed and reordered in place, one name namespace with a did-you-mean, the import cascade batched and its reading screen streamed from the server, the shop counting a row in the measure it was asked for, the seed as the owner's own snapshot, and a recipe varied for one week; after the 0040 cloud push with the template reseed ticked — the function and the app share one wire shape, so they shipped together | release 34561874981 · deploy 34561587312 |
| `v0.13.1` | 2026-09-11 | Field test round eight on v0.13.0 — the unit half of every sentence is the quantity sheet's own chip at one inline height, the ingredient form reopens in the mode the numbers were entered in with hints that say what to do, the USDA door drawn where it is needed, adding from a day asks only the slot, "Edit for this week" on Cook and Plan only, the import function streaming its model calls behind heartbeats, import's learned aliases held to the one namespace, and the allowed-units ladder applied once to the owner's vocabulary as a reviewed data pass; edge function and the 315-row template reseed first, no migrations | release 34658602960 · deploy 34658424680 |
| `v0.13.2` | 2026-09-11 | Field test round nine on v0.13.1 — the import reading marker spinning in place and its checklist in the tense it is in, an optional line wearing its tag on the editor row and that tag being the switch in week mode, and import's learning loop refusing a whole printed line as a name; edge function and the template reseed first, after eight learned aliases were retired on the owner's household, no migrations | release 34667784744 · deploy 34667684551 |
| `v0.14.0` | 2026-09-12 | Round ten — the recipe page up-levelled and optional as the cook's decision (plan 0044) — with the retire guard (migration 0041), the default-measure drop (migration 0042), an empty shelf's doors carrying their book, the Supabase CLI pinned by path, the schema doc learning drop column, and the seed re-exported from the owner's household with a reseed that now carries a re-weighed measure; after the 0041–0042 cloud push with the template reseed ticked (twice: the first reseed could not move Ginger's inch piece to 7 g) | release 34698039690 · deploy 34697520449 · deploy 34697917768 |
| `v0.15.0` | 2026-09-12 | Field test round eleven on v0.14.0 (plan 0045) — a flagged import amount prints empty instead of a unit the row cannot carry, the recipe editor's line opens into the review's card so a note can be set, and a household chooses the day its week starts with the flip re-homing its weeks on the server; after the 0043 cloud push, no reseed; a pre-existing red on main (tests reading the local-only gold corpus) fixed to skip | release 34712409998 · deploy 34711560878 |
| `v0.16.0` | 2026-09-13 | Field test round twelve on v0.15.0 (plan 0046) — ticked rows gather in a basket section that keeps its aisles, a meal's slot is a field of its editor and an add opens on the day's first unfilled slot, a piece-weighted row is bought in pieces, a measure that weighs a piece is the row's word for one at every door (ADR-0016; the owner re-pointed existing lines on cloud by hand), and the last tick bursts confetti; no migrations, no deploy | release 34728629162 |
| `v0.16.1` | 2026-09-13 | Three owner notes on v0.16.0, built in parallel lanes — the week's day foot and band read in the ingredient line's grammar (flame and sheaf, no `g`) with every unit glyph centred on the digits by construction and a pixel guard under the real fonts, the shop's confetti plays on every finishing tick rather than once per list, and the camera door photographs page after page with a question between them; no migrations, no deploy | release 34762113346 |
| `v0.17.0` | 2026-09-13 | Step 10 — wide screens on the web and on an iPad in landscape (plan 0047): one outer shell putting a rail or sidebar beside the content with every back rule unmoved and sheets presented as dialogs, one file reading the viewport and one wrapper applying the measure, Cook as a single schedule sheet, the Library as an open ledger, the Week as today beside the week's agenda, the recipe page and its editor in two columns, the import review in three with the read page beside the lines, the Shop's provenance pane and the vocabulary's two panes, a hover and a focus ring on every glyph control, and the URL following the route. The browser bundle builds in CI; no migrations. `import-recipe` gained two optional fields additively, so **a deploy-supabase run is owed** before a source span can light. **`pages` did not deploy** — the `github-pages` environment refuses a `v*` tag (§6.1), which failed the job and the run with it; `guard` · `android` · `web` · `ios` are green and the signed APK and AAB are on the Release | release 34801815051 (pages ✓ on the re-run, once the environment admitted the tag) |
| `v0.18.0` | 2026-09-14 | Field test round fourteen on v0.17.0 (plan 0048) — the wide Week swaps its panes, the agenda at left naming every meal in one small mono run with the phone's macro strip under each day and the week's band at its foot, the day pane at the phone's own meal size with the one add door; the serif has five named sizes and every title reads its role off the scale, held by a structural test; the wide vocabulary's pane draws no chrome while it loads, a pick is the URL and the lit row is scrolled on screen; the servings scaler is a control not a band, the search field is the app's type with its magnifier inset, the Shop's sync line keeps its height and a fast tick draws nothing; and a tap rules a method chip or a whole step off while you cook. No migrations; the deploy-supabase run 0047 owed was made before this landing | release 34920091755 |
| `v0.19.0` | 2026-09-17 | Food cost, phase one, and a meal eaten out (plan 0049) — receipts are the price table (0044, 0046: the pack kept in the words it was bought in), the price sheet and Price group with an edit and delete door on every row, the recipe panel flipping between Macros and Cost with one `Show line figures` toggle, the week band's cost to cook and the Shop's estimates, ADR-0017; a planned meal is a recipe, a bare ingredient or a meal eaten out (0045) read through one kind; the picker names a missed search; every type role names its face. Deploy 35288483877 went first | release 35290599044 |
| `v0.20.0` | 2026-09-18 | Food cost, phase two (plan 0049) — the `import-receipt` function reads a photographed receipt in the recipe import's two calls, joins overlapping shots by position, matches every line through the cascade and learns no alias; the Shop's scan door, the reading checklist, the review with its join card and money-first line cards, Save writing the receipt whole, the Receipts ledger by week and store, and the week band's spent line. No migrations; deploy-supabase (both functions) went first — run 35315258132 | release 35315449047 |
| `v0.21.0` | 2026-09-19 | The first receipt feedback pass, off the owner's own 29-line strip (plan 0049) — a dashed date parses, a paper printing no subtotal holds its lines against the total less tax and the join card says which figure it used, an unmatched card is titled by the printed name alone (`name_printed` rides the wire and is stored, migration `0047`), Bought is a calendar door, PRICE is a chip on every open card, and a saved receipt opens the same review with Save rewriting it in place and a delete under it; a line's twins on the same receipt are answered together, and the household's own saved lines are the match memory, recalled by printed name and still taught to no alias; *keep as a measure* names the word it actually buys and the house style it is written in, with one authoring rule behind every door that types a label, and a word that already says its size says it once; the unit picker drops the serving, opens on its first chip and leads with the imprecise default; a measure that lands leaves the form ready for the next and keeps the unit it was weighed in; a pack pre-fills from the printed name's last buy; the ingredient editor carries the Price group; and an aggregate that left a meal out reads `at least` on the recipe, the week band and the Shop. Also the Shop header's `receipts ›` door, the product spec's cost-and-receipts section and its `On receipts` section, and the recipe-measures frames drawn on the board as proposals only. Deploy 35475174213 went first; 35471848148 pushed `0047` and both functions an hour earlier and then failed on the sync-stream leg | release 35475474423 |
| `v0.22.0` | 2026-09-19 | The **reader** half of a recipe's own words (ADR-0018) — a recipe coins a named amount for a share of what it makes, `blob` = 15 g, each measure carrying its own unit and gated on a `makes` in that unit's family, with migration `0048` bringing the table and its `recipe_measure` sync stream; a component line is denominated in a unit *or* in one of those words, and a measured line is read, costed, cooked and shopped in the word it was written in and cannot be re-denominated behind the cook's back — the component chip row leads with the recipe's own words, the "used in" row stops reading a wordless line as batches, and the data layer says what a word *is* rather than how many fit. **No authoring door ships here**, which is the whole point of the two-release rollout: a build older than this tag crashes on a component line whose `unit` is null, so **both phones must be on `v0.22.0` or later before the release that lets anyone coin a measure**, and until that one lands nothing can write such a line. Also: a learned alias names a thing and not a decision — a decision word is matched with a plain pattern, and a seed guard refuses a decision-shaped row with no allowance — and the seed is regenerated from the owner's cleaned household, 323 ingredients (323 complete) · 326 measures · 157 aliases, its packaging labels in the house style `pack (N oz)`. Deploy 35480151258 went first with `reseed_template` ticked | release 35480850534 |
| `v0.23.0` | 2026-09-19 | The **authoring** half of a recipe's own measures (ADR-0018) — the recipe editor's MEASURES group under what the recipe makes, and the component amount sheet picking a measure or coining one behind its `+`, wherever a component's amount is edited. **Version floor:** a build older than `v0.22.0` casts a line's `unit` to a string and fails across the whole library once a measured line syncs, so every phone in a household must be on `v0.22.0` or later before anyone coins a measure. No migrations, no deploy | release 35486566126 |
| `v0.23.1` | 2026-09-20 | The review's fixes on `v0.23.0` — a recipe measure's unit must be in a measuring family (migration `0049`), a measure coined behind the `+` returns to the amount and reaches the row that says it, a measured line resolves its word by id, and the refusals say "measure"; on receipts, an edit tombstones only the lines it dropped, a failed write keeps the review, a receipt with every line dropped cannot be saved, a hand-typed receipt is not read as paper, and recall remembers "it is food" too; plus the docs tidy. Deploy 35517516397 went first | release 35517782927 |
| `v0.24.0` | 2026-09-20 | A receipt line carries a count — a count sub-row (`8 @ $2.99`) attaches to the line above it instead of becoming a junk line, so a price is paid ÷ (count × pack); the review gains a COUNT chip and reads `8 × block (16 oz)`. Migration `0050` (additive, default 1). Deploy 35534417017 went first | release 35535846613 |
| `v0.24.1` | 2026-09-20 | A line the reader missed is added by hand from the foot of the receipt's Lines list — picker, then price — and stores no printed words, so the match memory learns nothing from it; plus the board audited against the code. No migrations, no deploy | release 35540489722 |

## 4. Deploy Supabase

### 4.1 Configure it (once)

```bash
# Personal access token — supabase.com/dashboard/account/tokens
gh secret set SUPABASE_ACCESS_TOKEN

# The project's database password (Supabase → Project Settings → Database)
gh secret set SUPABASE_DB_PASSWORD

# Project ref — the <ref> in https://<ref>.supabase.co (a secret for the
# masking: it names the household's project and the repo is public)
gh secret set SUPABASE_PROJECT_REF --body '<ref>'

# PowerSync personal access token — powersync.com dashboard → account → tokens
gh secret set POWERSYNC_ADMIN_TOKEN

# PowerSync instance id — the <id> in https://<id>.powersync.journeyapps.com
# (the CLOUD_POWERSYNC_URL in cloud.env)
gh secret set POWERSYNC_INSTANCE_ID --body '<id>'
```

### 4.2 Run it

Actions → **deploy-supabase** → Run workflow. One job, in order:

1. **link** — `supabase link --project-ref $SUPABASE_PROJECT_REF`
2. **db push** — applies migrations the project has not seen (idempotent)
3. **functions deploy** — ships `import-recipe`, `import-receipt` and
   `read-label`, each by name
4. **sync streams** — validates then deploys
   `docker/powersync-cloud.streams.yaml` to the PowerSync instance
   (`powersync deploy sync-config`, CLI pinned). The CLI insists on a project
   directory even with an explicit file path, so the repo carries
   [`powersync/cli.yaml`](../powersync/README.md) — one line, `type: cloud`,
   and deliberately no `service.yaml` (that would let a run rewrite the
   instance config; only the sync config rides this button). This leg exists because of
   the 2026-09-01 outage: a cloud rebuild left the dashboard streams frozen at
   step 7.5, so `ingredient_measure` synced to no device while every
   repo-side check stayed green. Streams now ride the same button as the
   schema they must match — run this workflow after ANY cloud `db reset`,
   even one with no migration changes.

5. **reseed the template vocabulary** — only when the run was dispatched with
   **`reseed_template` ticked**: `seed_vocab.sql` → `seed_usda.sql` (skipped
   when the reference table is already populated; its 8,204 plain inserts
   never change between releases) → `seed_usda_index.sql`, in the runbook's
   order, against the member-less template household only. This is the
   **promote-to-template** leg of the cloud → seed direction: `seed_vocab.sql`
   is generated from an export of the owner's live household, and the button
   puts those curated rows back as the template new households clone.
   Re-runnable since migration `0020` (one live template row per
   `match_text`; the generated seed upserts on it). Tick it whenever
   `supabase/seed/**` or `supabase/seed_vocab.sql` changed.

Then it prints a step summary naming the legs it deliberately did not do.

### 4.3 The posture, and the trade

Dispatch-only, never push-triggered. A migration is immutable once applied to
cloud and a bad `db push` is not a revert away, so touching cloud stays a
deliberate act — CI's job is to make that act *one button with the right order
and credentials*, not to make it automatic on merge. This matches
[`supabase/AGENTS.md`](../supabase/AGENTS.md) ("migrations are immutable once
merged") and cloud-setup's insistence that dashboard state is walked by a human.

The trade being made knowingly: a Supabase PAT in CI is a credential that can
do anything to the project. It is accepted here because the repo is private,
the workflow cannot be triggered by a PR, and the alternative — running
`db push` from a laptop with the same token in a shell — is not safer, just
less repeatable. The repo being public does not change this: a workflow that
only runs on `workflow_dispatch` can be started only by a collaborator, and
GitHub never hands repository secrets to a workflow triggered from a fork.
What would change it is adding a push- or pull-request-triggered job that
reads the token — do not.

### 4.4 What this workflow will never do

- **Roll a reseed onto existing households**
  ([cloud-setup §2b](./cloud-setup.md)). A reseed updates the *template*
  household; households already onboarded keep their old clone until the §2b
  rollouts run — `rollout_ingredient_refresh.sql` for `ingredient` columns,
  `rollout_measure_refresh.sql` for measures. Preview first — each reports the
  per-household blast radius — then run it, then re-run the preview: every
  leg should read 0.
- **Set function secrets.** `ANTHROPIC_API_KEY` and `IMPORT_ALLOWED_HOUSEHOLDS`
  are `supabase secrets set` only ([cloud-setup §3b](./cloud-setup.md)). CI has
  no business holding them, and `supabase secrets list` shows names, not values.
- **Touch dashboard-only settings.** Auth hook, JWT audience, public sign-up —
  cloud-setup's checklist, walked by a human. (Sync streams left this list on
  2026-09-01: the workflow's step 4 deploys them via the PowerSync CLI.)

After a deploy, run [`scripts/cloud_verify.sh`](../scripts/cloud_verify.sh) and
record the run in cloud-setup's ledger.

## 5. Full ship checklist

1. `make ci` green locally.
2. Migrations or the edge function changed? Actions → deploy-supabase → Run
   workflow (§4.2).
3. Seed changed? Tick **`reseed_template`** on that same run (§4.2 step 5),
   then do cloud-setup §2b (§4.4) by hand if existing households need it.
   **The reseed handles renames, re-weighs and deletions itself.** The template on cloud
   is long-lived and the seed upserts by `match_text`, so a renamed row still
   arrives under its new key — but the generated file then soft-deletes every
   template row, measure and alias the snapshot no longer carries, and raises
   a notice saying how many went. The old name is retired by the same run that
   adds the new one. Read that notice: a count far off what you changed means
   the snapshot, not the template, is wrong. (Renames used to need a hand-run
   statement first; six of them once left five orphans to tombstone by hand.)
4. `scripts/cloud_verify.sh` clean.
5. `git tag vX.Y.Z && git push origin vX.Y.Z`. (No pubspec bump needed — the
   tag is the version of record, §3c.)
6. Watch the run: `guard` · `android` · `web` · `ios` green, `play-internal`
   skipped by design, and `pages` deployed — it skips itself where no host
   exists, and fails the whole run where the `github-pages` environment will
   not admit the tag (§6.1).
7. Install the APK from the GitHub Release on each phone. Sign in; confirm
   sync.
8. Add the tag's row to §3d, append the deploy to cloud-setup's ledger if
   there was one, and move the roadmap's untagged rows into Shipped.

## 6. Web — the browser build and its host

The same tag that builds the phones builds the browser. `release.yml`'s **web**
job runs `flutter build web --release` with the same three defines as `android`
and attaches the output as the `web-release` artifact; the **pages** job
publishes that artifact to GitHub Pages, and runs only on a tag, and only when
Pages is actually configured.

### 6.1 The host

Pages is **on**, with **Settings → Pages → Source: GitHub Actions** — not
"Deploy from a branch", which ignores the workflow and serves the repo. The
site's address is `https://simonboothroyd.github.io/ansi/`: a *project* site,
which is why the build's `--base-href` is `/<repo>/` rather than `/` and why a
bundle built for the root 404s every asset (§6.5). The browser origins a
sign-in needs are listed on the Supabase dashboard
([`cloud-setup.md` §1.6](./cloud-setup.md#1-supabase-cloud-project)). Switching
the host on was the owner's call to accept §6.2's trade — read that section
before changing anything here.

The `github-pages` deployment environment admits the default branch **and
`v*` tags** — every deploy here rides a tag, and an environment that admits
only its branch refuses it in a second (`Tag "vX.Y.Z" is not allowed to
deploy to github-pages due to environment protection rules`) and takes the
tag's whole release run red, because the job is not `continue-on-error`.
Deploying from `main` instead would publish a commit no tag names, which is
the wrong trade for a runbook built around the tag.

What a future operator re-checks, in this order:

1. `GET /repos/<owner>/<repo>/pages` answers at all (that call is the `web`
   job's own gate) and reports `build_type: workflow`.
2. The `github-pages` environment still admits `v*` tags (Settings →
   Environments → github-pages → Deployment branches and tags).
3. The origins in cloud-setup §1.6 still list the site, or "Continue with
   Google" is refused at the redirect rather than on the page.
4. `--base-href` still matches the path Pages serves the app from.

### 6.2 The trade: hosting publishes the endpoints

`--dart-define` values are compiled into `main.dart.js`. Hosting that file
means the Supabase URL, the Supabase anon key and the PowerSync URL are
readable by anyone who opens the page. The anon key is public by design — RLS
is the protection, see [`SECURITY.md`](./SECURITY.md) — but the two endpoints
are kept as repo *secrets* rather than variables precisely so a public repo
never prints them (§2.3), and this hands them out. What keeps that safe is the
ledger row nobody may relax: **public sign-up stays OFF**
([cloud-setup.md](./cloud-setup.md) checklist row 8). With sign-up closed, a
stranger holding the endpoints and the anon key can create no account, so
reaches no household's rows. Turning Pages on is the owner's call to accept
that; nothing in the repo makes it for them.

### 6.3 Two facts about the build

- **Cross-origin isolation is not required.** PowerSync's web build opens,
  writes and persists in Chrome with *and* without the COOP/COEP headers, which
  is what makes a static host viable at all — Pages cannot set headers. What is
  lost without them is `SharedArrayBuffer`: the database falls back to the
  worker's asynchronous access path instead of shared-memory synchronous
  access. It is slower under a heavy write burst and identical in behaviour;
  nothing in the app depends on it. **ADR-0002's "web support in PowerSync is in
  beta" line no longer holds** — an ADR is immutable, so it is corrected here:
  the web path is shipped, and this repo's own runs are the evidence.
- **The router stays on hash URLs** (`…/#/week`). Pages serves static files and
  cannot rewrite an unknown path back to `index.html`, so `usePathUrlStrategy()`
  would give clean URLs that 404 on every refresh and every shared link. It
  becomes a one-line change the day the app is hosted somewhere with an SPA
  rewrite. What each route puts *in* that hash, and why the bar follows a pushed
  page at all, is
  [`navigation.md` §7](./design-docs/navigation.md#7-the-url-is-the-route).

### 6.4 What a browser does not get

Three doors are gated, not broken — each says what it is rather than throwing:

| Door | On the web | Why |
|---|---|---|
| Take a photo (import) | one "Choose image files" door, and a line saying so | a tab has no camera door worth the name; `image_picker`'s web path is a file input |
| Crop / rotate a page | skipped; pages go up as chosen | `image_cropper` needs `WebUiSettings`, which means cropperjs in `index.html` and a `BuildContext` the provider has not got — disproportionate for a door reached from a phone |
| Scan a barcode | not offered; the typed barcode field is on the ingredient form as always | `mobile_scanner`'s web build fetches its detector from a CDN and then asks for a camera |

Each row is a `kIsWeb` branch with a test behind it, not a `try`/`catch` around
a plugin: the point is that the screen never offers what the platform cannot do.
The layout half of the web story is
[`wide-screen.md`](./design-docs/wide-screen.md); this table stays here with the
hosting.

### 6.5 Serving the build locally

```bash
cd app
flutter build web --release --base-href / \
  --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=… \
  --dart-define=POWERSYNC_URL=…
python3 -m http.server 8080 --directory build/web
```

`--base-href /` matters: the CI build uses `/<repo>/` for the project site, and
a bundle built for that path 404s every asset when served from the root.
Whatever port you use has to be a listed Supabase redirect origin before Google
sign-in works there (§6.1).
