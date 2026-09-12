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
| PowerSync sync streams ([`docker/powersync-cloud.streams.yaml`](../docker/powersync-cloud.streams.yaml)) | `deploy-supabase.yml` → `powersync deploy sync-config` | same run — also re-run after any cloud `db reset` |
| Function secrets (`ANTHROPIC_API_KEY`, `IMPORT_ALLOWED_HOUSEHOLDS`) | `supabase secrets set` | **human**, [cloud-setup §3b](./cloud-setup.md) |
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
tag it is arm64-only (about 35 MB). The AAB (76–81 MB) keeps every ABI. "Deploy" is the deploy-supabase run that
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
3. **functions deploy** — ships `import-recipe`
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
6. Watch the run: `guard` · `android` · `ios` green, `play-internal` skipped
   by design.
7. Install the APK from the GitHub Release on each phone. Sign in; confirm
   sync.
8. Add the tag's row to §3d, append the deploy to cloud-setup's ledger if
   there was one, and move the roadmap's untagged rows into Shipped.
