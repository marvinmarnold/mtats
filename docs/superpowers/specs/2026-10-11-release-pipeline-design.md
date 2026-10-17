# mtats release pipeline and website — design spec

Status: drafted 2026-10-11 against PR #1 (`marvinmarnold/mtats`, branch `mtats-v1-implementation`, head `6b3bff2`). Decisions 1–13 in the "Decisions & rationale" table were settled with the product owner before this document was written; everything else here is derived from them and from the repo as it stands.

## Summary

Today `Scripts/package-app.sh` produces a DEBUG-only, ad-hoc-signed `.build/mtats.app` with a hardcoded version (0.1.0 / build 1) that cannot be distributed. This document specifies the pipeline that turns a pushed git tag `vX.Y.Z` into: a Release-configuration build, Developer ID signed with the hardened runtime, notarized and stapled, packaged in a signed/notarized DMG, published to a Cloud Storage bucket, announced through a Sparkle appcast at `https://mtats.app/appcast.xml`, downloadable from `https://mtats.app/download`, mirrored as a GitHub Release, and described on a single static Astro page at `https://mtats.app`. It also specifies the GCP project that hosts all of this, how GitHub Actions authenticates to it without key files, and how the owner's existing GCP project (`petgo-play-ci`) is kept out of the blast radius.

Distribution v1 is a free public download. Nothing in this design needs to be rebuilt or reinstalled when payments or license keys are added later, because an installed copy of mtats only ever knows two URLs on a domain the owner controls.

## Spikes (do these before any pipeline work)

Each spike is a throwaway experiment that answers one question the rest of the design depends on. Each states what it decides and what happens if it fails.

| # | Question | How to answer it | Decides | Fallback if it fails |
|---|---|---|---|---|
| (a) | First: does any GitHub-hosted Apple Silicon image ship an Xcode that builds this package (`swift build --build-system swiftbuild` with the local toolchain recorded as Xcode 27.1 / Swift 6.4)? If not, the fallback is a self-hosted runner on a dedicated macOS user or VM, which reopens Decision 8 with the owner. Then: can that runner run `Scripts/smoke-test.sh`? The app creates `NSStatusItem`s via `StatusBarController.present` before the `--smoke-test-exit-after` timer fires; a session with no WindowServer access would fail there. | A one-job workflow on `macos-15` that runs `Scripts/package-app.sh` + `Scripts/smoke-test.sh`. Pass = `PASS` printed. | Whether the release workflow's gate includes the full GUI smoke test (§"Release flow", step 2). | Add a `--smoke-test-headless` mode to `main.swift` that runs `loader.loadAll` and prints `SMOKE_TEST_LOADED_WIDGET_IDS` but skips `statusBar.present`; CI gates on that. The full GUI smoke test then becomes a mandatory item in the local pre-tag checklist (`Scripts/release-preflight.sh`, §"Testing"). The widget-load assertion is the regression that matters (ADR-0005 Task 10 addendum); the status-item path is covered by the owner's manual visual check. |
| (b) | Does the hand-written `swiftc` relink of the Host still work with (1) `swift build -c release --build-system swiftbuild`, whose intermediates path under `.build/out/Intermediates.noindex` is expected to differ from the debug one the current glob matches, (2) `-framework Sparkle` from the prebuilt XCFramework, and (3) `codesign --options runtime` + `com.apple.security.cs.disable-library-validation`? | Locally: build release, relink per §"Bundle layout", ad-hoc sign with `--options runtime` and the entitlements file, run the smoke test. Then `otool -L` the Host and confirm `@rpath/libMTatsPluginKit.dylib` and `@rpath/Sparkle.framework/Versions/B/Sparkle` are undefined references, and `nm` shows `U` (not defined) symbols for `MTatsPluginKit` protocol descriptors, exactly as the Task 10 addendum checks. | The exact object-file glob and link line for `Scripts/package-app.sh` under Release; whether the relink remains the mechanism. | If the swiftbuild intermediates layout proves unstable or differs in a way the glob cannot pin to one configuration, stop depending on SwiftPM's intermediates for the Host entirely: compile `Sources/mtats/*.swift` ourselves with `swiftc -O -wmo -emit-object -module-name mtats -I .build/release` and link those objects. The Host is six files with no third-party dependencies, so a direct compile is small and removes the only fragile path in the build. The plugin and Core targets keep using SwiftPM. |
| (c) | Does a Developer-ID-signed, notarized, hardened-runtime Host load an ad-hoc-signed third-party plugin from `~/Library/Application Support/mtats/Plugins/` after the one-time trust prompt in `main.swift`? Two sub-cases: the bundle without a quarantine xattr (built locally), and the same bundle with `com.apple.quarantine` set (as it would be after a browser download). | Locally, after Phase 2 (signing works): install the `HelloWidget.bundle` from the `mtats-example-plugin` repo (plan Task 11), ad-hoc signed, into the user plugins directory; launch the notarized app; accept the prompt; confirm the widget appears. Repeat with `xattr -w com.apple.quarantine "0083;...;Safari;" HelloWidget.bundle`. | Whether ADR-0001's trust boundary works as designed under the real production signing, and what the third-party plugin README must tell authors. | Non-quarantined failure: the entitlement or signing order is wrong — fix in `Scripts/sign-app.sh`; this must not ship broken because built-in plugins use the identical load path. Quarantined failure (expected to be Gatekeeper refusing a quarantined, non-notarized bundle on `dlopen`): this is Apple policy, not a bug. Document for plugin authors that a downloaded plugin must be Developer ID signed and notarized, or the user must clear quarantine; the Host's diagnostics view (`DiagnosticsView`) already surfaces the skip reason. |

### Spike (b) outcome (2026-10-12)

The relink works under Release. With `swift build -c release --build-system swiftbuild`, the Host's objects are in exactly one directory, `.build/out/Intermediates.noindex/mtats.build/Release/mtats-p.build/Objects-normal/arm64` (Debug is the same path with `Debug`), so `package-app.sh` selects the directory by configuration name and fails unless exactly one matches. Relinked with `-L .build/release -lMTatsPluginKit -Xlinker -rpath -Xlinker @executable_path/../Frameworks`, `nm` shows the `PluginEntry` protocol descriptor as `U` (undefined), as ADR-0005 requires. Sparkle works as a SwiftPM `.binaryTarget` (`import Sparkle` compiles, `swift test` still passes; the framework appears at `.build/artifacts/<package-dir>/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`) and links with `-F <dir> -framework Sparkle`, giving `@rpath/Sparkle.framework/Versions/B/Sparkle`. A bundle with the dylib and Sparkle in `Contents/Frameworks`, the XPC services removed, signed inside-out ad-hoc with `--options runtime` and the `disable-library-validation` entitlement, passes `codesign --verify --deep --strict` and loads all five widgets, including the ad-hoc-signed third-party HelloWidget (the auto-approved smoke-test path; the unquarantined half of spike (c) is therefore already encouraging but is re-checked with the real Developer ID in Phase 2). Sparkle's sandboxing documentation states that non-sandboxed apps can remove the XPC services, so they are stripped. The fallback (direct `swiftc` compile of the Host) is not needed.

Pins chosen: Sparkle 2.10.0 (published 2026-09-13, 29 days old). SwiftPM binary-target checksum `17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959`. CLI tools tarball `Sparkle-2.10.0.tar.xz` SHA-256 `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`; its members are named `./bin/generate_keys`, `./bin/sign_update`, `./bin/generate_appcast`, so extraction must name `./bin`.

### Spike (a) outcome (2026-10-17)

A GitHub-hosted image works; no self-hosted runner is needed and Decision 8 stands. On `macos-26` with Xcode 26.6.0 (`MTATS_MACOS_RUNNER=macos-26`, `MTATS_XCODE_PATH=/Applications/Xcode_26.6.0.app`) the package builds with `--build-system swiftbuild`, tests pass when run through `Scripts/swift-test.sh` (which puts Sparkle on the dyld path for the test process), and `Scripts/package-app.sh -c release` packages after two fixes it surfaced: the build products directory is taken from `swift build --show-bin-path` instead of being assumed, and `find-host-objects.sh` accepts both object-directory layouts. `Scripts/smoke-test.sh` prints `PASS` on the hosted runner, so the full GUI smoke test is the CI gate (`MTATS_CI_SMOKE_TEST=Scripts/smoke-test.sh`) and the `--smoke-test-headless` fallback was not built. `macos-15` with Xcode 26.3 cannot build the package (`import Sparkle`: module not found), so it is not an option.

### Spike (c) outcome (2026-10-17)

The production signing chain is verified on a real artifact: the `v0.1.0-rc.2` DMG, downloaded from the bucket, passes `xcrun stapler validate`, `spctl -a -vv -t open --context context:primary-signature` reports `accepted` / `source=Notarized Developer ID`, and the app inside is signed with the hardened runtime by Team `7QPHD26GNA`. The third-party-plugin sub-cases (ad-hoc `HelloWidget.bundle` with and without `com.apple.quarantine` under the Developer ID Host) are not part of this record; the unquarantined path is covered by spike (b)'s ad-hoc result and the identical built-in load path.

Spike (b) blocks Phase 1. Spike (c) blocks nothing but must be answered before v0.1.0 is tagged. Spike (a) blocks the CI workflow's final shape (Phase 4) only.

## Goals

- A release is produced by exactly one action: pushing an annotated tag `vX.Y.Z` to `marvinmarnold/mtats`. No manual signing, uploading, or editing of XML.
- Every shipped artifact (app, every nested plugin, the dylib, Sparkle, the DMG) is Developer ID signed with the hardened runtime, notarized, and stapled; `spctl -a -vv` reports `Notarized Developer ID` on a clean Mac.
- Installed copies self-update through Sparkle over `https://mtats.app/appcast.xml`, with updates signed by an EdDSA key only CI and the owner hold.
- The website never shows a stale version, size, or date: those come from a `latest.json` the release workflow writes.
- The release never passes if `swift test` or the smoke test fails.
- No GCP work ever touches `petgo-play-ci` or the owner's gcloud default configuration.
- Adding paid distribution later is a server-side change (serve `/download` and `/appcast.xml` from Cloud Run), not an app change.
- Every secret lives in GitHub Actions secrets or the owner's keychain/password manager; no key files in the repo or on CI disks after the job ends.

## Non-goals

| Deferred | Why |
|---|---|
| `MTatsPluginKit.xcframework` as a frozen, versioned artifact for third-party plugin authors (ADR-0005's actionable requirement) | There are no outside plugin authors yet. The example plugin (plan Task 11) links against the local `.build/debug` and proves the mechanism. The release pipeline must not break this later: `libMTatsPluginKit.dylib` keeps its install name `@rpath/libMTatsPluginKit.dylib` and the same `pluginAPIVersion` semantics (ADR-0004), so a future xcframework is additive. |
| Payments, license keys, a paid tier | ADR-0002 keeps the lever; v1 distribution is free. The two-stable-URL rule (Decision 2) is the only thing v1 does for it. |
| Homebrew cask, `curl \| sh` installer, `.pkg` | One install channel (DMG) plus one update channel (Sparkle) is enough for v1; a cask can be added once there is a stable download URL, which this design provides. |
| Intel / universal builds | ADR-0003. The runner, the Sparkle slice, and every `arm64` glob in the scripts assume Apple Silicon only. |
| Telemetry, crash reporting | Privacy note on the website promises none; Sparkle's system-profile reporting is disabled (`SUEnableSystemProfiling` absent, defaults to false). |
| Sparkle delta updates, a public beta channel | `generate_appcast` is only ever given the new DMG, so no deltas. The `beta` channel in §"Auto-update" exists for the owner's own update testing, not for users. |
| Custom DMG background art, app icon design | Visual design gets its own pass in the implementation plan. The DMG is a plain `hdiutil` image with an `Applications` symlink. The app icon is an open item because Sparkle's update dialog and the Finder show it. |
| CI on every push/PR beyond `swift build` + `swift test` | The verification loop (`Scripts/verify.sh`, GLM review) stays local per v1 spec §8. |
| Rotating signing keys as a routine | Documented as an incident procedure only (§"Security"). |

## Decisions & rationale

| # | Decision | Rationale | Rejected alternatives |
|---|---|---|---|
| 1 | Developer ID signing, hardened runtime, notarization, stapling. A "Developer ID Application" certificate must be created and exported as `.p12` for CI; this Mac currently has zero code-signing identities (`security find-identity -v -p codesigning` found none at plan start; unverified since). | Owner is enrolled in the Apple Developer Program. Without notarization, Gatekeeper blocks a direct-download app on macOS 14/15 with no "open anyway" path short of System Settings. | Ad-hoc signing (current): blocked by Gatekeeper. Mac App Store: ADR-0003 (sandbox breaks sensor reads and dynamic plugins). |
| 2 | Free public download. The app embeds exactly two URLs: `https://mtats.app/appcast.xml` (Sparkle feed) and `https://mtats.app/download` (website button; not embedded in the app but the only download URL ever published). | Payments deferred. Both URLs are on an owner-controlled domain, so a Cloud Run service can later sit behind them to gate by license without rebuilding or reinstalling anything. | Baking a storage.googleapis.com or `*.web.app` URL into the app: would freeze the hosting choice into every installed copy forever. |
| 3 | Install: signed + notarized DMG, drag to Applications. Update: Sparkle 2. | Standard for menu-bar utilities (iStat Menus, Stats). Sparkle handles download, signature check, replacement, relaunch, and its own UI. | Homebrew/curl/pkg: see Non-goals. Hand-rolled updater: Sparkle's code-signing continuity check and EdDSA verification are the hard parts. |
| 4 | Feed and download on `mtats.app`. `.app` is HSTS-preloaded: browsers and Sparkle will only ever use HTTPS. A storage.googleapis.com URL may be used during development only, never in a tagged build. | The feed URL is baked into every installed copy. Changing it later requires every user to reinstall unless an update is shipped first (§"Auto-update"). | — |
| 5 | Single static Astro page, branding "Mac stats you wear on your sleeve". Contents fixed in §"Website". | Static page is cheapest to host and fastest to load; Astro gives build-time data import for `latest.json` with zero client JS. | Next.js/SPA: no dynamic content to justify it. Plain HTML: fine too, but Astro's component model makes the design pass cheaper. |
| 6 | Hosting Approach A: Firebase Hosting (site, `appcast.xml`, `latest.json`, `/download` and `/releases/*` redirects) + one Cloud Storage bucket for versioned DMGs. | Firebase Hosting is free at this scale (10 GB storage, 360 MB/day egress on the no-cost tier), gives a custom domain with managed TLS and a CDN, and supports redirects with path captures. DMGs (~10–20 MB each, unverified) go in a bucket so the Hosting egress allowance is not consumed by downloads; bucket egress is pay-per-GB with no fixed cost. | Cloud Storage + external HTTPS load balancer + Cloud CDN: ~$18/month fixed (forwarding rule) at zero traffic. Cloud Run serving everything now: over-built for a free v1 with no logic to run; kept as the documented path for paid distribution. GitHub Pages + GitHub Releases as the CDN: GitHub Releases URLs are not on `mtats.app` (Decision 4) and offer no redirect control. |
| 7 | New GCP project `mtats-release` (ID availability unverified), on the owner's existing billing account, labeled `app=mtats`, $10/month budget with 50/90/100% email alerts, minimal APIs, one public-read versioned bucket, Workload Identity Federation for GitHub Actions restricted to `marvinmarnold/mtats` and `v*` tags, least-privilege service account, DNS done manually by the owner. | Project-level isolation is the only clean billing and IAM boundary from `petgo-play-ci`. WIF removes long-lived key files. | Reusing `petgo-play-ci`: cross-contaminates billing, IAM, and quota; one mistake in a Firebase deploy could hit the pet app. Service-account JSON key in GitHub secrets: a long-lived credential that outlives any rotation discipline. |
| 8 | GitHub Actions on `macos-15` (Apple Silicon), triggered by tag `vX.Y.Z` (and `vX.Y.Z-rc.N` as a dry run). Steps in §"Release flow". | GitHub-hosted runners avoid maintaining a self-hosted Mac; the `macos-14`+ images are arm64. | Self-hosted runner on the owner's Mac: a signing machine that also runs the owner's browser. Local-only release script: no audit trail, and the owner's laptop becomes a single point of failure. |
| 9 | Host entitlements: exactly `com.apple.security.cs.disable-library-validation = true`. Not sandboxed. | ADR-0001: third-party plugins signed by other teams cannot load under the hardened runtime without it. ADR-0003: no sandbox. | `allow-unsigned-executable-memory`, `allow-jit`, `allow-dyld-environment-variables`, `disable-executable-page-protection`: none needed by the Host or any plugin; each weakens the hardened runtime and draws notarization scrutiny. |
| 10 | `CFBundleShortVersionString` = tag minus the leading `v`; `CFBundleVersion` = `git rev-list --count HEAD` at the tagged commit, with a workflow guard that it is strictly greater than the build number currently in the target channel's appcast and that the tagged commit is an ancestor of `origin/main`. | Sparkle orders releases by `CFBundleVersion`, so it must be strictly increasing. Commit count is derivable locally and in CI from the commit alone (reproducible: re-running the workflow yields the same number), unlike the run number. The guard turns the two ways it can fail to increase (history rewrite, tagging off a side branch) into a hard workflow failure. | `GITHUB_RUN_NUMBER`: strictly increasing but resets if the workflow file is renamed, is not derivable locally, and makes a re-run produce a different build from the same source. Hand-edited build number: the hardcoded `1` is the problem being fixed. |
| 11 | `libMTatsPluginKit.dylib` and `Sparkle.framework` move to `Contents/Frameworks/`; Host rpath `@executable_path/../Frameworks`. Sparkle's prebuilt XCFramework is declared as a SwiftPM `.binaryTarget(url:checksum:)` (Sparkle's own `Sparkle-for-Swift-Package-Manager.zip` release asset), so SwiftPM can compile `import Sparkle` in the Host sources; the hand-written relink then links it explicitly with `-F`/`-framework Sparkle`. Sparkle's command-line tools (`generate_keys`, `sign_update`, `generate_appcast`) come from the matching `Sparkle-<version>.tar.xz`, fetched by `Scripts/fetch-sparkle-tools.sh` with a recorded SHA-256. Settings gets "Check for Updates…"; background checks on by default. | `Contents/Frameworks` is the location Apple's signing and notarization tooling expects for nested frameworks. The Host is linked by a hand-written `swiftc` line that bypasses SwiftPM's linker (ADR-0005 Task 10 addendum), so the relink must name the framework itself; but the Host's sources are still *compiled* by SwiftPM, so SwiftPM must know the module. A binary target supplies the module at compile time, and because it is a dynamic framework it is not subject to the static-embedding problem the relink exists for. (Review fix, 2026-10-12: the first draft said 'not through SwiftPM', which would have failed to compile `import Sparkle`.) | Linking the XCFramework only at relink time with no SwiftPM declaration: `import Sparkle` would not compile, because SwiftPM compiles the Host's objects. Keeping the dylib in `Contents/MacOS`: works, but `codesign`/`notarytool` treat loose dylibs there as executables and it complicates the inside-out signing. |
| 12 | Deferred items in §"Non-goals". | — | — |
| 13 | Work order: (0) merge PR #1 after the owner's visual check, (1) release build + versioning + bundle layout, (2) local signing + notarization, (3) Sparkle, (4) CI workflow, (5) GCP + site, (6) tag v0.1.0. | Each phase is verifiable on its own before the next adds a dependency; the GCP project is created last so nothing bills before it is needed and the feed URL is only baked once it resolves. | — |

## Architecture overview

```
developer                         GitHub                                  GCP project mtats-release
---------                         ------                                  -------------------------
git tag v0.1.0 ──push──▶ release.yml (tag v*)
                         │
                         ├─ job build-sign-notarize (macos-15, arm64)
                         │    swift test ─▶ package-app.sh -c release ─▶ smoke-test.sh
                         │    sign-app.sh (Developer ID, hardened runtime, entitlements)
                         │    notarize.sh app ─▶ staple
                         │    make-dmg.sh ─▶ notarize.sh dmg ─▶ staple
                         │    sign_update (EdDSA) + generate_appcast ─▶ artifact: dmg + appcast + metadata
                         │
                         └─ job publish (ubuntu, WIF → github-release@mtats-release)
                              gsutil cp dmg ─────────────────────────────▶ bucket mtats-releases/releases/mtats-0.1.0.dmg
                              upload appcast.xml (from job 1) ──────────▶ bucket /appcast.xml   (authoritative copy)
                              write latest.json ────────────────────────▶ bucket /latest.json
                              astro build (site/, imports latest.json)
                              firebase deploy --only hosting ───────────▶ Hosting site (mtats.app):
                              gh release create v0.1.0 dmg                  /            static page
                                                                            /appcast.xml
                                                                            /latest.json
                                                                            /download      302 → /releases/mtats-0.1.0.dmg
                                                                            /releases/*    302 → storage.googleapis.com/mtats-releases/releases/*

installed mtats.app ── Sparkle ──GET https://mtats.app/appcast.xml──▶ Hosting ──enclosure url──▶ /releases/... ──302──▶ bucket
browser ──────────────────────────GET https://mtats.app/download───▶ Hosting ──302──▶ /releases/... ──302──▶ bucket
```

The app and the browser only ever address `mtats.app`. The bucket is reachable directly but never published or embedded; replacing the Hosting redirects with a Cloud Run service later changes nothing for installed copies.

## Release flow, step by step

Trigger: push of a tag matching `^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$`. Any other `v*` tag fails the workflow at step 1. Tags with `-rc.N` are prereleases and publish to the `beta` channel (§"Auto-update"); they are the dry-run mechanism.

Job 1, `build-sign-notarize`, on `macos-15` (GitHub-hosted, arm64):

1. **Checkout** with full history (`fetch-depth: 0`) and tags; compute `MTATS_VERSION` (tag minus `v`) and `MTATS_BUILD` (`git rev-list --count HEAD`). Fail unless `git merge-base --is-ancestor "$GITHUB_SHA" origin/main`. Fail unless `Releases/${MTATS_VERSION}.md` exists (release notes; used by Sparkle and the GitHub Release).
2. **Gate**: `swift test --build-system swiftbuild`. Then `Scripts/package-app.sh -c release` (ad-hoc signed at this point) and `Scripts/smoke-test.sh` (or the headless variant per spike (a)). Either failing fails the release before any secret is touched.
2a. **Update guard**: fetch the current channel appcast anonymously over HTTPS from the public bucket (`https://storage.googleapis.com/mtats-releases/appcast.xml`, or `beta/appcast.xml`; an empty-channel placeholder if this is the first release). Extract the highest `sparkle:version`; fail unless `MTATS_BUILD` is greater. This runs before signing so a bad build number wastes no notarization time.
3. **Import signing identity**: create a temporary keychain with a random password, import the `.p12` from `APPLE_DEVELOPER_ID_P12_BASE64` / `APPLE_DEVELOPER_ID_P12_PASSWORD`, `security set-key-partition-list -S apple-tool:,apple: -s`, add it to the search list. The keychain is deleted in an `if: always()` step.
4. **Sign** with `Scripts/sign-app.sh .build/mtats.app` using the identity `Developer ID Application: <name> (<TEAM_ID>)` found via `security find-identity -v -p codesigning` (exactly one must match or the step fails). Order and flags in §"Bundle layout & signing".
5. **Verify** before submitting: `codesign --verify --deep --strict --verbose=2 .build/mtats.app` and `codesign -d --entitlements - .build/mtats.app` must show exactly the expected entitlement.
6. **Notarize the app**: `ditto -c -k --keepParent .build/mtats.app .build/mtats.zip`; `xcrun notarytool submit .build/mtats.zip --key <p8 temp file> --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" --wait --timeout 30m`; on anything but `Accepted`, fetch the log with `notarytool log` and fail. `xcrun stapler staple .build/mtats.app`.
7. **DMG**: `Scripts/make-dmg.sh .build/mtats.app .build/mtats-${MTATS_VERSION}.dmg` — staging folder containing `mtats.app` and a symlink `Applications -> /Applications`; `hdiutil create -volname "mtats ${MTATS_VERSION}" -srcfolder <staging> -fs HFS+ -format UDZO -ov <out>`.
8. **Sign, notarize, staple the DMG**: `codesign --sign "$IDENTITY" --timestamp <dmg>`; `notarytool submit <dmg> ... --wait`; `xcrun stapler staple <dmg>`; `spctl -a -vv -t open --context context:primary-signature <dmg>` must print `accepted`.
9. **Sparkle signature**: `sign_update --ed-key-file <temp file from SPARKLE_ED25519_PRIVATE_KEY> <dmg>` → `sparkle:edSignature="…" length="…"` captured to `signature.txt`. Temp key file removed in an `if: always()` step.
10. **Metadata**: write `release-meta.json` with version, build, dmg filename, size in bytes, SHA-256, `minimumSystemVersion` (read from the app's `Info.plist`), channel (`stable` or `beta`), ISO-8601 timestamp.
10a. **Appcast**: run Sparkle's `generate_appcast` (a macOS-only binary, which is why this is in job 1 and not on the Linux publish job: npm and gcloud never run on the signing machine) on a folder containing the fetched channel appcast, the new DMG, and `mtats-${MTATS_VERSION}.html` (release notes converted from Markdown), with `--download-url-prefix https://mtats.app/releases/` and `--link https://mtats.app`. The resulting `appcast.xml` travels in the job artifact; job 2 only uploads it.

11. **Upload job artifact**: the DMG, `signature.txt`, `release-meta.json`, `appcast.xml`, `Releases/${MTATS_VERSION}.md`.

Job 2, `publish`, on `ubuntu-latest`, `needs: build-sign-notarize`, `permissions: { id-token: write, contents: write }`, GitHub environment `release`:

12. **Authenticate to GCP** via `google-github-actions/auth` with `workload_identity_provider` and `service_account` from repository variables; no key JSON anywhere.
13. **Upload DMG** to `gs://mtats-releases/releases/mtats-${MTATS_VERSION}.dmg` with `Content-Type: application/x-apple-diskimage`, `Cache-Control: public, max-age=31536000, immutable`, with `gcloud storage cp --if-generation-match=0` (a server-side creation precondition: GCS refuses to overwrite an existing object). `Scripts/publish.sh` first fetches the object anonymously: a 404 means upload; an existing object whose SHA-256 equals the artifact's `.sha256` is skipped (a re-run resumes); an existing object with different bytes fails the release, since DMG names are immutable; any other fetch result (5xx, 403, transport error) aborts.
14. **Upload appcast**: copy the artifact's `appcast.xml` to the bucket as the channel's `appcast.xml` (`Cache-Control: no-cache`; object versioning keeps the previous copy).
15. **latest.json**: write `{ "version", "build", "channel", "url": "https://mtats.app/releases/mtats-X.Y.Z.dmg", "sizeBytes", "sha256", "publishedAt", "minimumSystemVersion" }` to the bucket as `latest.json` (stable) or `beta/latest.json`.
16. **Site build**: `npm ci` in `site/`, copy `latest.json` to `site/src/data/latest.json`, `npm run build`; generated `firebase.json` redirects `/download` to the stable DMG URL. Copy `appcast.xml`, `latest.json`, and the `beta/` pair into `site/dist/`.
17. **Deploy**: `firebase deploy --only hosting --project mtats-release --non-interactive`. Prereleases deploy too (the beta appcast must be live for the VM test), but `/download` and `latest.json` are only changed by stable tags.
18. **GitHub Release**: `gh release create "$TAG" <dmg> <dmg>.sha256 --title "mtats $MTATS_VERSION" --notes-file Releases/${MTATS_VERSION}.md` (`--prerelease` for rc tags).

If any step after 13 fails, re-running the failed job is safe: step 13 skips a byte-identical DMG, steps 14–17 re-upload and redeploy the same artifact, and step 18 uploads the assets to an existing release (`gh release view`, then `gh release upload --clobber`) instead of creating it. See the runbook in §"Testing & verification".

As implemented (2026-10-17 review fixes), job 2 runs checkout (with `persist-credentials: false`), artifact download, `Scripts/site-data.sh` and `npm ci && npm run build` before `google-github-actions/auth`, so no npm package's install scripts or build code runs while a GCP credential exists; only `firebase deploy` does. The released channel's site data (step 16) comes from the artifact, the other channel's from the public bucket; only a 404 counts as "not published yet" (`Scripts/fetch-published.sh`), any other fetch failure fails the job instead of deploying bootstrap mode or the empty placeholder feed. Job 1's appcast fetch (step 10a) follows the same rule, so a transient error cannot truncate feed history.

## Bundle layout & signing / entitlements

Target layout of `.build/mtats.app`:

```
mtats.app/Contents/
  Info.plist                       generated by package-app.sh from Scripts/Host-Info.plist.template
  MacOS/mtats                      Host, relinked by swiftc; rpath @executable_path/../Frameworks
  Frameworks/libMTatsPluginKit.dylib   install name @rpath/libMTatsPluginKit.dylib (unchanged)
  Frameworks/Sparkle.framework     from the XCFramework's macos-arm64_x86_64 slice
  Resources/Plugins/CPUWidget.bundle
  Resources/Plugins/RAMWidget.bundle
  Resources/Plugins/GPUWidget.bundle
  Resources/Plugins/NetworkWidget.bundle
  Resources/AppIcon.icns           once the icon exists (open item); CFBundleIconFile added then
  _CodeSignature/                  app seal; nested code each carries its own
```

Changes to `Scripts/package-app.sh`:

- Accept `-c debug|release` (default `debug`; `Scripts/dev.sh` keeps calling it with the default). Build with `swift build -c "$CONFIGURATION" --build-system swiftbuild`; link against `.build/$CONFIGURATION`.
- Object glob: the current `find .build/out/Intermediates.noindex -path "*/mtats-p.build/Objects-normal/arm64/*.o"` is expected to match both configurations' intermediates once both have been built on the same checkout, which would duplicate every symbol at link time. The release glob must be constrained to the configuration being built (the exact path component is what spike (b) determines; unverified) and the script must fail if the matched objects come from more than one `*.build` directory or from none. Release relink flags: the objects were compiled by SwiftPM with `-O`; the link line adds `-Xlinker -rpath -Xlinker @executable_path/../Frameworks`, `-L .build/release -lMTatsPluginKit`, `-F <sparkle-slice-dir> -framework Sparkle`, and drops the current `@executable_path` rpath.
- Sparkle framework: `Package.swift` gains `.binaryTarget(name: "Sparkle", url: "https://github.com/sparkle-project/Sparkle/releases/download/<SPARKLE_VERSION>/Sparkle-for-Swift-Package-Manager.zip", checksum: "<computed with swift package compute-checksum>")` and the `mtats` target depends on it. SwiftPM downloads and verifies it into `.build/artifacts/`. `package-app.sh` locates `Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework` under `.build/artifacts`, passes its parent directory to the relink with `-F`, and copies the framework into `Contents/Frameworks/`. The version chosen in Phase 3 is the newest Sparkle 2.x release at least 14 days old at that time.
- Sparkle tools: `Scripts/fetch-sparkle-tools.sh` downloads `Sparkle-<SPARKLE_VERSION>.tar.xz` into `.build/sparkle-tools/` (gitignored), verifies `SPARKLE_TOOLS_SHA256` with `shasum -a 256 -c`, and extracts `bin/`. Same version as the binary target; both pins live in the repo.
- `Scripts/build-plugin.sh`: accept the configuration; use `-I/-L .build/$CONFIGURATION`; for release, omit the dev-only rpath (`@loader_path/../../../../debug`) entirely. It is harmless (dyld matches the install name first, ADR-0005) but it is a path into a build directory and there is no reason to ship it.
- The dylib's install name stays `@rpath/libMTatsPluginKit.dylib`, which is what every plugin, including the example third-party plugin, already references.
- Default signing stays ad-hoc (`codesign -s -`) so dev builds and the CI gate (step 2) need no identity. `--deep` is removed in favor of explicit inside-out signing (below), used for both ad-hoc and Developer ID so the two paths cannot diverge.

`Scripts/sign-app.sh <app> [identity]` signs inside-out. Every call uses `--force --timestamp --options runtime` (for ad-hoc, `--timestamp` is dropped since there is no identity to timestamp against). Order:

1. `Contents/Frameworks/libMTatsPluginKit.dylib` (identifier `com.mtats.MTatsPluginKit`).
2. Sparkle nested code. mtats is not sandboxed, and Sparkle 2's XPC services exist for sandboxed hosts, so `package-app.sh` removes `Sparkle.framework/Versions/B/XPCServices` when copying the framework (review fix, 2026-10-12; confirm against the pinned version's sandboxing documentation in Phase 3 — if that documentation says otherwise, keep them and sign `Installer.xpc` and `Downloader.xpc` first, the latter with `--preserve-metadata=entitlements`). Then sign `.../Versions/B/Autoupdate`, `.../Versions/B/Updater.app`, then `Sparkle.framework` itself. The script enumerates what exists rather than hardcoding the list.
3. Each `Contents/Resources/Plugins/*.bundle`, with `--identifier` read from that bundle's own `CFBundleIdentifier` (review fix, 2026-10-12: `build-plugin.sh` currently signs with `com.mtats.plugin.CPU` while the plist says `com.mtats.plugin.cpu`). Nested code must also carry the hardened runtime for notarization to accept the app.
4. `mtats.app` with `--entitlements Scripts/mtats.entitlements --identifier com.mtats.app`.

`Scripts/mtats.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
```

Requested: `com.apple.security.cs.disable-library-validation` only (ADR-0001). Not requested, deliberately: `com.apple.security.app-sandbox` (ADR-0003), `com.apple.security.cs.allow-unsigned-executable-memory`, `com.apple.security.cs.allow-jit`, `com.apple.security.cs.allow-dyld-environment-variables`, `com.apple.security.cs.disable-executable-page-protection`, `com.apple.security.get-task-allow` (must be absent or notarization rejects the build; the `swiftc` relink does not add it, and `sign-app.sh` asserts its absence). Network access needs no entitlement outside the sandbox. Plugin bundles get no entitlements file (none needed; they inherit the Host's process).

Library validation being disabled means the Host will `dlopen` any validly signed code; `PluginLoader.hasValidSignature` still rejects unsigned bundles and `main.swift` still prompts on first third-party load. Built-in plugins are signed by the same Team ID, so they would load even with validation enabled; the entitlement exists only for third parties.

## Versioning

| Field | Source | Example for tag `v0.1.0` |
|---|---|---|
| `CFBundleShortVersionString` | tag without `v` | `0.1.0`; `0.1.0-rc.1` for a prerelease |
| `CFBundleVersion` | `git rev-list --count HEAD` at the tagged commit | `137` (illustrative) |
| `SUFeedURL` | constant in template, release only | `https://mtats.app/appcast.xml` |
| `SUPublicEDKey` | constant in template, committed | base64 EdDSA public key from `generate_keys` |
| `SUEnableAutomaticChecks` | constant | `true` (Decision 11) |
| `SUScheduledCheckInterval` | constant | `86400` (Sparkle's default, stated explicitly) |
| `LSMinimumSystemVersion` | constant | `14.0` (as today; `Package.swift` says `.macOS(.v14)`) |
| `CFBundleIdentifier`, `CFBundleName`, `CFBundleExecutable`, `CFBundlePackageType`, `LSUIElement` | as today | `com.mtats.app`, `mtats`, `mtats`, `APPL`, `true` |
| `CFBundleInfoDictionaryVersion`, `LSApplicationCategoryType`, `NSHumanReadableCopyright` | new constants | `6.0`, `public.app-category.utilities`, `© <year> <owner name>, MIT License` |

`package-app.sh` reads `MTATS_VERSION` and `MTATS_BUILD` from the environment; when unset (local dev) it derives them: version from `git describe --tags --match 'v*' --always --dirty` with the `v` stripped, build from `git rev-list --count HEAD`. The heredoc in the script is replaced by `Scripts/Host-Info.plist.template` with `__VERSION__`, `__BUILD__`, `__COPYRIGHT_YEAR__` substituted by `sed`; debug packages additionally delete the `SUFeedURL` key with `/usr/libexec/PlistBuddy` so an ad-hoc dev build never polls the production feed (Sparkle would also refuse to install an update over an ad-hoc-signed app, since it checks code-signing continuity). The Host starts Sparkle only when `Bundle.main.infoDictionary["SUFeedURL"]` is present.

Plugin bundles' `Info.plist` files (`Plugins/*/Info.plist`) gain `CFBundleShortVersionString`/`CFBundleVersion` substituted from the same two values so every nested bundle reports the Host's version; `MTatsPluginAPIVersion` is unchanged (ADR-0004).

Prerelease ordering: Sparkle compares `CFBundleVersion` first, so `0.1.0-rc.2` (build 137) and `0.1.0` tagged on the same commit have the same build number and Sparkle will not offer the final to a beta-channel install of the rc. That only affects the owner's test VM and is accepted; the stable channel never sees rc builds.

## Auto-update (Sparkle) design

**Integration in the Host.** `main.swift` creates one `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil)` held at top level (like `watcher`), only when `SUFeedURL` is present in `Info.plist` and the process is not in smoke-test mode (no network, no dialogs during `Scripts/smoke-test.sh`). `StatusBarController` receives an optional `UpdateControls` value (`checkForUpdates: () -> Void`, `canCheckForUpdates: AnyPublisher<Bool, Never>`, `automaticallyChecks: Binding<Bool>`) and passes it to `SettingsView`, which adds, below the existing toggles in `settingsForm`: a "Check for Updates…" button (disabled while `canCheckForUpdates` is false), an "Automatically check for updates" toggle bound to `SPUUpdater.automaticallyChecksForUpdates`, and a line showing the installed version and build. When `UpdateControls` is nil (debug builds), these controls are hidden. Sparkle's own windows handle the rest of the UI; `LSUIElement` apps need `NSApp.activate()` before Sparkle shows its first alert, which the delegate does in `updater(_:willScheduleUpdateCheckAfterDelay:)`'s counterpart `updaterWillShowModalAlert`.

**Channels.** `SPUUpdaterDelegate.feedURLString(for:)` returns `https://mtats.app/beta/appcast.xml` when the user default `updateChannel` (domain `com.mtats.app`) equals `beta`, otherwise nil (so the `Info.plist` value is used). This is the only hook needed for the owner to test an rc update in a VM without rebuilding: `defaults write com.mtats.app updateChannel beta`. It is not surfaced in Settings.

**Appcast.** One `appcast.xml` per channel, authoritative copy in the bucket root (`appcast.xml`, `beta/appcast.xml`), served from Hosting at the same paths. Items are produced by Sparkle's `generate_appcast`, which merges into the existing file, so the history of all releases stays in the feed. Each item carries `sparkle:version` (build), `sparkle:shortVersionString`, `sparkle:minimumSystemVersion` (from `LSMinimumSystemVersion`), an embedded `<description>` rendered from `Releases/<version>.md`, and an `<enclosure>` with `url="https://mtats.app/releases/mtats-X.Y.Z.dmg"`, `length`, `type="application/octet-stream"`, and `sparkle:edSignature`. Hosting redirects the enclosure URL to the bucket; Sparkle's downloader follows HTTP redirects, and the EdDSA signature is over the DMG bytes, which a redirect does not alter.

**Keys.** The EdDSA key pair is generated once with Sparkle's `generate_keys` on the owner's Mac (it stores the private key in the login keychain). The private key is exported with `generate_keys -x <file>`, stored in (1) the GitHub secret `SPARKLE_ED25519_PRIVATE_KEY`, (2) the owner's password manager, (3) the owner's login keychain; the exported file is deleted. The public key is committed in `Scripts/Host-Info.plist.template` as `SUPublicEDKey`. CI writes the private key to a temp file only for `sign_update`/`generate_appcast` and removes it in an `always()` step.

**If the EdDSA private key is lost** (all three copies): no update can be produced that existing installs will accept, because they verify against the baked public key. Recovery: generate a new pair, change `SUPublicEDKey`, release; every existing user must download the DMG manually once. The website's download button and a note in the release notes are the only channel to tell them. This is why three copies exist.

**If the EdDSA private key is compromised**: an attacker can sign updates, but can only deliver them by also controlling `mtats.app` (feed) or the user's network with a valid TLS cert for `mtats.app` (HSTS preload rules out plain HTTP). Response in §"Security".

**If the feed domain must change**: Sparkle reads `SUFeedURL` from the installed copy's `Info.plist`, so a domain change is an ordinary update: ship a release under the old domain whose `Info.plist` carries the new `SUFeedURL`; installs that take that update follow the new domain from then on. The old domain must keep serving `appcast.xml` until the update's adoption is acceptable; installs that never check in during that window need a manual download. The same two-step applies to rotating the EdDSA key (ship an update signed with the old key whose plist carries the new public key). Neither can be done retroactively, which is why Decision 4 forbids a provider-owned URL.

## CI workflow design

Files: `.github/workflows/release.yml` (tags `v*`), `.github/workflows/ci.yml` (push and pull_request: `swift build --build-system swiftbuild`, `swift test --build-system swiftbuild`, `Scripts/package-app.sh -c release`, smoke test per spike (a); no secrets), `.github/workflows/site.yml` (push to `main` touching `site/**`: fetch `latest.json`/appcasts anonymously from the public bucket, build, deploy Hosting; needs WIF, see the open item on `main` in the WIF condition).

Runner image: the newest GitHub-hosted Apple Silicon image that ships an Xcode able to build this package (local toolchain, recorded 2026-10-12: Xcode 27.1, Swift 6.4, SDK macOS 27.0; `--build-system swiftbuild` requires a Swift 6.x toolchain). Whether any hosted image currently has a suitable Xcode is unverified and is the first question spike (a) answers. Xcode is selected explicitly with `sudo xcode-select -s`. `macos-15` is used in this document as a stand-in for that image name. All third-party actions pinned to a full commit SHA. Concurrency group `release` with `cancel-in-progress: false` so two tags cannot publish at once. Job 1 has no `id-token` permission and never runs `npm` or `gcloud`; job 2 references no Apple or Sparkle secret. The `release` environment holds every secret below, restricted to deployments from tags `v*`, with the owner as required reviewer. Both jobs reference the environment (job 2 needs its GCP variables), so the owner approves twice per release: before job 1 (before any secret is read) and again before job 2 publishes, roughly 30–60 minutes later. This double approval is accepted (review M-5, 2026-10-17); a run waiting for the second approval holds the shared `release` concurrency group, and a pending run can be cancelled by newer queued runs in that group (a cancelled tag run can be re-run from the Actions UI). Strictly, the environment's Apple/Sparkle secrets are *available* to job 2; it does not reference them.

| Secret / variable | Kind | Purpose | Where it comes from |
|---|---|---|---|
| `APPLE_DEVELOPER_ID_P12_BASE64` | secret | Developer ID Application certificate + private key for `codesign` | Keychain Access export of the certificate created at developer.apple.com (steps in Open items), then `base64 -i cert.p12` |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | secret | Password set on the `.p12` at export | Chosen at export; also in the owner's password manager |
| `APPLE_TEAM_ID` | variable | Selects the identity (`Developer ID Application: … (<TEAM_ID>)`) and is checked against the signed app | developer.apple.com → Membership details |
| `APPLE_NOTARY_KEY_ID` | variable | `notarytool --key-id` | App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys (Developer role is sufficient for notarization) |
| `APPLE_NOTARY_ISSUER_ID` | variable | `notarytool --issuer` | Same page, Issuer ID |
| `APPLE_NOTARY_KEY_P8` | secret | The API key's `.p8` contents for `notarytool --key` | Downloadable exactly once from that page; also stored in the owner's password manager |
| `SPARKLE_ED25519_PRIVATE_KEY` | secret | `sign_update` / `generate_appcast` | `generate_keys -x` on the owner's Mac |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | variable | `projects/<number>/locations/global/workloadIdentityPools/github/providers/github-oidc` | Output of the WIF setup in Phase 5 |
| `GCP_SERVICE_ACCOUNT` | variable | `github-release@mtats-release.iam.gserviceaccount.com` | Phase 5 |
| `GITHUB_TOKEN` | built-in | `gh release create` | Automatic; job 2 requests `contents: write` |

`SUPublicEDKey`, `SPARKLE_VERSION`, `SPARKLE_SHA256`, the bucket name, and the Hosting site ID are not secrets and live in the repo.

## GCP resources

Project ID `mtats-release` is proposed; availability is unverified. The project number (needed in the WIF provider name) is known only after creation.

| Resource | Name | Configuration | Why |
|---|---|---|---|
| Project | `mtats-release` | Billing: owner's existing billing account. Labels `app=mtats`. No organization (owner's account is assumed to have none; unverified). | Clean billing/IAM boundary from `petgo-play-ci` |
| Enabled APIs | — | `cloudresourcemanager`, `serviceusage`, `iam`, `iamcredentials`, `sts`, `storage`, `firebase`, `firebasehosting`, `billingbudgets` (`*.googleapis.com`) | Only what the bucket, Hosting, WIF, and the budget need |
| Firebase | project `mtats-release` added to Firebase (`firebase projects:addfirebase mtats-release`) | Hosting only; no Firestore, Auth, Analytics | Hosting is the only Firebase product used |
| Hosting site | default site `mtats-release` | Custom domains `mtats.app` (primary) and `www.mtats.app` (redirect to primary; see open item). Config in `site/firebase.json` (generated at release time from a template), `site/.firebaserc` pins `"default": "mtats-release"`. | Static page, appcasts, `latest.json`, redirects |
| Bucket | `mtats-releases` (global namespace; name availability unverified; fallback `mtats-release-dmgs`) | Location `us-central1` (single region, Standard class), uniform bucket-level access, public access prevention off, IAM `allUsers → roles/storage.objectViewer`, object versioning on, lifecycle: delete noncurrent versions after 90 days, soft-delete default. Objects: `releases/mtats-X.Y.Z.dmg` (+ `.sha256`), `appcast.xml`, `latest.json`, `beta/appcast.xml`, `beta/latest.json`. | Versioned, immutable DMGs with pay-per-use egress; the appcast/latest.json history gives rollback for the only objects that are overwritten |
| Service account | `github-release@mtats-release.iam.gserviceaccount.com` | Bucket-level binding only: `roles/storage.objectAdmin` on `mtats-releases`. Project-level: `roles/firebasehosting.admin` (Hosting has no per-site IAM) and `roles/serviceusage.serviceUsageConsumer` (the Firebase CLI checks enabled APIs; drop it if the Phase 5 dry-run deploy succeeds without it). Nothing else. | Least privilege: can write release objects and deploy this Hosting site, cannot create resources or read billing |
| WIF pool / provider | pool `github`, provider `github-oidc` | Issuer `https://token.actions.githubusercontent.com`. Attribute mapping: `google.subject=assertion.sub`, `attribute.repository=assertion.repository`, `attribute.ref=assertion.ref`. Attribute condition: `assertion.repository == "marvinmarnold/mtats" && assertion.ref.startsWith("refs/tags/v")` (see open item for adding `refs/heads/main` for `site.yml`). Binding: `roles/iam.workloadIdentityUser` on the service account for `principalSet://iam.googleapis.com/projects/<number>/locations/global/workloadIdentityPools/github/attribute.repository/marvinmarnold/mtats`. | GitHub Actions obtains short-lived tokens; no key file exists anywhere |
| Budget | `mtats-monthly` | $10/month, thresholds 50%, 90%, 100% of actual spend, email to the billing account's admins (the owner). | Backstop against a runaway egress bill or a misdirected deploy |
| DNS (at the registrar, manual) | `mtats.app` | Records as shown by the Firebase console when the custom domain is added: a TXT record for ownership verification and the A records Firebase lists (the IPs are whatever the console shows; not recorded here because they are assigned at setup). `www` CNAME/A per the console if the redirect domain is used. | Firebase provisions the TLS certificate only after verification; since `.app` has no HTTP fallback the site is unreachable until then (up to 24 h per Firebase's documentation). |

**Billing-isolation safety rule.** Every `gcloud`, `gsutil`, and `firebase` command in scripts, docs, and the owner's terminal passes `--project mtats-release` explicitly. Nobody runs `gcloud config set project`, `gcloud config configurations activate`, or `firebase use` — those change the default that currently points at `petgo-play-ci`. For interactive work the owner creates a named configuration once (`gcloud config configurations create mtats --no-activate`, then `gcloud config set project mtats-release --configuration mtats`) and selects it per command with `CLOUDSDK_ACTIVE_CONFIG_NAME=mtats`, which never alters the active default. Scripts that automate setup (`Scripts/gcp-bootstrap.sh`, if written) begin by asserting `gcloud config get-value project` is still what it was when they started and abort if not. The budget alert is the backstop, not the control.

Cost expectation at v1 traffic (unverified; for sizing only): Hosting $0, bucket storage cents, bucket egress ≈ $0.12/GB (≈ 60–100 downloads per dollar at 10–15 MB each). The $10 budget allows roughly 80 GB/month of downloads before the 100% alert.

## Website

Astro project in `site/` (same repo, `package-lock.json` committed, `npm ci` in CI). Output `site/dist`, deployed by `release.yml` and `site.yml`. Data: `site/src/data/latest.json` (gitignored, copied in by the workflow from the bucket; the build fails if it is missing unless `MTATS_SITE_BOOTSTRAP=1`, which renders the page without a download button for the pre-first-release deploy). Zero client-side JavaScript is the default; the design pass may add a small amount for the menu-bar mock-up animation.

Single page, in order:

1. Hero: product name, tagline "Mac stats you wear on your sleeve" (the design pass may tune the wording; the sleeve metaphor stays), one sentence stating what it is (menu-bar CPU/RAM/GPU/network monitor, Apple Silicon, macOS 14+).
2. Menu-bar mock-up: a rendering of the four built-in widgets as they appear in the menu bar. Source asset is produced in the design pass (screenshot or SVG recreation).
3. Download button: `href="/download"`, label `Download mtats <version>`, with `<size in MB> · macOS 14 or later · <publishedAt as date>` beneath, all from `latest.json`. A secondary link to the GitHub Release of the same version.
4. Three-step install: open the DMG; drag mtats to Applications; open it from Applications (first launch shows the standard macOS prompt for a downloaded app; mtats is notarized, so there is no override needed). A fourth line notes it lives in the menu bar and has no Dock icon, and that updates arrive through the app itself.
5. Screenshots: the dropdown detail of each widget and the Settings window. Produced in the design pass.
6. Privacy note: no telemetry, no crash reporting, no accounts. The only outbound requests are the Sparkle update check (daily, can be turned off in Settings) and the optional public-IP lookup (on by default, toggle in Settings; the services used are named in the app's Network dropdown). Plugins run with the app's privileges; third-party plugins are warned about on first load.
7. Footer: link to `https://github.com/marvinmarnold/mtats` (source, MIT), link to Releases, the version currently offered.

Constraints for the design pass: light and dark themes; renders without JavaScript; the download button and version line are the only data-bound elements; no external fonts or scripts from third-party CDNs (nothing to cookie-consent for); page weight under 1 MB including the mock-up. Headers set in `firebase.json`: `appcast.xml` and `beta/appcast.xml` with `Content-Type: application/xml; charset=utf-8` and `Cache-Control: public, max-age=300`; `latest.json` same cache policy; everything else Hosting defaults. Redirects: `/download` → `302` to the stable DMG's `/releases/` URL; `/releases/:file*` → `302` to `https://storage.googleapis.com/mtats-releases/releases/:file*` (Firebase Hosting supports absolute destinations and segment captures per its documentation; unverified here). `www.mtats.app` → `301` to `https://mtats.app` if the redirect domain is set up.

## Security & threat notes

**Supply chain.** `Package.swift` has no external dependencies. Sparkle is fetched from its GitHub release at a pinned version and verified against a SHA-256 recorded in the repo; a mismatch fails the build. GitHub Actions are pinned to commit SHAs. The site's npm dependencies run only in job 2 on a Linux runner that has no signing material; job 1 runs no package manager. In job 2 and in `site.yml`, `npm ci` and `npm run build` run before GCP authentication and checkouts use `persist-credentials: false`, so install scripts and build code never hold publishing credentials or the `GITHUB_TOKEN`; only the pinned `firebase-tools` runs with credentials, for `firebase deploy`. The notarization step means Apple scans every shipped binary.

**Who can trigger a release.** Only a push of a `v*` tag. A GitHub tag ruleset on `v*` restricts creation and deletion to the repository owner (currently the only collaborator; unverified). The `release` environment requires the owner's approval before job 1 reads any secret, so a tag pushed by mistake can be cancelled at the approval step. `workflow_dispatch` is deliberately not offered on `release.yml`; `site.yml` offers it (from `main` only, which the WIF condition already admits) so Hosting can be re-synced from the bucket during recovery. Pull requests from forks never receive secrets (GitHub default). Branch protection on `main` requires a PR, which is also what makes the "tagged commit is an ancestor of main" guard meaningful.

**Update-feed hijack.** To push a malicious update an attacker needs both a valid TLS response for `mtats.app` (Firebase account or DNS control; plain HTTP is impossible because `.app` is HSTS-preloaded) and the EdDSA private key (Sparkle rejects any enclosure whose signature does not verify against the baked public key), and additionally the update must pass Sparkle's code-signing continuity check against the installed app's Developer ID. Compromise of the Firebase/Google account alone can serve a malicious DMG to new visitors via `/download`, which Gatekeeper would flag unless the attacker also holds a Developer ID; mitigations are 2FA on the Google and GitHub accounts and the SHA-256 published on the GitHub Release page so a user can verify a download independently.

**Key compromise response.**
- Developer ID certificate: revoke it at developer.apple.com (this prevents new signatures; stapled, already-notarized builds keep working), create a new certificate, replace the two `APPLE_DEVELOPER_ID_*` secrets, release. Sparkle's continuity check accepts a new certificate from the same Team ID.
- Notary API key: revoke in App Store Connect, create a new one, replace the three `APPLE_NOTARY_*` values. Nothing shipped is affected.
- EdDSA private key: immediately replace the appcast in the bucket and Hosting with a copy whose items are known-good (object versioning provides the previous versions), generate a new pair, ship an update signed with the old key whose `Info.plist` carries the new `SUPublicEDKey` (§"Auto-update"), then rotate the secret. Users who update before the attacker publishes are migrated; the feed domain being under owner control is what makes this race winnable.
- GCP service account via WIF: there is no key to leak; revoke by deleting the WIF binding. Replace the GitHub secrets if the GitHub account itself is compromised.
- Any of the above: file a note in `docs/security/` with the timeline (that directory does not exist yet; created on first use).

**Plugin trust.** Unchanged from ADR-0001: a valid signature is required, a one-time prompt names the signer, and the Host's hardened runtime otherwise protects nothing against a plugin the user chose to load. The release pipeline does not add notarization checks for third-party plugins.

## Testing & verification

Local, after each phase:

- Phase 1: `Scripts/package-app.sh -c release && Scripts/smoke-test.sh` passes; `otool -L .build/mtats.app/Contents/MacOS/mtats` lists `@rpath/libMTatsPluginKit.dylib`; `otool -l` shows exactly one `LC_RPATH` of `@executable_path/../Frameworks`; `/usr/libexec/PlistBuddy -c Print .build/mtats.app/Contents/Info.plist` shows the derived version and build; RSS from the smoke test is re-measured for the release build (the smoke test's 80 MB line and its "debug builds measure ~52 MB" comment are updated with the release figure).
- Phase 2: `Scripts/sign-app.sh` with the real identity, then `codesign --verify --deep --strict --verbose=2`, `codesign -d --entitlements - ` showing only `disable-library-validation`, `Scripts/notarize.sh`, `xcrun stapler validate`, and `spctl -a -vv .build/mtats.app` printing `accepted` and `source=Notarized Developer ID`. Then the same on the DMG with `spctl -a -vv -t open --context context:primary-signature`. Then spike (c).
- Phase 3: a debug package shows no update controls and makes no network request to `mtats.app` (confirm with the Network widget's own counters or `nettop`); a release package shows the controls; "Check for Updates…" against a temporary development feed served from a local `python3 -m http.server` (never a released build) reports "up to date" or offers the test item.
- Phase 4: push `v0.1.0-rc.1`. The workflow must complete end to end and publish only to the `beta` channel and a GitHub pre-release. Download the DMG from `https://mtats.app/releases/mtats-0.1.0-rc.1.dmg`, verify the `.sha256`, and repeat the Phase 2 checks on the downloaded file on a Mac that has never seen the signing identity.

Real update test in the owner's macOS VM, before tagging `v0.1.0`:

1. In the VM, install `mtats-0.1.0-rc.1.dmg`, launch, accept the first-launch prompt, confirm the four widgets. `defaults write com.mtats.app updateChannel beta`.
2. Push `v0.1.0-rc.2` (any commit after rc.1 so the build number increases; a release-notes file is required).
3. In the VM, Settings → "Check for Updates…". Expected: Sparkle offers 0.1.0-rc.2 with the release notes, downloads via the `/releases/` redirect, verifies, installs, relaunches; Settings shows the new version and build. Also confirm the automatic check fires without the button after `SUScheduledCheckInterval` by temporarily setting `defaults write com.mtats.app SUScheduledCheckInterval 60` (Sparkle honors the user default for the interval).
4. `defaults delete com.mtats.app updateChannel`; tag `v0.1.0`; confirm `https://mtats.app/download` serves `mtats-0.1.0.dmg`, the page shows 0.1.0 with the correct size and date, and `https://mtats.app/appcast.xml` contains exactly one item.
5. After `v0.1.1` exists one day, repeat step 3 on the stable channel; that is the first real-user-path update and is the acceptance test for this whole design.

Every release: `Scripts/release-preflight.sh` is run locally before pushing a tag. It checks: on `main` and up to date with `origin/main`; working tree clean; `Releases/<version>.md` exists and is non-empty; the tag does not exist; the update guard (`Scripts/appcast-guard.sh`) passes for the channel derived from the version with the current commit count, so a build number that CI would reject never burns an immutable tag; `swift test` passes; `Scripts/package-app.sh -c release && Scripts/smoke-test.sh` passes (this is also the fallback for spike (a)); prints the tag command to run.

### Runbook: publish failed halfway

Symptom: job 2 (`publish`) failed after some objects reached the bucket (the rc.2 shape), or after the Hosting deploy but before the GitHub Release.

1. Transient failure (GCS 5xx, network, Firebase timeout, missed approval): use **Re-run failed jobs** on the tag's run. Job 2 resumes: an identical DMG is skipped; the remaining uploads, the deploy and the GitHub Release are idempotent. If the cause is a bug in the workflow itself, a re-run cannot help (it runs the tagged commit's workflow); fix it on `main` and cut the next version, after rolling the channel back (step 4) if the half-published state is wrong.
2. If `publish.sh` stops with "already exists with different bytes", do not delete anything; confirm byte identity by hand: `curl -fsSL https://storage.googleapis.com/mtats-releases/releases/mtats-X.Y.Z.dmg | shasum -a 256` and compare with `mtats-X.Y.Z.dmg.sha256` in the run's `release` artifact (`gh run download <run-id> -n release`). Identical → a stale read; re-run. Different → the name is burned; cut the next version.
3. If "could not determine whether … exists": a transient or permission error; re-run once it clears.
4. Rollback (a bad release must be pulled, or a half-published channel must be reverted): list generations with `gcloud storage ls -a gs://mtats-releases/appcast.xml` (or `beta/appcast.xml`, `latest.json`), restore the previous one with `gcloud storage cp gs://mtats-releases/appcast.xml#<generation> gs://mtats-releases/appcast.xml` (same for `latest.json`), then run `site.yml` from `main` via **Actions → site → Run workflow** (`gh workflow run site.yml --ref main`) so Hosting serves the restored objects. Verify with `curl -s https://mtats.app/appcast.xml` and `curl -sI https://mtats.app/download`. Object versioning keeps noncurrent generations for 90 days.

## Risks

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Release-configuration intermediates path differs from the debug glob (known; see Task 10 addendum) | Certain / blocks Phase 1 | Spike (b); fallback direct `swiftc` compile of the Host. |
| Both configurations' objects match one glob and the link fails with duplicate symbols, or silently links debug objects into the release app | Likely once both have been built / wrong binary shipped | Glob pinned to the configuration; script fails on objects from more than one build directory; `otool`/`nm` checks in Phase 1. |
| GitHub macOS runner cannot create status items | Unknown / changes the CI gate | Spike (a) and its fallback. |
| Sparkle XCFramework nested-code signing done in the wrong order or missing an XPC service → notarization rejects or Sparkle's installer fails at runtime | Moderate / blocks Phase 2–3 | Enumerate nested code programmatically in `sign-app.sh`; `codesign --verify --deep --strict`; the rc update test exercises the installer for real. |
| `notarytool` outage or slow queue | Occasional / delays a release | `--wait --timeout 30m`; re-run the workflow; nothing is published before notarization succeeds. |
| `mtats-release` project ID or `mtats-releases` bucket name already taken | Possible / naming only | Fallbacks `mtats-release-<4 digits>` and `mtats-release-dmgs`; the names are referenced from one place each (`site/.firebaserc`, `Scripts/release-env.sh`). |
| Custom-domain TLS not provisioned when `v0.1.0` is tagged | Possible / baked feed URL points at a dead host until it is | Phase 5 finishes (domain verified, `https://mtats.app/appcast.xml` returns the empty placeholder feed) before Phase 6 starts; `release-preflight.sh` curls the feed URL. |
| Owner's laptop is the only holder of the Developer ID private key if the `.p12` export is skipped | Possible / cert must be recreated (not catastrophic: same Team ID) | Export and store the `.p12` and password in the password manager as part of the certificate creation steps. |
| Commit-count build number regresses after a history rewrite on `main` | Low / Sparkle stops offering updates | Guard against the published appcast fails the release; `main` is protected against force-push. |
| Hosting free-tier egress exhausted if DMGs are ever served through Hosting by mistake | Low / site goes down for the day | DMGs are never in `site/dist`; a size check in the site build fails if any file over 2 MB is present. |
| Firebase redirect capture syntax does not behave as expected for `/releases/:file*` | Low / downloads 404 | Verified by the rc dry run; fallback is a redirect per release written by the workflow (the file list is finite). |

## Open items for the owner

| Item | Recommended default / steps |
|---|---|
| Registrar for `mtats.app` (unknown) | Identify it; confirm you can add TXT and A records at the apex. If the registrar cannot host apex A records, move DNS to Cloud DNS in `mtats-release` (adds ≈ $0.20/month). |
| Create and export the Developer ID Application certificate | On this Mac: Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority (save to disk, no CA email). developer.apple.com → Certificates → `+` → Developer ID Application (G2 sub-CA) → upload the CSR → download the `.cer` → double-click to install. Keychain Access → My Certificates → right-click the certificate (with its private key) → Export → `.p12` with a strong password. Store the `.p12` and password in the password manager. `base64 -i mtats-devid.p12 \| pbcopy` → GitHub secret. Delete the `.p12` and CSR files. Then `security find-identity -v -p codesigning` must list one `Developer ID Application` identity. |
| Create the App Store Connect API key for notarization | App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → Generate (name `mtats-notary`, access Developer). Record Key ID and Issuer ID; download the `.p8` once; store in the password manager; paste contents into `APPLE_NOTARY_KEY_P8`. |
| Generate the Sparkle EdDSA key pair | After Phase 3 fetches Sparkle: `.build/sparkle/bin/generate_keys` (prints the public key for the plist), `generate_keys -x sparkle-private.txt` → secret and password manager → delete the file. |
| GitHub: secrets, variables, environment, rulesets | Create environment `release` (deployment tags `v*`, required reviewer: owner); add the secrets/variables from the table; add a tag ruleset for `v*` (restrict create/delete to owner); confirm branch protection on `main`. |
| Confirm the project ID `mtats-release` and bucket name `mtats-releases` | Accept the defaults; the fallbacks are in §"Risks". |
| Confirm single-region `us-central1` for the bucket | Accept; if most users are expected outside North America, `europe-west1` is the alternative; the cost difference is negligible. |
| WIF condition: tags only, or tags plus `refs/heads/main`? | Recommended: add `refs/heads/main` so `site.yml` can deploy copy changes without a release. The service account's permissions are identical either way, so the only added exposure is that a `main` push can redeploy the site, which `main`'s branch protection already governs. |
| `www.mtats.app` | Recommended: add it in Firebase as a redirect to `mtats.app` and publish the records; costs nothing. |
| App icon | Required before `v0.1.0`: Sparkle's update window, the DMG, and Finder show it. Produce in the visual design pass as `Resources/AppIcon.icns`; `package-app.sh` copies it and the template gains `CFBundleIconFile`. |
| Copyright holder name for `NSHumanReadableCopyright` and the site footer | The owner's name or a project name; set once in `Scripts/Host-Info.plist.template`. |
| Local Swift/Xcode version | Recorded 2026-10-12: Xcode 27.1 (27A9275), Swift 6.4. The CI image must provide a compatible Xcode (spike (a)). |
| macOS VM for the update test | Confirm one exists on macOS 14 or 15 with a clean user account; the test in §"Testing" assumes it. |
| DNS records | Entered at the registrar after Firebase displays them in Phase 5; nothing to decide now beyond having registrar access. |

## Phases (mapped to the work order)

| Phase | Deliverables | Done when |
|---|---|---|
| 0 — Merge PR #1 | Owner's manual visual check of the menu bar; merge to `main`; branch protection on `main`. | On `main`: `swift test`, `Scripts/package-app.sh`, and `Scripts/smoke-test.sh` pass. (`Scripts/verify.sh` is not used here: it calls the paid external GLM review.) |
| Spikes | (a), (b), (c) as throwaway branches; findings recorded as addenda in this document's "Spikes" table (one paragraph each, like ADR-0005's addenda). | Each has a recorded outcome and the chosen path. |
| 1 — Release build, versioning, bundle layout | `package-app.sh -c release`; configuration-pinned object glob (or direct compile); `Scripts/Host-Info.plist.template` with derived version/build; `Contents/Frameworks` layout and rpath; `build-plugin.sh` configuration support and no dev rpath in release; explicit inside-out ad-hoc signing in `sign-app.sh`; smoke-test RSS line re-measured; `ci.yml`. | Phase 1 checks in §"Testing" pass locally and `ci.yml` is green. |
| 2 — Local signing and notarization | Developer ID certificate created and exported (owner); `Scripts/mtats.entitlements`; `sign-app.sh` with a real identity; `Scripts/notarize.sh`; `Scripts/make-dmg.sh`; spike (c) answered. | `spctl -a -vv` accepts both app and DMG on a second Mac; third-party plugin loading result recorded. |
| 3 — Sparkle | `Scripts/fetch-sparkle.sh` with pinned version and checksum; Sparkle in `Frameworks/`; Host integration (`main.swift`, `StatusBarController`, `SettingsView`); channel delegate; EdDSA keys generated; smoke test unaffected. | Phase 3 checks pass; a release package shows and exercises the update controls against a local test feed. |
| 4 — CI workflow | `release.yml` (two jobs, environment `release`, SHA-pinned actions, keychain cleanup), `site.yml`, `Scripts/release-preflight.sh`, `Releases/0.1.0.md`; GitHub secrets, variables, environment, tag ruleset (owner). Steps 12–18 are stubbed until Phase 5 provides the project. | A `v0.1.0-rc.*` tag runs job 1 to completion (signed, notarized, stapled DMG artifact) with job 2 skipped or pointed at a dry-run flag. |
| 5 — GCP and site | Project, APIs, bucket, service account, WIF, budget, Firebase Hosting, custom domain (owner adds DNS); `site/` Astro project with the page content of §"Website" (design pass is its own task in the plan); `firebase.json` template; empty placeholder `appcast.xml` and `beta/appcast.xml` deployed so the feed URL resolves before any build bakes it. | `https://mtats.app/` serves the bootstrap page over TLS; `https://mtats.app/appcast.xml` returns a valid empty feed; a `site.yml` deploy from `main` succeeds via WIF. |
| 6 — Tag v0.1.0 | `v0.1.0-rc.1` and `-rc.2` through the full workflow; VM update test; `v0.1.0`. | `https://mtats.app/download` serves the notarized 0.1.0 DMG, the page shows 0.1.0, the appcast has one stable item, the GitHub Release exists, and a fresh Mac installs it with no Gatekeeper override. |
