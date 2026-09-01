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

## What syncs how

Not everything is automated, and the split is deliberate: anything that can
mutate live household data stays a human act.

| What | How it ships | Trigger |
|------|--------------|---------|
| Android APK + AAB | `release.yml` → GitHub Release assets | `git push origin v0.1.0` |
| iOS build | `release.yml` → unsigned `.app` **artifact** (compile proof only, see §3) | same tag push |
| Migrations (`supabase/migrations/`) | `deploy-supabase.yml` → `supabase db push` | Actions → Run workflow |
| `import-recipe` edge function | `deploy-supabase.yml` → `supabase functions deploy` | same run |
| Function secrets (`ANTHROPIC_API_KEY`, `IMPORT_ALLOWED_HOUSEHOLDS`) | `supabase secrets set` | **human**, [cloud-setup §3b](./cloud-setup.md) |
| Template vocab reseed | SQL block, run by hand | **human**, [cloud-setup §2](./cloud-setup.md) |
| Rolling a reseed onto existing households | [`supabase/rollout_ingredient_refresh.sql`](../supabase/rollout_ingredient_refresh.sql), preview then run | **human**, [cloud-setup §2b](./cloud-setup.md) |
| Dashboard settings (auth hook, JWT audience, sync streams) | Dashboards | **human**, cloud-setup's checklist |

**Order matters.** `db push` runs before an app build that writes new columns
reaches a device — a client writing a column the cloud schema lacks gets
`PGRST204`, and PowerSync then retries that upload forever, wedging sync
entirely rather than failing one row (cloud-setup §3b). So: deploy Supabase
first, tag the app second.

---

## 1. Prerequisite — commit the Gradle signing block

**`app/android/app/build.gradle.kts` currently does NOT have the release
signing block committed.** It is modified-but-uncommitted in the working tree.
Until it lands on `main`, `release.yml` will fail its first guard step, on
purpose — because without it a `--release` build is silently signed with the
debug key, which installs fine and can then never update a real install.

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
it only when the file was found. `applicationId` is `io.mise.app` (the permanent
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

### 2.3 Set the secrets and variables

Four **secrets** (encrypted, never printed) and three **variables** (plain,
readable in logs). Placeholders below — substitute your real values.

```bash
# --- secrets: the signing material ---
gh secret set ANDROID_KEYSTORE_B64 < /tmp/keystore.b64
gh secret set ANDROID_KEYSTORE_PASSWORD   # prompts; the -storepass you chose
gh secret set ANDROID_KEY_ALIAS           # prompts; "upload" above
gh secret set ANDROID_KEY_PASSWORD        # prompts; the -keypass you chose

# --- variables: the app's compile-time config ---
gh variable set SUPABASE_URL      --body 'https://<ref>.supabase.co'
gh variable set SUPABASE_ANON_KEY --body 'sb_publishable_…'
gh variable set POWERSYNC_URL     --body 'https://<id>.powersync.journeyapps.com'

rm /tmp/keystore.b64
```

**Why variables and not secrets for those three.** They are the same
`--dart-define`s `make run` passes, and none of them is a secret: the Supabase
publishable key *is* the anon key and is public by design — it ships inside
every APK, and RLS is the actual protection (`app/lib/core/config/env.dart`,
[`SECURITY.md`](./SECURITY.md)). Making them repo variables buys something
real: they stay readable in the build log, so "which project did this build
point at?" is answerable from the run page instead of from a rebuild.

**Why four individual signing secrets rather than one `key.properties` blob.**
A blob would have to carry `storeFile`, and that path is a *runner* detail, not
yours — the workflow writes the keystore to `$RUNNER_TEMP` and fills in the
absolute path itself. (Gradle resolves a relative `storeFile` against
`android/app/`, not `android/`, so guessing it wrong is a silent "keystore not
found".) Splitting them also lets the guard step name the one you forgot.

### 2.4 What the guard checks

`release.yml`'s first job fails in ~15 seconds, before any SDK is fetched, if:

1. `app/android/app/build.gradle.kts` has no `key.properties` block (§1), or
2. any of the four secrets or three variables above is empty — it prints the
   exact `gh secret set` / `gh variable set` lines for the missing ones.

Both failures otherwise produce a build that *succeeds* and ships the wrong
thing: a debug-signed APK, or an app compiled in local/dev mode pointing at
nothing.

## 3. Cut a release

```bash
git tag v0.1.0
git push origin v0.1.0
```

That runs three jobs:

| Job | Runner | Does | Output |
|-----|--------|------|--------|
| `guard` | ubuntu | §2.4 checks only | pass/fail |
| `android` | ubuntu | decode keystore → write `android/key.properties` → `flutter build apk --release` + `appbundle --release` with the three dart-defines | `mise-v0.1.0.apk` + `mise-v0.1.0.aab` on the **GitHub Release** for the tag, and an `android-release` artifact |
| `ios` | macOS | `flutter build ios --release --no-codesign` | unsigned `Runner.app` **artifact** |

`android` needs `guard`; `ios` does not, so an expired signing secret never
costs you the compile signal.

**Why iOS is a compile proof and nothing more.** Mise is a two-person household
app installed from Xcode, not from the App Store. Real iOS signing in CI means
an Apple Developer account, a distribution certificate and provisioning profile
in secrets, a temporary keychain, and an export-options plist — a pile of
expiring machinery to produce an `.ipa` nobody installs. The job proves the
release configuration still compiles and stops there. The `.app` is unsigned, so
it is an artifact, never a Release asset.

Keep the tag and `pubspec.yaml`'s `version:` in step — the Android
`versionCode`/`versionName` come from pubspec, not from the tag.

**Re-running a tag.** The publish step is re-runnable: if a Release already
exists for the tag it uploads with `--clobber` instead of failing. To rebuild
from different code you must move the tag (`git tag -f`, `git push -f origin
v0.1.0`) — which is a rewrite, so prefer a new patch tag.

**Rehearsing without a tag.** Actions → release → Run workflow. Everything runs
except the Release publish (it is gated on the ref being a tag); the builds land
as artifacts.

## 4. Deploy Supabase

### 4.1 Configure it (once)

```bash
# Personal access token — supabase.com/dashboard/account/tokens
gh secret set SUPABASE_ACCESS_TOKEN

# The project's database password (Supabase → Project Settings → Database)
gh secret set SUPABASE_DB_PASSWORD

# Project ref — the <ref> in https://<ref>.supabase.co
gh variable set SUPABASE_PROJECT_REF --body '<ref>'
```

### 4.2 Run it

Actions → **deploy-supabase** → Run workflow. One job, in order:

1. **link** — `supabase link --project-ref $SUPABASE_PROJECT_REF`
2. **db push** — applies migrations the project has not seen (idempotent)
3. **functions deploy** — ships `import-recipe`

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
less repeatable. If the repo ever goes public, revoke the token first.

### 4.4 What this workflow will never do

- **Reseed the template vocab** ([cloud-setup §2](./cloud-setup.md)). A change
  to `supabase/seed/vocab.jsonl` or the generated `seed.sql` reaches cloud only
  when you run that block by hand (`seed_curation.sql` last).
- **Roll a reseed onto existing households**
  ([cloud-setup §2b](./cloud-setup.md)). A reseed updates the *template*
  household; households already onboarded keep their old clone until the §2b
  rollout runs. Preview first — it reports the per-household blast radius — then
  run it, then re-run the preview: every leg should read 0.
- **Set function secrets.** `ANTHROPIC_API_KEY` and `IMPORT_ALLOWED_HOUSEHOLDS`
  are `supabase secrets set` only ([cloud-setup §3b](./cloud-setup.md)). CI has
  no business holding them, and `supabase secrets list` shows names, not values.
- **Touch dashboard-only settings.** Auth hook, JWT audience, sync streams,
  public sign-up — cloud-setup's checklist, walked by a human.

After a deploy, run [`scripts/cloud_verify.sh`](../scripts/cloud_verify.sh) and
record the run in cloud-setup's ledger.

## 5. Full ship checklist

1. `make ci` green locally.
2. Migrations changed? Actions → deploy-supabase → Run workflow (§4.2).
3. Seed changed? Do cloud-setup §2, then §2b (§4.4) — by hand.
4. `scripts/cloud_verify.sh` clean.
5. Bump `version:` in `app/pubspec.yaml`, commit.
6. `git tag vX.Y.Z && git push origin vX.Y.Z`.
7. Download the APK from the Release; install; sign in; confirm sync.
