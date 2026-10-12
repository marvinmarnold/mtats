# mtats Release Pipeline and Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a pushed `vX.Y.Z` tag into a Developer-ID-signed, notarized mtats DMG that installs cleanly, updates itself through Sparkle, and is downloadable from `https://mtats.app`, hosted in a dedicated GCP project.

**Architecture:** The existing SwiftPM build plus the hand-written Host relink (ADR-0005) gains a release configuration, a `Contents/Frameworks` layout, explicit inside-out signing, notarization and DMG packaging, and Sparkle. A two-job GitHub Actions workflow builds/signs/notarizes on macOS and publishes on Linux to a public Cloud Storage bucket plus Firebase Hosting (site, appcast, redirects) in GCP project `mtats-release`, authenticated by Workload Identity Federation.

**Tech Stack:** Swift 6.4 / Xcode 27.1, SwiftPM (`--build-system swiftbuild`), bash, `codesign`/`notarytool`/`stapler`/`hdiutil`, Sparkle 2 (binary target + CLI tools), GitHub Actions, gcloud, Firebase Hosting (`firebase-tools`), Cloud Storage, Astro.

**Spec:** `docs/superpowers/specs/2026-10-11-release-pipeline-design.md` (read it; this plan argues from it and cites its sections as "spec §…").

## Global Constraints

- Apple Silicon only, `LSMinimumSystemVersion` 14.0; `Package.swift` platform `.macOS(.v14)` stays.
- Every `swift build`/`swift test` passes `--build-system swiftbuild`.
- The only Host entitlement is `com.apple.security.cs.disable-library-validation`; the app is not sandboxed; `get-task-allow` must never be present in a release.
- The Sparkle feed URL baked into a release is exactly `https://mtats.app/appcast.xml`; the only published download URL is `https://mtats.app/download`. No `storage.googleapis.com` or `*.web.app` URL is ever baked into a tagged build.
- `CFBundleShortVersionString` = tag without `v`; `CFBundleVersion` = `git rev-list --count HEAD`, strictly increasing per channel.
- **Billing-isolation rule (spec §GCP):** every `gcloud`/`gsutil`/`firebase` command passes `--project mtats-release` explicitly. Never run `gcloud config set project`, `gcloud config configurations activate`, or `firebase use`. The owner's default config points at `petgo-play-ci` and must still point there after every task.
- No GCP resource is created, and nothing is pushed to GitHub other than branches/tags this plan names, without the owner's explicit go-ahead at the task that says so.
- Every new source file starts with `// SPDX-License-Identifier: MIT` (Swift) or `# SPDX-License-Identifier: MIT` (shell/YAML/Python).
- Third-party GitHub Actions are pinned to full commit SHAs (pinning procedure in Task 7, Step 4).
- Debug/dev builds (`Scripts/dev.sh`, `Scripts/package-app.sh` with no `-c`) keep working exactly as today at every commit.

## Review Focus

- **A debug and a release build on the same checkout**: the relink must link only the configuration being packaged; a reasonable person expects `package-app.sh -c release` after a debug build to ship release objects only. Test: Task 4, Step 7.
- **A dev build polling the production feed**: a debug package must contain no `SUFeedURL` and start no updater. Test: Task 3, Step 1 (`test-render-info-plist.sh`) and Task 12, Step 1.
- **Re-tagging the same commit or tagging off `main`**: a release whose build number does not exceed the channel's published maximum must fail before signing. Test: Task 14, Step 1 (`test-appcast-guard.sh`).
- **Tagging before `mtats.app` serves the feed**: preflight must refuse to print the tag command if `https://mtats.app/appcast.xml` is not a valid feed. Test: Task 14, Step 1 (`test-release-preflight.sh` feed check).
- **A DMG name that already exists in the bucket**: publishing must refuse to overwrite a released DMG. Test: Task 19, Step 1 (`test-publish.sh`).

## Rulings carried in this plan

- `generate_appcast` both signs the enclosure and writes the appcast, so the separate `sign_update` step in spec §Release flow step 9 is dropped; the EdDSA signature lands in the appcast either way. Cost if wrong: none — the signature is identical.
- Owner defaults adopted from spec §Open items (owner did not object when reviewing): WIF condition admits `refs/heads/main` for `site.yml`; bucket region `us-central1`; `www.mtats.app` redirects to `mtats.app`.

## File map

| File | Responsibility | Task |
|---|---|---|
| `Scripts/version.sh` | Print marketing version / build number from env or git | 3 |
| `Scripts/Host-Info.plist.template` | Host Info.plist source with `__TOKENS__` | 3, 13 |
| `Scripts/render-info-plist.sh` | Render the template for a configuration | 3 |
| `Scripts/check-bundle.sh` | Assert a packaged app's layout, linkage, plist, signature | 4, 5, 11 |
| `Scripts/package-app.sh` | Build + relink + assemble `.build/mtats.app` (`-c debug|release`) | 4, 11 |
| `Scripts/build-plugin.sh` | Build one plugin bundle for a configuration | 4 |
| `Scripts/sign-app.sh` | Inside-out signing, ad-hoc or Developer ID | 5 |
| `Scripts/mtats.entitlements` | Host entitlements | 5 |
| `Scripts/notarize.sh` | Submit, wait, staple, validate | 9 |
| `Scripts/make-dmg.sh` | Build the drag-to-Applications DMG | 9 |
| `Scripts/fetch-sparkle-tools.sh` | Pinned Sparkle CLI tools | 11 |
| `Sources/mtats/Updates.swift` | Sparkle wiring, channel selection, `UpdateControls` | 12 |
| `Scripts/appcast-guard.sh` | Fail if build number does not increase | 14 |
| `Scripts/notes-to-html.py` | Release notes Markdown → HTML for Sparkle | 14 |
| `Scripts/release-preflight.sh` | Local pre-tag checks | 14 |
| `Scripts/publish.sh` | Upload DMG/appcast/latest.json (no-clobber) | 19 |
| `Scripts/gcp-bootstrap.sh` | One-time GCP project setup | 16 |
| `Scripts/tests/*.sh` | Shell tests (one file per script) | 3–19 |
| `.github/workflows/ci.yml`, `release.yml`, `site.yml` | CI, release, site deploy | 7, 15/19, 17 |
| `site/` | Astro site, firebase config generator, placeholder feeds | 17, 18 |
| `Releases/<version>.md` | Release notes per version | 14 |

Shell tests run with `Scripts/tests/run.sh` (created in Task 3), which runs every `Scripts/tests/test-*.sh` and fails on the first failure.

---

### Task 0: Merge PR #1 and base this branch on `main` (owner gate)

**Files:** none changed.

**Interfaces:** Produces: `main` containing v1; branch `release-pipeline` rebased onto it.

- [ ] **Step 1: Owner visual check.** Ask the owner to run `cd ~/code/mtats/.worktrees/mtats-v1-implementation && Scripts/dev.sh` and confirm: four readings visible in the menu bar, each opens its dropdown, ⚙ opens Settings. Stop until the owner confirms.
- [ ] **Step 2: Verify `main`-to-be is green.**

Run: `cd ~/code/mtats/.worktrees/mtats-v1-implementation && swift test --build-system swiftbuild && Scripts/package-app.sh && Scripts/smoke-test.sh`
Expected: tests pass; smoke test prints `PASS`.

- [ ] **Step 3: Merge (owner go-ahead required — this publishes to `main`).** `gh pr merge 1 --merge --delete-branch=false` after the owner says merge.
- [ ] **Step 4: Branch protection on `main`.** `gh api -X PUT repos/marvinmarnold/mtats/branches/main/protection --input - <<'EOF'` with body `{"required_status_checks":null,"enforce_admins":false,"required_pull_request_reviews":{"required_approving_review_count":0},"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}` then `EOF`. Expected: JSON echo containing `"allow_force_pushes":{"enabled":false}`.
- [ ] **Step 5: Rebase.** `cd ~/code/mtats/.worktrees/release-pipeline && git fetch origin && git rebase origin/main`. Expected: clean rebase (the branch only adds docs).

---

### Task 1: Spike (b) — release relink, Sparkle, hardened runtime (throwaway)

Answers spec §Spikes (b). Throwaway branch; findings are recorded in the spec, code is not kept.

**Files:** throwaway branch `spike/release-relink`; then Modify: `docs/superpowers/specs/2026-10-11-release-pipeline-design.md` (Spikes table addendum) on `release-pipeline`.

- [ ] **Step 1: Branch.** `git switch -c spike/release-relink`
- [ ] **Step 2: Release build and find the objects.**

Run: `swift build -c release --build-system swiftbuild && find .build/out/Intermediates.noindex -path "*/mtats-p.build/Objects-normal/arm64/*.o" ! -name "*-testable.o" | sed 's#/[^/]*\.o$##' | sort -u`
Expected: one directory containing `/Release/` (record the exact path). If debug objects also exist, a second directory containing `/Debug/` appears — that confirms the duplicate-match risk.

- [ ] **Step 3: Relink against release products with the Frameworks rpath.**

```bash
OBJ_DIR=$(find .build/out/Intermediates.noindex -type d -path "*/Release/mtats-p.build/Objects-normal/arm64" | head -1)
mkdir -p /tmp/spike-b && swiftc -o /tmp/spike-b/mtats $(ls "$OBJ_DIR"/*.o | grep -v -- -testable.o) \
  -L .build/release -lMTatsPluginKit -Xlinker -rpath -Xlinker @executable_path/../Frameworks
otool -L /tmp/spike-b/mtats | grep MTatsPluginKit
nm /tmp/spike-b/mtats | xcrun swift-demangle | grep "protocol descriptor for MTatsPluginKit.PluginEntry"
```
Expected: `@rpath/libMTatsPluginKit.dylib`, and the descriptor line starts with whitespace then `U`.

- [ ] **Step 4: Sparkle as a binary target compiles and relinks.** Pick the newest Sparkle 2.x release at least 14 days old (`gh release list -R sparkle-project/Sparkle --limit 10`). Download its `Sparkle-for-Swift-Package-Manager.zip`, run `swift package compute-checksum <zip>`. In `Package.swift` add `.binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/<that version>/Sparkle-for-Swift-Package-Manager.zip", checksum: "<computed>")` and add `"Sparkle"` to the `mtats` executable target's dependencies. Add `import Sparkle` and `_ = SPUStandardUpdaterController.self` to the top of `Sources/mtats/main.swift`. Rebuild release, relink as Step 3 adding `-F "$(dirname "$(find .build/artifacts -path '*macos-arm64_x86_64/Sparkle.framework' -type d | head -1)")" -framework Sparkle`.
Expected: link succeeds; `otool -L` lists `@rpath/Sparkle.framework/Versions/B/Sparkle`; `swift test --build-system swiftbuild` still passes (the test bundle links Sparkle too).

- [ ] **Step 5: Hardened runtime + entitlement, ad-hoc.** Assemble a minimal bundle at `/tmp/spike-b/mtats.app` (copy `.build/mtats.app` from a debug package, replace `Contents/MacOS/mtats` with the relinked binary, move the dylib to `Contents/Frameworks/`, copy Sparkle.framework there without `Versions/B/XPCServices`), write the entitlements file from spec §Bundle layout to `/tmp/spike-b/e.plist`, sign inside-out with `codesign --force --options runtime --sign -` (dylib, Sparkle `Autoupdate`, `Updater.app`, framework, each plugin, then app with `--entitlements /tmp/spike-b/e.plist`). Run `/tmp/spike-b/mtats.app/Contents/MacOS/mtats --smoke-test-exit-after=3`.
Expected: prints `SMOKE_TEST_LOADED_WIDGET_IDS: cpu,gpu,...,network,ram` and no `SMOKE_TEST_DIAGNOSTIC` lines.

- [ ] **Step 6: Sparkle XPC services.** Read the pinned version's documentation page on sandboxing (`https://sparkle-project.org/documentation/sandboxing/`) and record whether a non-sandboxed app may omit `XPCServices`.
- [ ] **Step 7: Record and discard.** `git switch release-pipeline && git branch -D spike/release-relink`. Append one paragraph to the spec's Spikes section titled "Spike (b) outcome (date)": exact Release object directory pattern, whether a binary target worked, the Sparkle version + checksum chosen, XPC decision, and whether the fallback (direct `swiftc` compile) is needed. If the fallback is needed, stop and tell the owner — Task 4's relink step changes and this plan needs a revision for that task. Commit: `git commit -am "Record spike (b) outcome"` (message ends with the session's Co-Authored-By line).

---

### Task 2: Spike (a) — hosted runner toolchain and GUI smoke test (throwaway)

Answers spec §Spikes (a). Pushes a throwaway branch to GitHub (owner go-ahead required: it uses Actions minutes on the public repo).

**Files:** throwaway branch `spike/ci-runner` with `.github/workflows/spike-runner.yml`; then Modify the spec's Spikes section on `release-pipeline`. Produces: repository variables `MTATS_MACOS_RUNNER`, `MTATS_XCODE_PATH`, `MTATS_CI_SMOKE_TEST`.

- [ ] **Step 1: Workflow.**

```yaml
# SPDX-License-Identifier: MIT
name: spike-runner
on: push
jobs:
  probe:
    strategy:
      fail-fast: false
      matrix:
        image: [macos-latest, macos-15, macos-26]
    runs-on: ${{ matrix.image }}
    steps:
      - uses: actions/checkout@v4
      - run: sw_vers; uname -m; ls -d /Applications/Xcode*.app
      - name: Select newest Xcode
        run: |
          XC=$(ls -d /Applications/Xcode*.app | sort -V | tail -1)
          echo "Using $XC"; sudo xcode-select -s "$XC"; xcodebuild -version; swift --version
      - run: swift build --build-system swiftbuild
      - run: swift test --build-system swiftbuild
      - run: Scripts/package-app.sh
      - run: Scripts/smoke-test.sh
```

- [ ] **Step 2: Push (owner go-ahead).** `git switch -c spike/ci-runner origin/main && mkdir -p .github/workflows && <write file> && git add .github && git commit -m "Spike: probe hosted runners" && git push -u origin spike/ci-runner`
- [ ] **Step 3: Read results.** `gh run watch -R marvinmarnold/mtats $(gh run list -R marvinmarnold/mtats -b spike/ci-runner -L1 --json databaseId -q '.[0].databaseId')` then `gh run view --log-failed`. For each image record: Xcode path chosen, whether build/test/package passed, whether the smoke test printed `PASS`.
- [ ] **Step 4: Decide.**
  - If an image builds and the smoke test passes: `gh variable set MTATS_MACOS_RUNNER -b <image>`, `gh variable set MTATS_XCODE_PATH -b <xcode path>`, `gh variable set MTATS_CI_SMOKE_TEST -b "Scripts/smoke-test.sh"`.
  - If it builds but the smoke test fails on status-item creation: same first two variables, `gh variable set MTATS_CI_SMOKE_TEST -b "Scripts/smoke-test.sh --headless"`, and Task 6 is required.
  - If no image builds: stop and report to the owner (spec Decision 8 reopens: self-hosted runner). Do not continue to Task 7.
- [ ] **Step 5: Clean up and record.** `git push origin --delete spike/ci-runner && git switch release-pipeline && git branch -D spike/ci-runner`. Append "Spike (a) outcome (date)" to the spec's Spikes section with the table from Step 3 and the variables set. Commit.

---

### Task 3: Versioning and Info.plist template

**Files:**
- Create: `Scripts/version.sh`, `Scripts/Host-Info.plist.template`, `Scripts/render-info-plist.sh`, `Scripts/tests/run.sh`, `Scripts/tests/test-version.sh`, `Scripts/tests/test-render-info-plist.sh`

**Interfaces:** Produces: `Scripts/version.sh version|build` (stdout, honours `MTATS_VERSION`/`MTATS_BUILD`); `Scripts/render-info-plist.sh <out-plist> <debug|release>` (reads `MTATS_VERSION`/`MTATS_BUILD` or derives them via `version.sh`).

- [ ] **Step 1: Write the failing tests.**

`Scripts/tests/run.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
status=0
for t in Scripts/tests/test-*.sh; do
  if bash "$t"; then echo "PASS $t"; else echo "FAIL $t"; status=1; fi
done
exit $status
```

`Scripts/tests/test-version.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q && git config user.email t@t && git config user.name t
mkdir Scripts && cp "$ROOT/Scripts/version.sh" Scripts/
for i in 1 2 3; do git commit -q --allow-empty -m "c$i"; done

[[ "$(Scripts/version.sh build)" == "3" ]] || fail "build should be commit count 3"
[[ "$(MTATS_BUILD=99 Scripts/version.sh build)" == "99" ]] || fail "MTATS_BUILD override"
[[ "$(Scripts/version.sh version)" == 0.0.0-dev+* ]] || fail "untagged repo should give 0.0.0-dev+<hash>, got $(Scripts/version.sh version)"
git tag -a v1.2.3 -m v1.2.3
[[ "$(Scripts/version.sh version)" == "1.2.3" ]] || fail "tagged HEAD should give 1.2.3, got $(Scripts/version.sh version)"
[[ "$(MTATS_VERSION=4.5.6 Scripts/version.sh version)" == "4.5.6" ]] || fail "MTATS_VERSION override"
Scripts/version.sh bogus 2>/dev/null && fail "bad argument should exit non-zero"
exit 0
```

`Scripts/tests/test-render-info-plist.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PB=/usr/libexec/PlistBuddy

MTATS_VERSION=1.2.3 MTATS_BUILD=42 Scripts/render-info-plist.sh "$T/r.plist" release
plutil -lint -s "$T/r.plist" || fail "release plist invalid"
[[ "$($PB -c 'Print :CFBundleShortVersionString' "$T/r.plist")" == "1.2.3" ]] || fail "version"
[[ "$($PB -c 'Print :CFBundleVersion' "$T/r.plist")" == "42" ]] || fail "build"
[[ "$($PB -c 'Print :LSMinimumSystemVersion' "$T/r.plist")" == "14.0" ]] || fail "min OS"
grep -q "__" "$T/r.plist" && fail "unreplaced token in release plist"

# Review Focus: a debug package must never poll the production feed.
MTATS_VERSION=1.2.3 MTATS_BUILD=42 Scripts/render-info-plist.sh "$T/d.plist" debug
$PB -c 'Print :SUFeedURL' "$T/d.plist" >/dev/null 2>&1 && fail "debug plist must not contain SUFeedURL"
Scripts/render-info-plist.sh "$T/x.plist" bogus 2>/dev/null && fail "bad configuration should fail"
exit 0
```

- [ ] **Step 2: Run to verify they fail.**

Run: `chmod +x Scripts/tests/*.sh && Scripts/tests/run.sh`
Expected: `FAIL Scripts/tests/test-version.sh` and `FAIL Scripts/tests/test-render-info-plist.sh` (scripts missing).

- [ ] **Step 3: Implement.**

`Scripts/version.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: version.sh version|build
# version: MTATS_VERSION, else the tag at HEAD without "v", else 0.0.0-dev+<describe>.
# build:   MTATS_BUILD, else `git rev-list --count HEAD` (Sparkle orders by this; spec §Versioning).
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  version)
    if [[ -n "${MTATS_VERSION:-}" ]]; then echo "$MTATS_VERSION"; exit 0; fi
    if tag=$(git describe --tags --exact-match --match 'v*' 2>/dev/null); then echo "${tag#v}"; exit 0; fi
    echo "0.0.0-dev+$(git describe --tags --match 'v*' --always --dirty)" ;;
  build)
    if [[ -n "${MTATS_BUILD:-}" ]]; then echo "$MTATS_BUILD"; exit 0; fi
    git rev-list --count HEAD ;;
  *) echo "usage: version.sh version|build" >&2; exit 2 ;;
esac
```

`Scripts/Host-Info.plist.template` (Task 13 adds the two Sparkle keys):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>mtats</string>
  <key>CFBundleIdentifier</key><string>com.mtats.app</string>
  <key>CFBundleName</key><string>mtats</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>__BUILD__</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>© __COPYRIGHT_YEAR__ The mtats contributors, MIT License</string>
  <key>LSUIElement</key><true/>
  <key>SUFeedURL</key><string>https://mtats.app/appcast.xml</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict></plist>
```

`Scripts/render-info-plist.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: render-info-plist.sh <out-plist> <debug|release>
set -euo pipefail
OUT="$1"; CONFIG="${2:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
case "$CONFIG" in debug|release) ;; *) echo "configuration must be debug or release" >&2; exit 2 ;; esac
VERSION="$("$DIR/version.sh" version)"
BUILD="$("$DIR/version.sh" build)"
sed -e "s/__VERSION__/${VERSION//\//\\/}/" -e "s/__BUILD__/$BUILD/" -e "s/__COPYRIGHT_YEAR__/$(date +%Y)/" \
  "$DIR/Host-Info.plist.template" > "$OUT"
if [[ "$CONFIG" == debug ]]; then
  # Dev builds must never poll the production feed (spec §Versioning).
  /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$OUT"
fi
plutil -lint -s "$OUT"
```

- [ ] **Step 4: Run to verify they pass.**

Run: `chmod +x Scripts/version.sh Scripts/render-info-plist.sh && Scripts/tests/run.sh`
Expected: `PASS` for both test files.

- [ ] **Step 5: Commit.** `git add Scripts/version.sh Scripts/render-info-plist.sh Scripts/Host-Info.plist.template Scripts/tests && git commit -m "Add version derivation and Info.plist template"`

---

### Task 4: Release configuration and `Contents/Frameworks` layout

**Files:**
- Create: `Scripts/check-bundle.sh`, `Scripts/tests/test-package-release.sh`
- Modify: `Scripts/package-app.sh` (full replacement below), `Scripts/build-plugin.sh` (full replacement below)

**Interfaces:**
- Consumes: `Scripts/render-info-plist.sh <out> <config>` (Task 3); the Release object directory pattern recorded by Task 1.
- Produces: `Scripts/package-app.sh [-c debug|release]` → `.build/mtats.app`; `Scripts/check-bundle.sh <app> [--release] [--sparkle] [--signed]` (exit non-zero with a message on the first failed assertion); `Scripts/build-plugin.sh <Name> <PrincipalClass> [debug|release]`.

- [ ] **Step 1: Write the bundle checker (it is the test).**

`Scripts/check-bundle.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: check-bundle.sh <path/to/mtats.app> [--release] [--sparkle] [--signed]
set -euo pipefail
APP="$1"; shift
RELEASE=0; SPARKLE=0; SIGNED=0
for a in "$@"; do case "$a" in --release) RELEASE=1;; --sparkle) SPARKLE=1;; --signed) SIGNED=1;; *) echo "unknown flag $a" >&2; exit 2;; esac; done
HOST="$APP/Contents/MacOS/mtats"
fail() { echo "check-bundle: $*" >&2; exit 1; }

[[ -f "$APP/Contents/Frameworks/libMTatsPluginKit.dylib" ]] || fail "libMTatsPluginKit.dylib not in Contents/Frameworks"
ls "$APP/Contents/MacOS" | grep -q '\.dylib$' && fail "a dylib is still in Contents/MacOS"
otool -L "$HOST" | grep -q "@rpath/libMTatsPluginKit.dylib" || fail "Host does not reference @rpath/libMTatsPluginKit.dylib"
RPATHS=$(otool -l "$HOST" | awk '/LC_RPATH/{getline; getline; print $2}')
[[ "$RPATHS" == "@executable_path/../Frameworks" ]] || fail "Host rpaths must be exactly @executable_path/../Frameworks, got: $RPATHS"
nm "$HOST" | xcrun swift-demangle | grep -Eq '^[[:space:]]+U protocol descriptor for MTatsPluginKit.PluginEntry$' \
  || fail "PluginEntry descriptor is not an undefined reference (ADR-0005 static-embedding regression)"
for b in "$APP"/Contents/Resources/Plugins/*.bundle; do
  bin="$b/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$b/Contents/Info.plist")"
  if (( RELEASE )); then otool -l "$bin" | grep -A2 LC_RPATH | grep -q '/debug' && fail "$(basename "$b") ships a dev rpath"; fi
done
PB=/usr/libexec/PlistBuddy
[[ "$($PB -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$(Scripts/version.sh version)" ]] || fail "CFBundleShortVersionString mismatch"
[[ "$($PB -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$(Scripts/version.sh build)" ]] || fail "CFBundleVersion mismatch"
if (( RELEASE )); then
  [[ "$($PB -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")" == "https://mtats.app/appcast.xml" ]] || fail "release SUFeedURL"
else
  $PB -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" >/dev/null 2>&1 && fail "debug bundle must not contain SUFeedURL"
fi
if (( SPARKLE )); then
  [[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || fail "Sparkle.framework missing"
  otool -L "$HOST" | grep -q "@rpath/Sparkle.framework/Versions/B/Sparkle" || fail "Host does not link Sparkle"
fi
if (( SIGNED )); then
  codesign --verify --deep --strict "$APP" || fail "codesign --verify --deep --strict failed"
  ENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)
  [[ "$(grep -o '<key>[^<]*</key>' <<<"$ENT")" == "<key>com.apple.security.cs.disable-library-validation</key>" ]] \
    || fail "entitlements must be exactly disable-library-validation, got: $(grep -o '<key>[^<]*</key>' <<<"$ENT" | tr '\n' ' ')"
  codesign -d --verbose=4 "$APP" 2>&1 | grep -q 'flags=.*runtime' || fail "hardened runtime flag missing"
fi
echo "check-bundle: OK ($APP)"
```

`Scripts/tests/test-package-release.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Builds debug then release on the same checkout (Review Focus: the release relink must not
# pick up debug objects), then checks the release bundle.
set -euo pipefail
cd "$(dirname "$0")/../.."
Scripts/package-app.sh -c debug >/dev/null
Scripts/check-bundle.sh .build/mtats.app
Scripts/package-app.sh -c release >/dev/null
Scripts/check-bundle.sh .build/mtats.app --release
Scripts/smoke-test.sh
```

- [ ] **Step 2: Run to verify it fails against the current layout.**

Run: `chmod +x Scripts/check-bundle.sh Scripts/tests/test-package-release.sh && Scripts/package-app.sh >/dev/null && Scripts/check-bundle.sh .build/mtats.app`
Expected: `check-bundle: libMTatsPluginKit.dylib not in Contents/Frameworks`.

- [ ] **Step 3: Replace `Scripts/build-plugin.sh`.**

```bash
#!/usr/bin/env bash
# Scripts/build-plugin.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

# Usage: build-plugin.sh <WidgetName> <PrincipalClassName> [debug|release]
# Builds Plugins/<WidgetName>Widget/PluginMain.swift into .build/plugins/<WidgetName>Widget.bundle,
# linking against the Core library for <WidgetName> and the shared MTatsPluginKit.
# package-app.sh runs `swift build` for the configuration first.

NAME="$1"
PRINCIPAL_CLASS="$2"
CONFIG="${3:-debug}"
case "$CONFIG" in debug) OPT=(-Onone -g) ;; release) OPT=(-O) ;; *) echo "configuration must be debug or release" >&2; exit 2 ;; esac

OUT_DIR=".build/plugins/${NAME}Widget.bundle/Contents/MacOS"
rm -rf ".build/plugins/${NAME}Widget.bundle"
mkdir -p "$OUT_DIR"

RPATH=()
if [[ "$CONFIG" == debug ]]; then
  # Dev only: lets a bundle in .build/plugins find .build/debug when loaded standalone.
  # Inside mtats.app dyld matches the install name against the Host's copy first (ADR-0005).
  RPATH=(-Xlinker -rpath -Xlinker "@loader_path/../../../../debug")
fi

swiftc -emit-library -module-name "${NAME}Plugin" "${OPT[@]}" \
  -I ".build/$CONFIG" -L ".build/$CONFIG" -l"MTatsPluginKit" -l"${NAME}Core" \
  "Plugins/${NAME}Widget/PluginMain.swift" \
  -o "$OUT_DIR/${NAME}Widget" \
  "${RPATH[@]}"

cp "Plugins/${NAME}Widget/Info.plist" ".build/plugins/${NAME}Widget.bundle/Contents/Info.plist"
echo "Built .build/plugins/${NAME}Widget.bundle ($CONFIG, principal class: $PRINCIPAL_CLASS)"
```

(Signing moves to `sign-app.sh` in Task 5; until then `package-app.sh` signs ad-hoc at the end.)

- [ ] **Step 4: Replace `Scripts/package-app.sh`.** Use the Release object directory pattern recorded in Task 1; the pattern below (`*/Debug/...` vs `*/Release/...`) is what Task 1 Step 2 is expected to confirm — if Task 1 recorded a different path component, substitute it in `CONFIG_DIR`.

```bash
#!/usr/bin/env bash
# Scripts/package-app.sh
# SPDX-License-Identifier: MIT
# Usage: package-app.sh [-c debug|release]   (default debug; Scripts/dev.sh uses the default)
set -euo pipefail
CONFIG=debug
while getopts "c:" opt; do case "$opt" in c) CONFIG="$OPTARG" ;; *) exit 2 ;; esac; done
case "$CONFIG" in debug) CONFIG_DIR=Debug ;; release) CONFIG_DIR=Release ;; *) echo "configuration must be debug or release" >&2; exit 2 ;; esac

# The relink below reads the swiftbuild backend's intermediates layout; pin the backend.
swift build -c "$CONFIG" --build-system swiftbuild
for widget in CPU RAM GPU Network; do
  Scripts/build-plugin.sh "$widget" "${widget}PluginMain" "$CONFIG"
done

APP=".build/mtats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/Plugins"

# ADR-0005 Task 10 addendum: SwiftPM statically embeds same-package targets into an executable,
# so relink the Host's objects ourselves against the dynamic MTatsPluginKit. Only this
# configuration's objects: a debug and a release build can coexist on one checkout, and
# matching both would duplicate every symbol or ship debug code in a release.
OBJ_DIRS=$(find .build/out/Intermediates.noindex -type d -path "*/${CONFIG_DIR}/mtats-p.build/Objects-normal/arm64" 2>/dev/null || true)
if [[ -z "$OBJ_DIRS" || $(wc -l <<<"$OBJ_DIRS") -ne 1 ]]; then
  echo "package-app.sh: expected exactly one ${CONFIG_DIR} object directory for the mtats target, found:" >&2
  echo "${OBJ_DIRS:-<none>}" >&2
  echo "See ADR-0005's Task 10 addendum and spike (b)." >&2
  exit 1
fi
MTATS_OBJECTS=$(find "$OBJ_DIRS" -maxdepth 1 -name '*.o' ! -name '*-testable.o')
swiftc -o "$APP/Contents/MacOS/mtats" \
  $MTATS_OBJECTS \
  -L ".build/$CONFIG" -lMTatsPluginKit \
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks"

Scripts/render-info-plist.sh "$APP/Contents/Info.plist" "$CONFIG"

for widget in CPU RAM GPU Network; do
  cp -R ".build/plugins/${widget}Widget.bundle" "$APP/Contents/Resources/Plugins/"
done
cp ".build/$CONFIG/libMTatsPluginKit.dylib" "$APP/Contents/Frameworks/"

codesign -s - --identifier com.mtats.app --deep -f "$APP"
echo "Packaged $APP ($CONFIG)"
```

- [ ] **Step 5: Run the checker on a debug package.**

Run: `Scripts/package-app.sh && Scripts/check-bundle.sh .build/mtats.app && Scripts/smoke-test.sh`
Expected: `check-bundle: OK`, then `PASS`.

- [ ] **Step 6: Run the dev loop once** to prove the default path is unchanged: `Scripts/dev.sh`. Expected: `[dev] relaunched in …`.
- [ ] **Step 7: Run the mixed-configuration test (Review Focus).**

Run: `Scripts/tests/test-package-release.sh`
Expected: two `check-bundle: OK` lines and `PASS`. Then record the release RSS: update the comment above `if (( RSS_MB > 80 ))` in `Scripts/smoke-test.sh` to state the measured release figure and date.

- [ ] **Step 8: Commit.** `git add Scripts && git commit -m "Release configuration and Contents/Frameworks layout"`

---

### Task 5: Inside-out signing with the hardened runtime

**Files:**
- Create: `Scripts/sign-app.sh`, `Scripts/mtats.entitlements`, `Scripts/tests/test-sign-adhoc.sh`
- Modify: `Scripts/package-app.sh` (replace the final `codesign -s - ... --deep` line)

**Interfaces:**
- Consumes: `.build/mtats.app` from `package-app.sh`; `check-bundle.sh --signed`.
- Produces: `Scripts/sign-app.sh <app> [identity]` (identity omitted → ad-hoc `-`).

- [ ] **Step 1: Failing test.** `Scripts/tests/test-sign-adhoc.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
Scripts/package-app.sh -c release >/dev/null
Scripts/check-bundle.sh .build/mtats.app --release --signed
Scripts/smoke-test.sh
```

Run: `chmod +x Scripts/tests/test-sign-adhoc.sh && Scripts/tests/test-sign-adhoc.sh`
Expected: FAIL with `entitlements must be exactly disable-library-validation` (current `--deep` ad-hoc signing has no entitlements or runtime flag).

- [ ] **Step 2: Entitlements.** `Scripts/mtats.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
```

- [ ] **Step 3: `Scripts/sign-app.sh`.**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: sign-app.sh <path/to/mtats.app> [identity]
# Inside-out signing (spec §Bundle layout & signing). No identity → ad-hoc ("-").
set -euo pipefail
APP="$1"; IDENTITY="${2:--}"
ENTITLEMENTS="$(cd "$(dirname "$0")" && pwd)/mtats.entitlements"
FLAGS=(--force --options runtime --sign "$IDENTITY")
[[ "$IDENTITY" != "-" ]] && FLAGS+=(--timestamp)
sign() { codesign "${FLAGS[@]}" "$@"; }

# 1. Shared plugin framework
sign --identifier com.mtats.MTatsPluginKit "$APP/Contents/Frameworks/libMTatsPluginKit.dylib"

# 2. Sparkle, deepest first (enumerated, not hardcoded; spec §Bundle layout)
SP="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SP" ]]; then
  if [[ -d "$SP/Versions/B/XPCServices" ]]; then
    for x in "$SP"/Versions/B/XPCServices/*.xpc; do
      if [[ "$x" == *Downloader.xpc ]]; then sign --preserve-metadata=entitlements "$x"; else sign "$x"; fi
    done
  fi
  [[ -e "$SP/Versions/B/Autoupdate" ]] && sign "$SP/Versions/B/Autoupdate"
  [[ -d "$SP/Versions/B/Updater.app" ]] && sign "$SP/Versions/B/Updater.app"
  sign "$SP"
fi

# 3. Built-in plugins, identifier from each bundle's own plist
for b in "$APP"/Contents/Resources/Plugins/*.bundle; do
  sign --identifier "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$b/Contents/Info.plist")" "$b"
done

# 4. The app
sign --identifier com.mtats.app --entitlements "$ENTITLEMENTS" "$APP"

codesign --verify --deep --strict "$APP"
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q get-task-allow; then
  echo "sign-app.sh: get-task-allow is present; notarization would reject this build" >&2; exit 1
fi
echo "Signed $APP (${IDENTITY/#-/ad-hoc})"
```

- [ ] **Step 4: Use it from `package-app.sh`.** Replace the line `codesign -s - --identifier com.mtats.app --deep -f "$APP"` with `Scripts/sign-app.sh "$APP"`.
- [ ] **Step 5: Run.**

Run: `chmod +x Scripts/sign-app.sh && Scripts/tests/test-sign-adhoc.sh && Scripts/dev.sh`
Expected: `check-bundle: OK`, `PASS`, `[dev] relaunched`.

- [ ] **Step 6: Commit.** `git add Scripts && git commit -m "Inside-out signing with hardened runtime and entitlements"`

---

### Task 6: Headless smoke mode (only if Task 2 set `MTATS_CI_SMOKE_TEST` to `--headless`)

Skip this task entirely if Task 2 found the GUI smoke test passes on the hosted runner; ledger "Task 6 skipped: spike (a) passed".

**Files:** Modify: `Sources/mtats/main.swift`, `Scripts/smoke-test.sh`.

**Interfaces:** Produces: `mtats --smoke-test-exit-after=N --smoke-test-headless` (loads plugins, prints IDs/diagnostics, never creates status items); `Scripts/smoke-test.sh [--headless]`.

- [ ] **Step 1: Failing run.** `Scripts/smoke-test.sh --headless` → Expected: fails (unknown flag or no `--smoke-test-headless` handling).
- [ ] **Step 2: `main.swift`.** After `let isSmokeTest = …` add:

```swift
/// CI runners may have no WindowServer session for status items (spike (a)). Headless smoke mode
/// still proves the regression that matters — plugins load through the shared dylib — and skips
/// everything that needs a menu bar.
let isHeadlessSmokeTest = isSmokeTest && CommandLine.arguments.contains("--smoke-test-headless")
```

Replace the three statements `let statusBar = StatusBarController(settings: settings, loader: loader)`, `statusBar.present(widgets: widgets)` and `let watcher = loader.watchForNewPlugins(…) { … }` with:

```swift
var statusBar: StatusBarController?
var watcher: PluginDirectoryWatcher?
if !isHeadlessSmokeTest {
    statusBar = StatusBarController(settings: settings, loader: loader)
    statusBar?.present(widgets: widgets)
    // Held at top level so the FSEventStream isn't deallocated (spec §4.2 hot-load).
    watcher = loader.watchForNewPlugins(in: userDirectory, warnBeforeFirstThirdPartyLoad: warnBeforeFirstThirdPartyLoad) { newWidgets in
        statusBar?.present(widgets: newWidgets)
    }
}
```
and in the `--smoke-test-exit-after` block replace `DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }` with:

```swift
    if isHeadlessSmokeTest { exit(0) }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
```

- [ ] **Step 3: `smoke-test.sh`.** Accept `--headless`: when present, pass `--smoke-test-headless` to the binary, skip the CPU/RSS sampling (`ps` against an exited process) and still assert the four widget IDs and no diagnostics. Exact change: add `HEADLESS=0; [[ "${1:-}" == --headless ]] && HEADLESS=1`; launch with `"$APP/Contents/MacOS/mtats" --smoke-test-exit-after=8 $([[ $HEADLESS == 1 ]] && echo --smoke-test-headless) >"$LOG" 2>&1 &`; wrap the `kill -0`/`ps` block and both budget checks in `if (( ! HEADLESS )); then … fi`, and in headless mode `wait "$PID"` before reading the log.
- [ ] **Step 4: Run both modes.** `Scripts/package-app.sh && Scripts/smoke-test.sh && Scripts/smoke-test.sh --headless` → Expected: `PASS` twice.
- [ ] **Step 5: Commit.** `git commit -am "Headless smoke mode for CI runners"`

---

### Task 7: `ci.yml`

**Files:** Create: `.github/workflows/ci.yml`.

**Interfaces:** Consumes repository variables `MTATS_MACOS_RUNNER`, `MTATS_XCODE_PATH`, `MTATS_CI_SMOKE_TEST` (Task 2).

- [ ] **Step 1: Workflow.**

```yaml
# SPDX-License-Identifier: MIT
name: ci
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
jobs:
  build-test:
    runs-on: ${{ vars.MTATS_MACOS_RUNNER }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - run: sudo xcode-select -s "${{ vars.MTATS_XCODE_PATH }}"
      - run: swift build --build-system swiftbuild
      - run: swift test --build-system swiftbuild
      - run: Scripts/tests/run.sh
      - run: Scripts/package-app.sh -c release && Scripts/check-bundle.sh .build/mtats.app --release --signed
      - run: ${{ vars.MTATS_CI_SMOKE_TEST }}
```

- [ ] **Step 2: Lint locally.** `brew install actionlint 2>/dev/null; actionlint .github/workflows/ci.yml` → Expected: no output.
- [ ] **Step 3: Push the branch and open a draft PR (owner go-ahead).** `git push -u origin release-pipeline && gh pr create --draft --title "Release pipeline" --body "Implements docs/superpowers/specs/2026-10-11-release-pipeline-design.md. Draft until v0.1.0."` (body ends with the session's PR attribution line). Expected: `ci` runs and passes.
- [ ] **Step 4: Pin actions to SHAs.** For each `uses: owner/repo@vN` in every workflow file in `.github/workflows/`, resolve and substitute:

```bash
for ref in $(grep -ho 'uses: [^ ]*@v[0-9][^ ]*' .github/workflows/*.yml | awk '{print $2}' | sort -u); do
  repo=${ref%@*}; tag=${ref#*@}
  sha=$(gh api "repos/$repo/commits/$tag" --jq .sha)
  sed -i '' "s#uses: $repo@$tag\$#uses: $repo@$sha \# $tag#" .github/workflows/*.yml
done
grep -h 'uses:' .github/workflows/*.yml
```
Expected: every `uses:` line is `owner/repo@<40 hex> # vN`. Re-run this step at the end of Tasks 15, 17 and 19 for the workflows they add.

- [ ] **Step 5: Commit and push.** `git commit -am "CI workflow" && git push` → Expected: `ci` green on the draft PR.

---

### Task 8: Developer ID certificate and notary key (owner task)

**Files:** none in the repo.

**Interfaces:** Produces: a `Developer ID Application` identity in the owner's login keychain; a notarytool keychain profile named `mtats-notary`; the values for GitHub secrets (spec §CI secrets table), entered by the owner.

- [ ] **Step 1:** Give the owner the steps from spec §Open items rows "Create and export the Developer ID Application certificate" and "Create the App Store Connect API key for notarization". Stop until the owner reports done.
- [ ] **Step 2: Verify identity.** `security find-identity -v -p codesigning` → Expected: exactly one line containing `Developer ID Application:`. Record the full identity string (it is not secret) for Task 9.
- [ ] **Step 3: Local notary profile (owner runs; it prompts for nothing secret on screen):** `xcrun notarytool store-credentials mtats-notary --key <path to .p8> --key-id <Key ID> --issuer <Issuer ID>` → Expected: `Credentials saved to Keychain.` Owner then deletes the local `.p8` copy (it is in the password manager).
- [ ] **Step 4: GitHub environment and secrets (owner).** Create environment `release` (deployment branches and tags: tags matching `v*`; required reviewer: owner). Add secrets `APPLE_DEVELOPER_ID_P12_BASE64`, `APPLE_DEVELOPER_ID_P12_PASSWORD`, `APPLE_NOTARY_KEY_P8` and variables `APPLE_TEAM_ID`, `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID` to that environment. Verify: `gh api repos/marvinmarnold/mtats/environments/release/secrets --jq '.secrets[].name'` lists the three secrets.
- [ ] **Step 5: Tag ruleset (owner go-ahead).** `gh api -X POST repos/marvinmarnold/mtats/rulesets --input - <<'EOF'` with body `{"name":"release-tags","target":"tag","enforcement":"active","conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}},"rules":[{"type":"creation"},{"type":"deletion"},{"type":"update"}],"bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]}` then `EOF` (actor 5 = repository admin role, i.e. the owner). Expected: JSON with `"enforcement": "active"`.

---

### Task 9: Notarization and DMG

**Files:** Create: `Scripts/notarize.sh`, `Scripts/make-dmg.sh`, `Scripts/tests/test-make-dmg.sh`.

**Interfaces:**
- Consumes: `Scripts/sign-app.sh <app> <identity>`; notary profile `mtats-notary` (local) or `APPLE_NOTARY_KEY_FILE`/`APPLE_NOTARY_KEY_ID`/`APPLE_NOTARY_ISSUER_ID` (CI).
- Produces: `Scripts/notarize.sh <path.app|path.dmg>` (submits, waits, staples, validates; non-zero on rejection after printing the log); `Scripts/make-dmg.sh <app> <out.dmg>`.

- [ ] **Step 1: Failing test for the DMG layout.** `Scripts/tests/test-make-dmg.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'hdiutil detach -quiet "$T/mnt" 2>/dev/null || true; rm -rf "$T"' EXIT
[[ -d .build/mtats.app ]] || Scripts/package-app.sh >/dev/null
Scripts/make-dmg.sh .build/mtats.app "$T/x.dmg"
hdiutil attach -quiet -nobrowse -mountpoint "$T/mnt" "$T/x.dmg"
[[ -d "$T/mnt/mtats.app" ]] || { echo "  app missing from DMG" >&2; exit 1; }
[[ "$(readlink "$T/mnt/Applications")" == "/Applications" ]] || { echo "  Applications symlink missing" >&2; exit 1; }
```
Run: `chmod +x Scripts/tests/test-make-dmg.sh && bash Scripts/tests/test-make-dmg.sh` → Expected: fails (`make-dmg.sh` missing).

- [ ] **Step 2: `Scripts/make-dmg.sh`.**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: make-dmg.sh <path/to/mtats.app> <out.dmg>
set -euo pipefail
APP="$1"; OUT="$2"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/mtats.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -quiet -volname "mtats $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT"
echo "Created $OUT"
```
Run: `chmod +x Scripts/make-dmg.sh && bash Scripts/tests/test-make-dmg.sh` → Expected: exits 0.

- [ ] **Step 3: `Scripts/notarize.sh`.**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: notarize.sh <path.app|path.dmg>
# Auth: NOTARY_KEYCHAIN_PROFILE (local, e.g. mtats-notary) or
#       APPLE_NOTARY_KEY_FILE + APPLE_NOTARY_KEY_ID + APPLE_NOTARY_ISSUER_ID (CI).
set -euo pipefail
TARGET="$1"
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then AUTH=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
else AUTH=(--key "$APPLE_NOTARY_KEY_FILE" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID"); fi
SUBMIT="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  SUBMIT="$(mktemp -d)/$(basename "${TARGET%.app}").zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
fi
RESULT=$(xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait --timeout 30m --output-format json)
echo "$RESULT"
STATUS=$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$RESULT")
ID=$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$RESULT")
if [[ "$STATUS" != "Accepted" ]]; then
  xcrun notarytool log "$ID" "${AUTH[@]}" >&2
  echo "notarize.sh: $TARGET was $STATUS" >&2; exit 1
fi
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
```

- [ ] **Step 4: Local end-to-end (uses the owner's identity and Apple's service).**

```bash
IDENTITY="<identity string recorded in Task 8 Step 2>"
Scripts/package-app.sh -c release
Scripts/sign-app.sh .build/mtats.app "$IDENTITY"
Scripts/check-bundle.sh .build/mtats.app --release --signed
NOTARY_KEYCHAIN_PROFILE=mtats-notary Scripts/notarize.sh .build/mtats.app
spctl -a -vv .build/mtats.app
Scripts/make-dmg.sh .build/mtats.app .build/mtats-test.dmg
codesign --force --timestamp --sign "$IDENTITY" .build/mtats-test.dmg
NOTARY_KEYCHAIN_PROFILE=mtats-notary Scripts/notarize.sh .build/mtats-test.dmg
spctl -a -vv -t open --context context:primary-signature .build/mtats-test.dmg
```
Expected: both `notarytool` results `"status":"Accepted"`; `spctl` on the app prints `accepted` and `source=Notarized Developer ID`; on the DMG prints `accepted`.

- [ ] **Step 5: Commit.** `git add Scripts && git commit -m "Notarization and DMG scripts"`

---

### Task 10: Spike (c) — third-party plugin under the notarized Host

**Files:** Modify: spec Spikes section (outcome paragraph). No code.

- [ ] **Step 1: Unquarantined.** With the notarized `.build/mtats.app` from Task 9 Step 4, ensure `~/Library/Application Support/mtats/Plugins/HelloWidget.bundle` exists (rebuild from `~/code/mtats-example-plugin` against `.build/release` if needed, ad-hoc signed). `defaults delete com.mtats.app 2>/dev/null; open .build/mtats.app`. Ask the owner to click **Load** in the prompt. Expected: the 👋 item appears; Settings → Diagnostics shows no skip for `HelloWidget.bundle`.
- [ ] **Step 2: Quarantined.** Quit mtats; `xattr -w com.apple.quarantine "0083;$(printf %x $(date +%s));Safari;" ~/Library/Application\ Support/mtats/Plugins/HelloWidget.bundle`; `defaults delete com.mtats.app`; relaunch; owner clicks **Load**. Record whether it loads; if not, record the Diagnostics message.
- [ ] **Step 3: Restore.** `xattr -d com.apple.quarantine ~/Library/Application\ Support/mtats/Plugins/HelloWidget.bundle; defaults delete com.mtats.app`.
- [ ] **Step 4: Record.** Append "Spike (c) outcome (date)" to the spec with both results and, if the quarantined case fails, the exact sentence to put in `mtats-example-plugin/README.md` for plugin authors (spec §Spikes (c) fallback). If the *unquarantined* case fails, stop: this is a signing bug that blocks release (spec says it must not ship) — investigate `sign-app.sh` order/flags before any further task. Commit.

---

### Task 11: Sparkle framework and tools

**Files:**
- Modify: `Package.swift`, `Scripts/package-app.sh`, `.gitignore`
- Create: `Scripts/fetch-sparkle-tools.sh`, `Scripts/tests/test-package-sparkle.sh`

**Interfaces:**
- Consumes: Sparkle version + SPM-zip checksum recorded by Task 1.
- Produces: `Sparkle` SwiftPM binary target (module `Sparkle` importable from target `mtats`); `.build/mtats.app/Contents/Frameworks/Sparkle.framework`; `Scripts/fetch-sparkle-tools.sh` → `.build/sparkle-tools/bin/{generate_keys,sign_update,generate_appcast}`.

- [ ] **Step 1: Failing test.** `Scripts/tests/test-package-sparkle.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
Scripts/package-app.sh -c release >/dev/null
Scripts/check-bundle.sh .build/mtats.app --release --signed --sparkle
[[ -d .build/mtats.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices ]] && [[ "${SPARKLE_KEEP_XPC:-0}" != 1 ]] \
  && { echo "  XPCServices should be stripped (spike (b) decision)" >&2; exit 1; }
Scripts/fetch-sparkle-tools.sh >/dev/null
for t in generate_keys sign_update generate_appcast; do [[ -x ".build/sparkle-tools/bin/$t" ]] || { echo "  missing $t" >&2; exit 1; }; done
Scripts/smoke-test.sh
```
Run: `chmod +x Scripts/tests/test-package-sparkle.sh && bash Scripts/tests/test-package-sparkle.sh` → Expected: FAIL `Sparkle.framework missing`.

(If Task 1 recorded that XPC services must be kept, set `SPARKLE_KEEP_XPC=1` at the top of this test and skip the `rm -rf` in Step 3.)

- [ ] **Step 2: `Package.swift`.** Add to `targets`:

```swift
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/<version recorded in Task 1>/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "<checksum recorded in Task 1>"
        ),
```
and change the `mtats` executable target's dependencies to `["MTatsPluginKit", "Sparkle"]`. Both values are copied verbatim from the Task 1 outcome paragraph in the spec.

- [ ] **Step 3: `package-app.sh` additions.** After the `swift build` line add:

```bash
SPARKLE_FW=$(find .build/artifacts -type d -path '*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' | head -1)
[[ -n "$SPARKLE_FW" ]] || { echo "package-app.sh: Sparkle.framework not found under .build/artifacts" >&2; exit 1; }
```
In the `swiftc -o "$APP/Contents/MacOS/mtats"` command add `-F "$(dirname "$SPARKLE_FW")" -framework Sparkle` before `-Xlinker -rpath`. After copying `libMTatsPluginKit.dylib` add:

```bash
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
# mtats is not sandboxed; Sparkle's XPC services exist only for sandboxed hosts (spike (b)).
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
```

- [ ] **Step 4: `Scripts/fetch-sparkle-tools.sh`.** Download `Sparkle-<version>.tar.xz` once manually, compute `shasum -a 256`, then write:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Fetches Sparkle's CLI tools at the version pinned in Package.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
SPARKLE_VERSION="<version recorded in Task 1>"
SPARKLE_TOOLS_SHA256="<sha256 of Sparkle-$SPARKLE_VERSION.tar.xz, computed in this step>"
DEST=.build/sparkle-tools
[[ -x "$DEST/bin/generate_appcast" ]] && exit 0
mkdir -p "$DEST"
curl -fsSL -o "$DEST/sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
echo "$SPARKLE_TOOLS_SHA256  $DEST/sparkle.tar.xz" | shasum -a 256 -c -
tar -xJf "$DEST/sparkle.tar.xz" -C "$DEST" bin
rm "$DEST/sparkle.tar.xz"
```
(`.build/` is already gitignored.)

- [ ] **Step 5: Run.** `chmod +x Scripts/fetch-sparkle-tools.sh && bash Scripts/tests/test-package-sparkle.sh && swift test --build-system swiftbuild && Scripts/dev.sh` → Expected: `check-bundle: OK`, `PASS`, tests pass, `[dev] relaunched`.
- [ ] **Step 6: Commit.** `git add Package.swift Scripts && git commit -m "Embed Sparkle framework and fetch Sparkle tools"`

---

### Task 12: Sparkle integration in the Host

**Files:**
- Create: `Sources/mtats/Updates.swift`, `Tests/mtatsTests/UpdateChannelTests.swift`
- Modify: `Sources/mtats/main.swift`, `Sources/mtats/StatusBarController.swift` (init + `makeSettingsView()`), `Sources/mtats/SettingsView.swift`

**Interfaces:**
- Consumes: `Sparkle` module (Task 11); `isSmokeTest` in `main.swift`.
- Produces: `UpdateChannel.feedURLOverride(defaults:) -> String?`, `UpdateChannel.isEnabled(infoDictionary:isSmokeTest:) -> Bool`, `UpdateChannel.betaFeedURL`; `final class UpdateControls: ObservableObject` with `canCheckForUpdates: Bool`, `checkForUpdates()`, `automaticallyChecks: Bool`; `StatusBarController.init(settings:loader:updateControls:)` (`updateControls` defaults to `nil`); `SettingsView.init(settings:widgets:loader:updateControls:onToggle:)`.

- [ ] **Step 1: Failing tests.** `Tests/mtatsTests/UpdateChannelTests.swift`:

```swift
// SPDX-License-Identifier: MIT
import XCTest
@testable import mtats

final class UpdateChannelTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "mtats.tests.\(UUID())")! }

    func test_noChannelSet_usesInfoPlistFeed() {
        XCTAssertNil(UpdateChannel.feedURLOverride(defaults: defaults()))
    }

    func test_betaChannel_overridesToBetaFeed() {
        let d = defaults(); d.set("beta", forKey: "updateChannel")
        XCTAssertEqual(UpdateChannel.feedURLOverride(defaults: d), "https://mtats.app/beta/appcast.xml")
    }

    func test_unknownChannel_isIgnored() {
        let d = defaults(); d.set("nightly", forKey: "updateChannel")
        XCTAssertNil(UpdateChannel.feedURLOverride(defaults: d))
    }

    // Review Focus: a debug package has no SUFeedURL and must never start the updater.
    func test_updaterDisabled_withoutFeedURL() {
        XCTAssertFalse(UpdateChannel.isEnabled(infoDictionary: ["CFBundleVersion": "1"], isSmokeTest: false))
        XCTAssertFalse(UpdateChannel.isEnabled(infoDictionary: nil, isSmokeTest: false))
    }

    func test_updaterDisabled_inSmokeTest() {
        XCTAssertFalse(UpdateChannel.isEnabled(infoDictionary: ["SUFeedURL": "https://mtats.app/appcast.xml"], isSmokeTest: true))
    }

    func test_updaterEnabled_forReleaseBuild() {
        XCTAssertTrue(UpdateChannel.isEnabled(infoDictionary: ["SUFeedURL": "https://mtats.app/appcast.xml"], isSmokeTest: false))
    }
}
```
Run: `swift test --build-system swiftbuild --filter UpdateChannelTests` → Expected: FAIL `cannot find 'UpdateChannel' in scope`.

- [ ] **Step 2: `Sources/mtats/Updates.swift`.**

```swift
// SPDX-License-Identifier: MIT
import AppKit
import Combine
import Sparkle

public enum UpdateChannel {
    public static let betaFeedURL = "https://mtats.app/beta/appcast.xml"

    /// nil means "use SUFeedURL from Info.plist" (stable). `defaults write com.mtats.app
    /// updateChannel beta` switches a test install to the beta feed (spec §Auto-update).
    public static func feedURLOverride(defaults: UserDefaults) -> String? {
        defaults.string(forKey: "updateChannel") == "beta" ? betaFeedURL : nil
    }

    /// Debug packages carry no SUFeedURL; the smoke test must make no network requests.
    public static func isEnabled(infoDictionary: [String: Any]?, isSmokeTest: Bool) -> Bool {
        guard !isSmokeTest, let feed = infoDictionary?["SUFeedURL"] as? String else { return false }
        return !feed.isEmpty
    }
}

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let defaults: UserDefaults
    init(defaults: UserDefaults) { self.defaults = defaults }
    func feedURLString(for updater: SPUUpdater) -> String? { UpdateChannel.feedURLOverride(defaults: defaults) }
}

/// LSUIElement apps aren't frontmost; without activating, Sparkle's window opens behind others.
final class UserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate()
    }
}

public final class UpdateControls: ObservableObject {
    @Published public private(set) var canCheckForUpdates = false
    private let updater: SPUUpdater
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        self.updater = updater
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    public func checkForUpdates() {
        NSApp.activate()
        updater.checkForUpdates()
    }

    public var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { objectWillChange.send(); updater.automaticallyChecksForUpdates = newValue }
    }
}
```
Run: `swift test --build-system swiftbuild --filter UpdateChannelTests` → Expected: PASS (6 tests). If `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)` does not match the pinned Sparkle's `SPUStandardUserDriverDelegate`, use the method that version's header declares for "about to show an update" and record the substitution in the ledger.

- [ ] **Step 3: `main.swift`.** Add `import Sparkle` at the top. Replace `let statusBar = StatusBarController(settings: settings, loader: loader)` with:

```swift
// Held at top level for the process lifetime, like `watcher`.
let updaterDelegate = UpdaterDelegate(defaults: .standard)
let userDriverDelegate = UserDriverDelegate()
let updaterController: SPUStandardUpdaterController? =
    UpdateChannel.isEnabled(infoDictionary: Bundle.main.infoDictionary, isSmokeTest: isSmokeTest)
    ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: userDriverDelegate)
    : nil
let updateControls = updaterController.map { UpdateControls(updater: $0.updater) }
let statusBar = StatusBarController(settings: settings, loader: loader, updateControls: updateControls)
```
(If Task 6 made `statusBar` optional, apply the same change inside its `if !isHeadlessSmokeTest` block.)

- [ ] **Step 4: `StatusBarController`.** Add a stored property `private let updateControls: UpdateControls?`; change the initializer to `public init(settings: SettingsStore, loader: PluginLoader, updateControls: UpdateControls? = nil)` assigning it; in `makeSettingsView()` pass `updateControls: updateControls`.
- [ ] **Step 5: `SettingsView`.** Add `let updateControls: UpdateControls?` and the init parameter `updateControls: UpdateControls? = nil` (between `loader` and `onToggle`). In `settingsForm`, immediately before the `Button("Quit mtats")`, add:

```swift
            if let updateControls {
                UpdatesSection(controls: updateControls)
            }
```
and add at file scope:

```swift
private struct UpdatesSection: View {
    @ObservedObject var controls: UpdateControls
    var body: some View {
        Button("Check for Updates…") { controls.checkForUpdates() }
            .disabled(!controls.canCheckForUpdates)
        Toggle("Automatically check for updates", isOn: Binding(
            get: { controls.automaticallyChecks },
            set: { controls.automaticallyChecks = $0 }
        ))
        let info = Bundle.main.infoDictionary
        Text("Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))")
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 6: Verify.** `swift test --build-system swiftbuild && Scripts/tests/run.sh && Scripts/dev.sh` → Expected: all pass; dev app relaunches. Ask the owner to open Settings in the dev app and confirm there is **no** updates section (debug build).
- [ ] **Step 7: Commit.** `git add Sources Tests && git commit -m "Sparkle updater in the Host with beta channel override"`

---

### Task 13: Sparkle signing keys and plist keys (owner runs key generation)

**Files:** Modify: `Scripts/Host-Info.plist.template`.

**Interfaces:** Produces: `SUPublicEDKey` in the template; secret `SPARKLE_ED25519_PRIVATE_KEY` in environment `release`.

- [ ] **Step 1: Owner generates the key pair.** `Scripts/fetch-sparkle-tools.sh && .build/sparkle-tools/bin/generate_keys` → prints a base64 public key (stores private key in the owner's login keychain). Then `.build/sparkle-tools/bin/generate_keys -x /tmp/sparkle-private.txt`, owner copies it into the password manager and the `release` environment secret `SPARKLE_ED25519_PRIVATE_KEY`, then `rm -P /tmp/sparkle-private.txt`.
- [ ] **Step 2: Template.** Add before `</dict></plist>` in `Scripts/Host-Info.plist.template`: `  <key>SUPublicEDKey</key><string>` + the public key printed in Step 1 + `</string>`.
- [ ] **Step 3: Test.** Add to `Scripts/tests/test-render-info-plist.sh` before `exit 0`:

```bash
KEY=$($PB -c 'Print :SUPublicEDKey' "$T/r.plist") || fail "SUPublicEDKey missing"
[[ $(printf %s "$KEY" | base64 -d 2>/dev/null | wc -c) -eq 32 ]] || fail "SUPublicEDKey is not a 32-byte Ed25519 key"
```
Run: `Scripts/tests/run.sh` → Expected: all PASS.

- [ ] **Step 4: Commit.** `git commit -am "Add Sparkle public EdDSA key"`

---

### Task 14: Release tooling — guard, notes, preflight, first release notes

**Files:**
- Create: `Scripts/appcast-guard.sh`, `Scripts/notes-to-html.py`, `Scripts/release-preflight.sh`, `Releases/0.1.0.md`, `Scripts/tests/test-appcast-guard.sh`, `Scripts/tests/test-notes-to-html.sh`, `Scripts/tests/test-release-preflight.sh`, `Scripts/tests/fixtures/appcast-two-items.xml`

**Interfaces:**
- Produces: `Scripts/appcast-guard.sh <stable|beta> <build>` (fetches `https://storage.googleapis.com/mtats-releases/[beta/]appcast.xml`; `APPCAST_FILE=<path>` overrides the fetch; exits 1 if `build` ≤ max `sparkle:version`; a 404 counts as empty); `Scripts/notes-to-html.py <in.md> <out.html>`; `Scripts/release-preflight.sh <version>` (`PREFLIGHT_SKIP_BUILD=1` and `PREFLIGHT_FEED_URL=<url>` exist for its own tests only).

- [ ] **Step 1: Failing tests.**

`Scripts/tests/fixtures/appcast-two-items.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>mtats</title>
<item><title>0.1.0</title><sparkle:version>120</sparkle:version><sparkle:shortVersionString>0.1.0</sparkle:shortVersionString></item>
<item><title>0.1.1</title><sparkle:version>137</sparkle:version><sparkle:shortVersionString>0.1.1</sparkle:shortVersionString></item>
</channel></rss>
```

`Scripts/tests/test-appcast-guard.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
F=Scripts/tests/fixtures/appcast-two-items.xml
fail() { echo "  $*" >&2; exit 1; }
APPCAST_FILE=$F Scripts/appcast-guard.sh stable 138 >/dev/null || fail "138 > 137 should pass"
APPCAST_FILE=$F Scripts/appcast-guard.sh stable 137 2>/dev/null && fail "equal build (re-tag of same commit) must fail"
APPCAST_FILE=$F Scripts/appcast-guard.sh stable 5 2>/dev/null && fail "lower build must fail"
E=$(mktemp); printf '<?xml version="1.0"?><rss version="2.0"><channel><title>mtats</title></channel></rss>' >"$E"
APPCAST_FILE=$E Scripts/appcast-guard.sh beta 1 >/dev/null || fail "empty feed should pass"
rm -f "$E"
Scripts/appcast-guard.sh nightly 1 2>/dev/null && fail "unknown channel must fail"
exit 0
```

`Scripts/tests/test-notes-to-html.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '# mtats 0.1.0\n\nFirst release.\n\n- CPU <and> RAM\n- GPU & Network\n' >"$T/n.md"
/usr/bin/python3 Scripts/notes-to-html.py "$T/n.md" "$T/n.html"
grep -q '<h2>mtats 0.1.0</h2>' "$T/n.html"
grep -q '<p>First release.</p>' "$T/n.html"
grep -q '<li>CPU &lt;and&gt; RAM</li>' "$T/n.html"
grep -q '<li>GPU &amp; Network</li>' "$T/n.html"
[[ $(grep -c '<ul>' "$T/n.html") -eq 1 ]]
```

`Scripts/tests/test-release-preflight.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
# Review Focus: refuse to tag while mtats.app does not serve a valid feed.
PREFLIGHT_SKIP_BUILD=1 PREFLIGHT_FEED_URL="https://mtats.invalid/appcast.xml" \
  Scripts/release-preflight.sh 0.1.0 >/dev/null 2>&1 && fail "unreachable feed must fail preflight"
PREFLIGHT_SKIP_BUILD=1 Scripts/release-preflight.sh 9.9.9 >/dev/null 2>&1 && fail "missing Releases/9.9.9.md must fail"
Scripts/release-preflight.sh not-a-version >/dev/null 2>&1 && fail "malformed version must fail"
exit 0
```
Run: `chmod +x Scripts/tests/*.sh && Scripts/tests/run.sh` → Expected: the three new tests FAIL (scripts missing).

- [ ] **Step 2: `Scripts/appcast-guard.sh`.**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: appcast-guard.sh <stable|beta> <build>
# Fails unless <build> is greater than every sparkle:version already in the channel's appcast
# (Sparkle orders by CFBundleVersion; spec §Versioning). APPCAST_FILE overrides the fetch.
set -euo pipefail
CHANNEL="$1"; BUILD="$2"
case "$CHANNEL" in stable) PREFIX="" ;; beta) PREFIX="beta/" ;; *) echo "channel must be stable or beta" >&2; exit 2 ;; esac
FEED="${APPCAST_FILE:-}"
if [[ -z "$FEED" ]]; then
  FEED=$(mktemp); trap 'rm -f "$FEED"' EXIT
  CODE=$(curl -s -o "$FEED" -w '%{http_code}' "https://storage.googleapis.com/mtats-releases/${PREFIX}appcast.xml")
  case "$CODE" in 200) ;; 404) : >"$FEED" ;; *) echo "appcast-guard: fetching appcast returned HTTP $CODE" >&2; exit 1 ;; esac
fi
MAX=$(/usr/bin/python3 - "$FEED" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
nums = [int(n) for n in re.findall(r"<sparkle:version>\s*(\d+)\s*</sparkle:version>", text)]
nums += [int(n) for n in re.findall(r'sparkle:version="(\d+)"', text)]
print(max(nums) if nums else 0)
PY
)
if (( BUILD <= MAX )); then
  echo "appcast-guard: build $BUILD is not greater than published build $MAX on $CHANNEL" >&2; exit 1
fi
echo "appcast-guard: build $BUILD > $MAX on $CHANNEL"
```

- [ ] **Step 3: `Scripts/notes-to-html.py`.**

```python
# SPDX-License-Identifier: MIT
"""Minimal Markdown → HTML for Sparkle release notes: '# ' headings, '- ' bullets, paragraphs."""
import html
import sys


def convert(markdown: str) -> str:
    out, para, in_list = [], [], False

    def flush_para():
        if para:
            out.append(f"<p>{html.escape(' '.join(para))}</p>")
            para.clear()

    for line in markdown.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            flush_para()
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{html.escape(stripped[2:])}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if stripped.startswith("#"):
            flush_para()
            out.append(f"<h2>{html.escape(stripped.lstrip('#').strip())}</h2>")
        elif stripped:
            para.append(stripped)
        else:
            flush_para()
    flush_para()
    if in_list:
        out.append("</ul>")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        result = convert(f.read())
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        f.write(result)
```

- [ ] **Step 4: `Scripts/release-preflight.sh`.**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: release-preflight.sh <version>   e.g. 0.1.0 or 0.1.0-rc.1
# Run locally before pushing a release tag (spec §Testing). Prints the tag command on success.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-}"
fail() { echo "preflight: $*" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || fail "version must look like 1.2.3 or 1.2.3-rc.1"
[[ -s "Releases/${VERSION}.md" ]] || fail "Releases/${VERSION}.md is missing or empty"
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && fail "tag v$VERSION already exists"
FEED_URL="${PREFLIGHT_FEED_URL:-https://mtats.app/appcast.xml}"
FEED=$(curl -fsS --max-time 15 "$FEED_URL") || fail "$FEED_URL is not reachable — finish Phase 5 before tagging"
grep -q '<rss' <<<"$FEED" || fail "$FEED_URL does not look like an appcast"
if [[ "${PREFLIGHT_SKIP_BUILD:-0}" != 1 ]]; then
  [[ "$(git branch --show-current)" == main ]] || fail "not on main"
  git fetch -q origin main
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not up to date with origin/main"
  [[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean"
  swift test --build-system swiftbuild >/dev/null || fail "swift test failed"
  Scripts/tests/run.sh >/dev/null || fail "shell tests failed"
  Scripts/package-app.sh -c release >/dev/null && Scripts/smoke-test.sh || fail "release package or smoke test failed"
fi
echo "preflight OK. Tag with:"
echo "  git tag -a v$VERSION -m \"mtats $VERSION\" && git push origin v$VERSION"
```

- [ ] **Step 5: `Releases/0.1.0.md`.**

```markdown
# mtats 0.1.0

The first public release of mtats: Mac stats you wear on your sleeve.

- CPU, memory, GPU and network readings in the menu bar, each with a detail dropdown
- Local and public IP in the network dropdown (public-IP lookup can be turned off)
- Updates install themselves; check manually from Settings
- Apple Silicon, macOS 14 or later
```

- [ ] **Step 6: Run.** `chmod +x Scripts/appcast-guard.sh Scripts/release-preflight.sh && Scripts/tests/run.sh` → Expected: all PASS.
- [ ] **Step 7: Commit.** `git add Scripts Releases && git commit -m "Release guard, notes conversion, and preflight"`

---

### Task 15: `release.yml`, job 1 (build, sign, notarize)

**Files:** Create: `.github/workflows/release.yml`.

**Interfaces:**
- Consumes: everything from Tasks 3–14; environment `release` secrets/variables (Task 8, 13); repository variables from Task 2.
- Produces: job artifact `release` containing `mtats-<version>.dmg`, `mtats-<version>.dmg.sha256`, `appcast.xml`, `latest.json`, `Releases/<version>.md`; env `MTATS_CHANNEL` semantics (`stable`|`beta`).

- [ ] **Step 1: Workflow (job 1 only; Task 19 adds job 2).**

```yaml
# SPDX-License-Identifier: MIT
name: release
on:
  push:
    tags: ['v*']
concurrency:
  group: release
  cancel-in-progress: false
permissions:
  contents: read
jobs:
  build-sign-notarize:
    runs-on: ${{ vars.MTATS_MACOS_RUNNER }}
    environment: release
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - run: sudo xcode-select -s "${{ vars.MTATS_XCODE_PATH }}"
      - name: Validate tag, derive version
        run: |
          TAG="$GITHUB_REF_NAME"
          [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || { echo "::error::bad tag $TAG"; exit 1; }
          VERSION="${TAG#v}"
          git fetch -q origin main
          git merge-base --is-ancestor "$GITHUB_SHA" origin/main || { echo "::error::tag is not on main"; exit 1; }
          test -s "Releases/${VERSION}.md" || { echo "::error::Releases/${VERSION}.md missing"; exit 1; }
          CHANNEL=stable; [[ "$VERSION" == *-rc.* ]] && CHANNEL=beta
          { echo "MTATS_VERSION=$VERSION"; echo "MTATS_BUILD=$(git rev-list --count HEAD)"; echo "MTATS_CHANNEL=$CHANNEL"; } >> "$GITHUB_ENV"
      - name: Gate — tests
        run: swift test --build-system swiftbuild && Scripts/tests/run.sh
      - name: Gate — release package and smoke test
        run: Scripts/package-app.sh -c release && ${{ vars.MTATS_CI_SMOKE_TEST }}
      - name: Update guard
        run: Scripts/appcast-guard.sh "$MTATS_CHANNEL" "$MTATS_BUILD"
      - name: Import Developer ID
        env:
          P12_BASE64: ${{ secrets.APPLE_DEVELOPER_ID_P12_BASE64 }}
          P12_PASSWORD: ${{ secrets.APPLE_DEVELOPER_ID_P12_PASSWORD }}
        run: |
          KC="$RUNNER_TEMP/signing.keychain-db"; KC_PW=$(uuidgen)
          echo "$P12_BASE64" | base64 -d > "$RUNNER_TEMP/devid.p12"
          security create-keychain -p "$KC_PW" "$KC"
          security set-keychain-settings -lut 3600 "$KC"
          security unlock-keychain -p "$KC_PW" "$KC"
          security import "$RUNNER_TEMP/devid.p12" -k "$KC" -P "$P12_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PW" "$KC" >/dev/null
          security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
          rm -f "$RUNNER_TEMP/devid.p12"
          IDS=$(security find-identity -v -p codesigning "$KC" | grep "Developer ID Application:.*(${{ vars.APPLE_TEAM_ID }})")
          [[ $(wc -l <<<"$IDS") -eq 1 ]] || { echo "::error::expected exactly one Developer ID identity"; exit 1; }
          echo "MTATS_IDENTITY=$(sed -E 's/^.*"(.*)"$/\1/' <<<"$IDS")" >> "$GITHUB_ENV"
      - name: Sign
        run: |
          Scripts/sign-app.sh .build/mtats.app "$MTATS_IDENTITY"
          Scripts/check-bundle.sh .build/mtats.app --release --signed --sparkle
      - name: Write notary key
        env:
          P8: ${{ secrets.APPLE_NOTARY_KEY_P8 }}
        run: |
          printf '%s' "$P8" > "$RUNNER_TEMP/notary.p8"
          echo "APPLE_NOTARY_KEY_FILE=$RUNNER_TEMP/notary.p8" >> "$GITHUB_ENV"
      - name: Notarize app
        env:
          APPLE_NOTARY_KEY_ID: ${{ vars.APPLE_NOTARY_KEY_ID }}
          APPLE_NOTARY_ISSUER_ID: ${{ vars.APPLE_NOTARY_ISSUER_ID }}
        run: Scripts/notarize.sh .build/mtats.app && spctl -a -vv .build/mtats.app
      - name: DMG
        env:
          APPLE_NOTARY_KEY_ID: ${{ vars.APPLE_NOTARY_KEY_ID }}
          APPLE_NOTARY_ISSUER_ID: ${{ vars.APPLE_NOTARY_ISSUER_ID }}
        run: |
          mkdir -p out
          DMG="out/mtats-${MTATS_VERSION}.dmg"
          Scripts/make-dmg.sh .build/mtats.app "$DMG"
          codesign --force --timestamp --sign "$MTATS_IDENTITY" "$DMG"
          Scripts/notarize.sh "$DMG"
          spctl -a -vv -t open --context context:primary-signature "$DMG"
          (cd out && shasum -a 256 "mtats-${MTATS_VERSION}.dmg" > "mtats-${MTATS_VERSION}.dmg.sha256")
      - name: Appcast and latest.json
        env:
          ED_KEY: ${{ secrets.SPARKLE_ED25519_PRIVATE_KEY }}
        run: |
          Scripts/fetch-sparkle-tools.sh
          PREFIX=""; [[ "$MTATS_CHANNEL" == beta ]] && PREFIX="beta/"
          W="$RUNNER_TEMP/appcast"; mkdir -p "$W"
          curl -fsS -o "$W/appcast.xml" "https://storage.googleapis.com/mtats-releases/${PREFIX}appcast.xml" || rm -f "$W/appcast.xml"
          cp "out/mtats-${MTATS_VERSION}.dmg" "$W/"
          /usr/bin/python3 Scripts/notes-to-html.py "Releases/${MTATS_VERSION}.md" "$W/mtats-${MTATS_VERSION}.html"
          printf '%s' "$ED_KEY" > "$RUNNER_TEMP/ed.key"
          .build/sparkle-tools/bin/generate_appcast --ed-key-file "$RUNNER_TEMP/ed.key" \
            --download-url-prefix "https://mtats.app/releases/" --link "https://mtats.app" "$W"
          cp "$W/appcast.xml" out/appcast.xml
          SIZE=$(stat -f %z "out/mtats-${MTATS_VERSION}.dmg")
          SHA=$(cut -d' ' -f1 "out/mtats-${MTATS_VERSION}.dmg.sha256")
          /usr/bin/python3 - <<PY > out/latest.json
          import json, datetime
          print(json.dumps({"version": "$MTATS_VERSION", "build": int("$MTATS_BUILD"), "channel": "$MTATS_CHANNEL",
            "url": "https://mtats.app/releases/mtats-$MTATS_VERSION.dmg", "sizeBytes": $SIZE, "sha256": "$SHA",
            "publishedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
            "minimumSystemVersion": "14.0"}, indent=2))
          PY
          cp "Releases/${MTATS_VERSION}.md" out/
      - uses: actions/upload-artifact@v4
        with:
          name: release
          path: out/
          if-no-files-found: error
      - name: Clean up secrets
        if: always()
        run: |
          rm -f "$RUNNER_TEMP/notary.p8" "$RUNNER_TEMP/ed.key" "$RUNNER_TEMP/devid.p12"
          security delete-keychain "$RUNNER_TEMP/signing.keychain-db" 2>/dev/null || true
```

- [ ] **Step 2: Lint and pin.** `actionlint .github/workflows/release.yml` → no output; then Task 7 Step 4's pinning loop.
- [ ] **Step 3: Commit and push.** `git add .github && git commit -m "Release workflow: build, sign, notarize" && git push`. (No tag yet: the end-to-end run happens in Task 20 after `main` contains this and the feed exists.)

---

### Task 16: GCP project bootstrap (owner go-ahead — creates billable resources)

**Files:** Create: `Scripts/gcp-bootstrap.sh`, `Scripts/release-env.sh`.

**Interfaces:**
- Produces: project `mtats-release`; bucket `gs://mtats-releases`; service account `github-release@mtats-release.iam.gserviceaccount.com`; WIF provider `projects/<number>/locations/global/workloadIdentityPools/github/providers/github-oidc`; budget `mtats-monthly`; Firebase enabled; repository variables `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`; `Scripts/release-env.sh` exporting `MTATS_GCP_PROJECT`, `MTATS_BUCKET`.

- [ ] **Step 1: `Scripts/release-env.sh`** (the single place names live; spec §Risks):

```bash
# SPDX-License-Identifier: MIT
# Sourced by GCP/publish scripts. The only place these names are defined.
export MTATS_GCP_PROJECT=mtats-release
export MTATS_BUCKET=mtats-releases
export MTATS_GITHUB_REPO=marvinmarnold/mtats
```

- [ ] **Step 2: `Scripts/gcp-bootstrap.sh`.**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# One-time setup of the mtats GCP project (spec §GCP resources). Idempotent where gcloud allows.
# Usage: BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX Scripts/gcp-bootstrap.sh
# Billing-isolation rule: every command passes --project explicitly; the default config is
# asserted unchanged at the end.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/release-env.sh
P="$MTATS_GCP_PROJECT"; B="$MTATS_BUCKET"; SA="github-release@${P}.iam.gserviceaccount.com"
: "${BILLING_ACCOUNT:?set BILLING_ACCOUNT (gcloud billing accounts list)}"
DEFAULT_BEFORE=$(gcloud config get-value project 2>/dev/null)
trap '[[ "$(gcloud config get-value project 2>/dev/null)" == "$DEFAULT_BEFORE" ]] || echo "WARNING: gcloud default project changed!" >&2' EXIT

gcloud projects describe "$P" >/dev/null 2>&1 || gcloud projects create "$P" --name="mtats release" --labels=app=mtats
gcloud billing projects link "$P" --billing-account="$BILLING_ACCOUNT"
gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com iam.googleapis.com \
  iamcredentials.googleapis.com sts.googleapis.com storage.googleapis.com firebase.googleapis.com \
  firebasehosting.googleapis.com billingbudgets.googleapis.com --project "$P"
NUMBER=$(gcloud projects describe "$P" --format='value(projectNumber)')

gcloud storage buckets describe "gs://$B" --project "$P" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$B" --project "$P" --location=us-central1 --default-storage-class=STANDARD \
    --uniform-bucket-level-access --no-public-access-prevention
gcloud storage buckets update "gs://$B" --project "$P" --versioning
LC=$(mktemp); echo '{"rule":[{"action":{"type":"Delete"},"condition":{"daysSinceNoncurrentTime":90}}]}' >"$LC"
gcloud storage buckets update "gs://$B" --project "$P" --lifecycle-file="$LC"; rm -f "$LC"
gcloud storage buckets add-iam-policy-binding "gs://$B" --project "$P" --member=allUsers --role=roles/storage.objectViewer

gcloud iam service-accounts describe "$SA" --project "$P" >/dev/null 2>&1 || \
  gcloud iam service-accounts create github-release --project "$P" --display-name="GitHub release publisher"
gcloud storage buckets add-iam-policy-binding "gs://$B" --project "$P" --member="serviceAccount:$SA" --role=roles/storage.objectAdmin
gcloud projects add-iam-policy-binding "$P" --member="serviceAccount:$SA" --role=roles/firebasehosting.admin --condition=None
gcloud projects add-iam-policy-binding "$P" --member="serviceAccount:$SA" --role=roles/serviceusage.serviceUsageConsumer --condition=None

gcloud iam workload-identity-pools describe github --project "$P" --location=global >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools create github --project "$P" --location=global --display-name="GitHub Actions"
gcloud iam workload-identity-pools providers describe github-oidc --project "$P" --location=global --workload-identity-pool=github >/dev/null 2>&1 || \
  gcloud iam workload-identity-pools providers create-oidc github-oidc --project "$P" --location=global \
    --workload-identity-pool=github --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="assertion.repository == '${MTATS_GITHUB_REPO}' && (assertion.ref.startsWith('refs/tags/v') || assertion.ref == 'refs/heads/main')"
gcloud iam service-accounts add-iam-policy-binding "$SA" --project "$P" --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/${NUMBER}/locations/global/workloadIdentityPools/github/attribute.repository/${MTATS_GITHUB_REPO}"

npx -y firebase-tools@latest projects:addfirebase "$P" 2>/dev/null || echo "(Firebase already enabled on $P)"

gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --billing-project="$P" --format='value(displayName)' | grep -qx mtats-monthly || \
  gcloud billing budgets create --billing-account="$BILLING_ACCOUNT" --billing-project="$P" --display-name=mtats-monthly \
    --budget-amount=10USD --filter-projects="projects/${NUMBER}" \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0

echo "GCP_WORKLOAD_IDENTITY_PROVIDER=projects/${NUMBER}/locations/global/workloadIdentityPools/github/providers/github-oidc"
echo "GCP_SERVICE_ACCOUNT=$SA"
```
(`firebase-tools@latest` here runs once, interactively, by the owner; CI pins a version in Task 17.)

- [ ] **Step 3: Read-only checks before running (no owner approval needed).** `bash -n Scripts/gcp-bootstrap.sh && gcloud projects describe mtats-release 2>&1 | head -2 && gcloud billing accounts list --format='table(name,displayName,open)'`. Expected: syntax OK; "does not exist or you do not have permission" for the project (ID free — if it exists and is not the owner's, switch to the fallback name in `release-env.sh` and tell the owner); billing accounts listed. Show the owner the billing account list and ask which to use.
- [ ] **Step 4: Run (owner go-ahead — creates billable resources).** `BILLING_ACCOUNT=<owner's choice> Scripts/gcp-bootstrap.sh`. Expected: ends with the two `GCP_…=` lines and no `WARNING`. Then confirm the rule: `gcloud config get-value project` → `petgo-play-ci`.
- [ ] **Step 5: Repository variables.** `gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER -b "<value printed>" && gh variable set GCP_SERVICE_ACCOUNT -b "<value printed>"`.
- [ ] **Step 6: Commit.** `git add Scripts/gcp-bootstrap.sh Scripts/release-env.sh && git commit -m "GCP bootstrap for the release project"`

---

### Task 17: Site scaffold, Hosting config, placeholder feeds, `site.yml`

**Files:**
- Create: `site/package.json` (via npm), `site/astro.config.mjs`, `site/src/pages/index.astro`, `site/src/data/latest.example.json`, `site/scripts/write-firebase-json.mjs`, `site/scripts/check-dist.mjs`, `site/public/appcast.xml`, `site/public/beta/appcast.xml`, `site/.firebaserc`, `site/.gitignore`, `.github/workflows/site.yml`

**Interfaces:**
- Consumes: `latest.json` schema from Task 15; bucket and project names from `Scripts/release-env.sh`.
- Produces: `npm run build` in `site/` → `site/dist/` plus `site/firebase.json`; with `MTATS_SITE_BOOTSTRAP=1` it builds without `src/data/latest.json`.

- [ ] **Step 1: Scaffold.** `mkdir -p site && cd site && npm init -y >/dev/null && npm install --save-exact astro@<newest astro release at least 14 days old per npm view astro time> && npm install --save-dev --save-exact firebase-tools@<newest firebase-tools release at least 14 days old>`. Then set `site/package.json` `"scripts"` to `{"build": "node scripts/write-firebase-json.mjs && astro build && node scripts/check-dist.mjs", "dev": "astro dev"}` and `"type": "module"`.
- [ ] **Step 2: Config files.**

`site/astro.config.mjs`:
```js
// SPDX-License-Identifier: MIT
import { defineConfig } from 'astro/config';
export default defineConfig({ site: 'https://mtats.app', output: 'static', build: { format: 'file' } });
```

`site/.firebaserc`:
```json
{ "projects": { "default": "mtats-release" } }
```

`site/.gitignore`:
```
node_modules/
dist/
firebase.json
src/data/latest.json
```

`site/src/data/latest.example.json`:
```json
{ "version": "0.1.0", "build": 1, "channel": "stable", "url": "https://mtats.app/releases/mtats-0.1.0.dmg",
  "sizeBytes": 12582912, "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "publishedAt": "2026-10-12T00:00:00+00:00", "minimumSystemVersion": "14.0" }
```

Placeholder feeds `site/public/appcast.xml` and `site/public/beta/appcast.xml` (same content; the release workflow overwrites them in `dist/`):
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel><title>mtats</title><link>https://mtats.app</link><description>mtats updates</description></channel>
</rss>
```

- [ ] **Step 3: Generators and checks.**

`site/scripts/write-firebase-json.mjs`:
```js
// SPDX-License-Identifier: MIT
// Writes site/firebase.json. /download points at the current stable DMG from latest.json.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';

const bootstrap = process.env.MTATS_SITE_BOOTSTRAP === '1';
const latestPath = new URL('../src/data/latest.json', import.meta.url);
if (!existsSync(latestPath) && !bootstrap) {
  console.error('src/data/latest.json missing (set MTATS_SITE_BOOTSTRAP=1 before the first release)');
  process.exit(1);
}
const latest = existsSync(latestPath) ? JSON.parse(readFileSync(latestPath, 'utf8')) : null;
const feedHeaders = [
  { key: 'Content-Type', value: 'application/xml; charset=utf-8' },
  { key: 'Cache-Control', value: 'public, max-age=300' },
];
const redirects = [
  { source: '/releases/:file*', destination: 'https://storage.googleapis.com/mtats-releases/releases/:file', type: 302 },
];
if (latest) {
  redirects.unshift({ source: '/download', destination: `/releases/mtats-${latest.version}.dmg`, type: 302 });
}
const config = {
  hosting: {
    public: 'dist',
    cleanUrls: true,
    headers: [
      { source: '/appcast.xml', headers: feedHeaders },
      { source: '/beta/appcast.xml', headers: feedHeaders },
      { source: '/latest.json', headers: [{ key: 'Cache-Control', value: 'public, max-age=300' }] },
    ],
    redirects,
  },
};
writeFileSync(new URL('../firebase.json', import.meta.url), JSON.stringify(config, null, 2) + '\n');
console.log(`firebase.json written (${latest ? `download → ${latest.version}` : 'bootstrap, no /download'})`);
```

`site/scripts/check-dist.mjs` (spec §Risks: DMGs never in Hosting):
```js
// SPDX-License-Identifier: MIT
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
const LIMIT = 2 * 1024 * 1024;
let bad = [];
function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const s = statSync(p);
    if (s.isDirectory()) walk(p);
    else if (s.size > LIMIT || name.endsWith('.dmg')) bad.push(`${p} (${s.size} bytes)`);
  }
}
walk(new URL('../dist', import.meta.url).pathname);
if (bad.length) { console.error('Files too large for Hosting:\n' + bad.join('\n')); process.exit(1); }
console.log('dist size check OK');
```

- [ ] **Step 4: Content page (structure only; Task 18 is the design pass).** `site/src/pages/index.astro`:

```astro
---
// SPDX-License-Identifier: MIT
import { existsSync, readFileSync } from 'node:fs';
const path = new URL('../data/latest.json', import.meta.url);
const latest = existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : null;
const mb = latest ? (latest.sizeBytes / 1048576).toFixed(1) : null;
const date = latest ? new Date(latest.publishedAt).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' }) : null;
---
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>mtats — Mac stats you wear on your sleeve</title>
    <meta name="description" content="A menu-bar monitor for CPU, memory, GPU and network on Apple Silicon Macs." />
  </head>
  <body>
    <header>
      <h1>mtats</h1>
      <p>Mac stats you wear on your sleeve.</p>
      <p>A menu-bar monitor for CPU, memory, GPU and network. Apple Silicon, macOS 14 or later.</p>
    </header>
    <section aria-label="Menu bar preview" id="menubar"></section>
    <section id="download">
      {latest ? (
        <>
          <a href="/download">Download mtats {latest.version}</a>
          <p>{mb} MB · macOS {latest.minimumSystemVersion} or later · {date}</p>
          <p><a href={`https://github.com/marvinmarnold/mtats/releases/tag/v${latest.version}`}>Also on GitHub Releases</a></p>
        </>
      ) : (
        <p>The first release is on its way.</p>
      )}
    </section>
    <section id="install">
      <h2>Install</h2>
      <ol>
        <li>Open the downloaded DMG.</li>
        <li>Drag mtats to Applications.</li>
        <li>Open mtats from Applications. It's notarized by Apple, so macOS opens it after the usual first-launch prompt.</li>
      </ol>
      <p>mtats lives in the menu bar and has no Dock icon. Updates arrive through the app itself.</p>
    </section>
    <section id="screenshots"></section>
    <section id="privacy">
      <h2>Privacy</h2>
      <p>No telemetry, no crash reporting, no accounts. mtats makes two kinds of outbound request: a daily update check (you can turn it off in Settings) and an optional public-IP lookup (on by default, toggle in Settings). Plugins run with the app's privileges, and mtats asks before loading a third-party plugin for the first time.</p>
    </section>
    <footer>
      <a href="https://github.com/marvinmarnold/mtats">Source on GitHub (MIT)</a> ·
      <a href="https://github.com/marvinmarnold/mtats/releases">Releases</a>
      {latest && <> · Current version {latest.version}</>}
    </footer>
  </body>
</html>
```

- [ ] **Step 5: Build both modes.** `cd site && MTATS_SITE_BOOTSTRAP=1 npm run build && grep -q 'first release is on its way' dist/index.html && cp src/data/latest.example.json src/data/latest.json && npm run build && grep -q 'Download mtats 0.1.0' dist/index.html && grep -q '"/download"' firebase.json && rm src/data/latest.json` → Expected: both builds succeed, `dist size check OK` twice.
- [ ] **Step 6: Bootstrap deploy (owner go-ahead — first deploy to the new project).** `cd site && MTATS_SITE_BOOTSTRAP=1 npm run build && npx firebase deploy --only hosting --project mtats-release --non-interactive`. Expected: `Hosting URL: https://mtats-release.web.app`; `curl -s https://mtats-release.web.app/appcast.xml | grep '<rss'` succeeds.
- [ ] **Step 7: Custom domain (owner).** Firebase console → project `mtats-release` → Hosting → Add custom domain `mtats.app`, then `www.mtats.app` as a redirect to `mtats.app`. Owner adds the shown TXT/A records at the registrar. Wait for the console to show "Connected". Verify: `curl -sI https://mtats.app/appcast.xml | head -1` → `HTTP/2 200`, and `Scripts/release-preflight.sh` no longer fails on the feed (run with `PREFLIGHT_SKIP_BUILD=1 Scripts/release-preflight.sh 0.1.0`; expected to reach the build-skip and print the tag command).
- [ ] **Step 8: `site.yml`.**

```yaml
# SPDX-License-Identifier: MIT
name: site
on:
  push:
    branches: [main]
    paths: ['site/**']
concurrency:
  group: release
  cancel-in-progress: false
permissions:
  contents: read
  id-token: write
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: site/package-lock.json
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}
      - name: Fetch published feeds and latest.json
        working-directory: site
        run: |
          B=https://storage.googleapis.com/mtats-releases
          if curl -fsS -o src/data/latest.json "$B/latest.json"; then echo "using published latest.json"; else rm -f src/data/latest.json; echo "MTATS_SITE_BOOTSTRAP=1" >> "$GITHUB_ENV"; fi
          curl -fsS -o public/appcast.xml "$B/appcast.xml" || true
          mkdir -p public/beta && { curl -fsS -o public/beta/appcast.xml "$B/beta/appcast.xml" || true; }
          curl -fsS -o public/latest.json "$B/latest.json" || true
      - working-directory: site
        run: npm ci && npm run build
      - working-directory: site
        run: npx firebase deploy --only hosting --project mtats-release --non-interactive
```
Then `actionlint .github/workflows/site.yml` and Task 7 Step 4's pinning loop.

- [ ] **Step 9: Commit.** `git add site .github && git commit -m "Site scaffold, Hosting config, placeholder feeds, site workflow" && git push`

---

### Task 18: Site design pass and app icon

**Files:** Modify: `site/src/pages/index.astro`; Create: `site/src/styles/site.css`, `site/public/menubar.svg`, screenshot images under `site/public/screens/`, `Resources/AppIcon.icns`; Modify: `Scripts/package-app.sh` (copy icon), `Scripts/Host-Info.plist.template` (`CFBundleIconFile`).

**Interfaces:** Consumes the page structure from Task 17 (section ids `menubar`, `download`, `install`, `screenshots`, `privacy`). Produces no new interfaces.

- [ ] **Step 1: Brief the owner and get direction.** This is a visual-design task; per the owner's working agreement, design choices are theirs. Present two or three directions for the "wear it on your sleeve" concept (e.g. the menu bar drawn as a shirt cuff; a wrist/sleeve close-up with the four readings; a plain dark menu bar with the readings glowing) and the icon concept, and wait for a choice.
- [ ] **Step 2: Implement the chosen direction** within spec §Website constraints: light and dark themes via `prefers-color-scheme`; no JavaScript required to read the page; only the download block and footer version are data-bound; no third-party fonts, scripts or CDNs; page weight under 1 MB including assets. Use the `frontend-design` skill if available.
- [ ] **Step 3: Screenshots.** From the owner's real app: each widget dropdown and the Settings window, exported as PNG ≤ 200 KB each into `site/public/screens/`.
- [ ] **Step 4: App icon.** Produce a 1024×1024 master, build the `.icns` with `iconutil` from an `AppIcon.iconset` (16…1024 @1x/@2x), save `Resources/AppIcon.icns`. Add to the template `  <key>CFBundleIconFile</key><string>AppIcon</string>` and to `package-app.sh` after the plugin copy: `mkdir -p "$APP/Contents/Resources" && cp Resources/AppIcon.icns "$APP/Contents/Resources/"`.
- [ ] **Step 5: Verify.** `cd site && cp src/data/latest.example.json src/data/latest.json && npm run build && du -sh dist && rm src/data/latest.json` → Expected: build OK, `dist` under 1 MB. `Scripts/tests/run.sh && Scripts/dev.sh` → pass; the owner confirms the icon shows in Finder for `.build/mtats.app` and approves the page via `cd site && npm run dev`.
- [ ] **Step 6: Commit.** `git add site Resources Scripts && git commit -m "Site design and app icon" && git push`

---

### Task 19: `release.yml`, job 2 (publish)

**Files:**
- Create: `Scripts/publish.sh`, `Scripts/tests/test-publish.sh`
- Modify: `.github/workflows/release.yml` (append job 2)

**Interfaces:**
- Consumes: artifact `release` from job 1 (Task 15); `Scripts/release-env.sh`; WIF variables (Task 16).
- Produces: `Scripts/publish.sh <artifact-dir> <stable|beta> <version>`; `PUBLISH_DRY_RUN=1` prints the `gcloud` commands instead of running them and simulates "object exists" for names listed in `PUBLISH_FAKE_EXISTING`.

- [ ] **Step 1: Failing test (Review Focus: never overwrite a released DMG).** `Scripts/tests/test-publish.sh`:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "  $*" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
for f in mtats-1.0.0.dmg mtats-1.0.0.dmg.sha256 appcast.xml latest.json; do echo x >"$T/$f"; done

OUT=$(PUBLISH_DRY_RUN=1 Scripts/publish.sh "$T" stable 1.0.0)
grep -q 'gs://mtats-releases/releases/mtats-1.0.0.dmg' <<<"$OUT" || fail "DMG upload missing"
grep -q 'gs://mtats-releases/appcast.xml' <<<"$OUT" || fail "stable appcast upload missing"
grep -q 'gs://mtats-releases/latest.json' <<<"$OUT" || fail "stable latest.json upload missing"
grep -q -- '--project mtats-release' <<<"$OUT" || fail "commands must pass --project"

OUT=$(PUBLISH_DRY_RUN=1 Scripts/publish.sh "$T" beta 1.0.0)
grep -q 'gs://mtats-releases/beta/appcast.xml' <<<"$OUT" || fail "beta appcast path"
grep -q 'gs://mtats-releases/latest.json' <<<"$OUT" && fail "beta must not touch stable latest.json"

PUBLISH_DRY_RUN=1 PUBLISH_FAKE_EXISTING=releases/mtats-1.0.0.dmg Scripts/publish.sh "$T" stable 1.0.0 >/dev/null 2>&1 \
  && fail "an existing DMG name must fail the publish"
exit 0
```
Run: `chmod +x Scripts/tests/test-publish.sh && bash Scripts/tests/test-publish.sh` → Expected: FAIL (`publish.sh` missing).

- [ ] **Step 2: `Scripts/publish.sh`.**

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: publish.sh <artifact-dir> <stable|beta> <version>
# Uploads the release artifact to the bucket. DMG names are immutable: an existing object fails.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/release-env.sh
DIR="$1"; CHANNEL="$2"; VERSION="$3"
case "$CHANNEL" in stable) PREFIX="" ;; beta) PREFIX="beta/" ;; *) echo "channel must be stable or beta" >&2; exit 2 ;; esac
B="gs://$MTATS_BUCKET"; P=(--project "$MTATS_GCP_PROJECT")

run() { if [[ "${PUBLISH_DRY_RUN:-0}" == 1 ]]; then echo "$*"; else "$@"; fi; }
exists() {
  if [[ "${PUBLISH_DRY_RUN:-0}" == 1 ]]; then [[ " ${PUBLISH_FAKE_EXISTING:-} " == *" $1 "* ]]; return; fi
  gcloud storage objects describe "$B/$1" "${P[@]}" >/dev/null 2>&1
}

DMG="releases/mtats-${VERSION}.dmg"
if exists "$DMG"; then echo "publish.sh: $B/$DMG already exists; DMG names are immutable" >&2; exit 1; fi
run gcloud storage cp "$DIR/mtats-${VERSION}.dmg" "$B/$DMG" "${P[@]}" \
  --content-type=application/x-apple-diskimage --cache-control="public, max-age=31536000, immutable"
run gcloud storage cp "$DIR/mtats-${VERSION}.dmg.sha256" "$B/$DMG.sha256" "${P[@]}" --cache-control="public, max-age=31536000, immutable"
run gcloud storage cp "$DIR/appcast.xml" "$B/${PREFIX}appcast.xml" "${P[@]}" \
  --content-type="application/xml; charset=utf-8" --cache-control="no-cache"
run gcloud storage cp "$DIR/latest.json" "$B/${PREFIX}latest.json" "${P[@]}" \
  --content-type=application/json --cache-control="no-cache"
echo "published $VERSION to $CHANNEL"
```
Run: `chmod +x Scripts/publish.sh && Scripts/tests/run.sh` → Expected: all PASS.

- [ ] **Step 3: Append job 2 to `.github/workflows/release.yml`** (under `jobs:`, after job 1):

```yaml
  publish:
    needs: build-sign-notarize
    runs-on: ubuntu-latest
    environment: release
    permissions:
      contents: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - name: Channel and version
        run: |
          VERSION="${GITHUB_REF_NAME#v}"; CHANNEL=stable; [[ "$VERSION" == *-rc.* ]] && CHANNEL=beta
          { echo "MTATS_VERSION=$VERSION"; echo "MTATS_CHANNEL=$CHANNEL"; } >> "$GITHUB_ENV"
      - uses: actions/download-artifact@v4
        with:
          name: release
          path: out
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ vars.GCP_SERVICE_ACCOUNT }}
      - uses: google-github-actions/setup-gcloud@v2
      - name: Upload to bucket
        run: Scripts/publish.sh out "$MTATS_CHANNEL" "$MTATS_VERSION"
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: site/package-lock.json
      - name: Build site with published data
        working-directory: site
        run: |
          B=https://storage.googleapis.com/mtats-releases
          # Stable latest.json drives the page and /download; an rc never changes them.
          if curl -fsS -o src/data/latest.json "$B/latest.json"; then :; else rm -f src/data/latest.json; echo "MTATS_SITE_BOOTSTRAP=1" >> "$GITHUB_ENV"; fi
          curl -fsS -o public/appcast.xml "$B/appcast.xml" || true
          mkdir -p public/beta && { curl -fsS -o public/beta/appcast.xml "$B/beta/appcast.xml" || true; }
          curl -fsS -o public/latest.json "$B/latest.json" || true
          npm ci && npm run build
      - name: Deploy Hosting
        working-directory: site
        run: npx firebase deploy --only hosting --project mtats-release --non-interactive
      - name: GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          PRE=(); [[ "$MTATS_CHANNEL" == beta ]] && PRE=(--prerelease)
          gh release create "$GITHUB_REF_NAME" "out/mtats-${MTATS_VERSION}.dmg" "out/mtats-${MTATS_VERSION}.dmg.sha256" \
            --title "mtats $MTATS_VERSION" --notes-file "out/${MTATS_VERSION}.md" "${PRE[@]}"
```
Then `actionlint .github/workflows/release.yml` → no output, and Task 7 Step 4's pinning loop.

- [ ] **Step 4: Commit and push.** `git add Scripts .github && git commit -m "Release workflow: publish to GCP, Hosting, GitHub" && git push`

---

### Task 20: Merge the pipeline, rc dry runs, VM update test

**Files:** Create: `Releases/0.1.0-rc.1.md`, `Releases/0.1.0-rc.2.md` (each: `# mtats 0.1.0-rc.N` + one line "Release candidate for testing the update path.").

- [ ] **Step 1: Merge (owner go-ahead).** Mark the draft PR ready; after `ci` is green, `gh pr merge --merge`. `git switch main && git pull` (in a worktree on `main`).
- [ ] **Step 2: rc.1.** Commit `Releases/0.1.0-rc.1.md` to `main` via a PR (branch protection), then `Scripts/release-preflight.sh 0.1.0-rc.1` → run the printed tag command (owner go-ahead; owner approves the `release` environment in GitHub). Expected: both jobs green; `https://mtats.app/beta/appcast.xml` contains one item `0.1.0-rc.1`; a GitHub pre-release exists; `https://mtats.app/download` unchanged (still absent before the first stable release).
- [ ] **Step 3: Verify the downloaded artifact on a second machine** (the owner's VM): download `https://mtats.app/releases/mtats-0.1.0-rc.1.dmg`, `shasum -a 256` matches the `.sha256` on the GitHub release, `spctl -a -vv -t open --context context:primary-signature mtats-0.1.0-rc.1.dmg` → `accepted`; install; `spctl -a -vv /Applications/mtats.app` → `source=Notarized Developer ID`; the four widgets appear.
- [ ] **Step 4: VM update test (spec §Testing steps 1–3).** In the VM: `defaults write com.mtats.app updateChannel beta`. Land `Releases/0.1.0-rc.2.md` on `main`, preflight, tag `v0.1.0-rc.2`. In the VM: Settings → Check for Updates… → Expected: Sparkle offers 0.1.0-rc.2 with the notes, installs, relaunches; Settings shows the rc.2 version and a higher build. Then `defaults write com.mtats.app SUScheduledCheckInterval 60` and confirm an automatic check occurs within a few minutes (Sparkle's window or log), then `defaults delete com.mtats.app SUScheduledCheckInterval`.
- [ ] **Step 5: Record results** as a short addendum at the end of the spec's Testing section (dates, versions, pass/fail) and commit via PR.

---

### Task 21: Tag v0.1.0

- [ ] **Step 1: Prerequisites.** Spike (c) recorded; app icon present (Task 18); `Releases/0.1.0.md` on `main` (Task 14); VM: `defaults delete com.mtats.app updateChannel`.
- [ ] **Step 2: Preflight and tag (owner go-ahead; owner approves the environment).** `Scripts/release-preflight.sh 0.1.0` → run the printed tag command.
- [ ] **Step 3: Verify (spec §Phases 6).** `curl -sI https://mtats.app/download | grep -i location` → `/releases/mtats-0.1.0.dmg`; the page at `https://mtats.app` shows 0.1.0 with the right size and date; `curl -s https://mtats.app/appcast.xml | grep -c '<item>'` → `1`; the GitHub Release `v0.1.0` exists; on a Mac that has never run mtats, the DMG installs and opens with no Gatekeeper override.
- [ ] **Step 4: Acceptance (spec §Testing step 5).** After `v0.1.1` exists for a day, confirm the stable-channel update in the VM. Record in the spec.
