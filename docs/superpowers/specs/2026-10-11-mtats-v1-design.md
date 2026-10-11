# mtats v1 — Design Spec

Status: approved by product owner (conversational design review, 2026-10-11)

## 1. What this is

`mtats` is a native macOS menu bar system-monitor utility — an iStat Menus-style clone. v1 shows live CPU, RAM, GPU, and Network usage (plus local/public IP) directly in the menu bar, with a dropdown for detail. It is open source (MIT, open-core) and intended to also be sold as a signed/notarized binary. See `CONTEXT.md` for terminology (Host, Plugin, Widget, Snapshot, Built-in/Third-party plugin) used throughout this document.

## 2. Goals / Non-goals

**Goals (v1):**
- CPU, RAM, GPU, Network Widgets, each with a live menu-bar sparkline/number and a dropdown detail view.
- Local + public IP shown as part of the Network Widget's detail.
- A real dynamic plugin architecture (not just an in-process registry) that both built-in and future third-party Widgets load through identically.
- One working dogfood proof that a genuinely third-party-signed Plugin can load.
- Sellable quality: notarized, signed, acceptable performance overhead, no crashes on missing/unexpected sensor data.

**Explicit non-goals (v1):**
- Weather, News, fan temperature, or the "Agents" Widget — all deferred (see §9).
- Mac App Store distribution, Intel support, sandboxing.
- Any plugin marketplace, update mechanism, or notarization/allow-list checking of third-party plugins beyond "has a valid signature."
- Backward/forward compatibility across `MTatsPluginKit` versions.
- Per-widget custom refresh intervals, menu-bar icon reordering, theming.

## 3. Platform & distribution

Apple Silicon only, macOS 14/15+. Notarized direct-sale binary (own site, e.g. Gumroad/Paddle), **not** sandboxed, **not** on the Mac App Store. Rationale: ADR-0003.

## 4. Architecture

### 4.1 Components

- **`MTatsPluginKit`** (framework): defines the `Plugin` protocol (bundle entry point / principal class, exposes `static func makeWidgets() -> [Widget]`), the `Widget` protocol (id, displayName, `start()`/`stop()` lifecycle, a menu-bar `AnyView`, a dropdown detail `AnyView`), and the `pluginAPIVersion` integer constant. `Snapshot` types and the `MetricsSource` protocol that produces them are **not** part of this shared surface — they're internal to each concrete Widget's own implementation (see ADR-0005, CONTEXT.md). This split exists so a Widget's presentation logic is unit-testable with canned data, and so the Host can pause/resume a Widget via `stop()`/`start()` for per-widget enable/disable (§6) without destroying Plugin state. Both the Host and every Plugin link against this one framework, loaded as a single shared image per process — the Host loads it first at launch, and Plugins link against it weakly rather than embedding their own copy, so Swift runtime type identity for `Widget` stays consistent everywhere (ADR-0005).
- **`mtats.app`** (Host): owns the `NSStatusItem`(s), a plugin discovery/loader service, the polling scheduler, Settings UI, and (future) license-key handling. Renders whatever Widgets the loaded Plugins expose — the Host has no built-in knowledge of CPU/RAM/GPU/Network beyond what it discovers at runtime.
- **4 built-in Plugin targets**: `CPUWidget.bundle`, `RAMWidget.bundle`, `GPUWidget.bundle`, `NetworkWidget.bundle` — each its own Xcode target, embedded + code-signed into `mtats.app` via a Copy Files build phase, depending only on `MTatsPluginKit` + system frameworks (IOKit, Darwin/Mach, Network/URLSession).
- **Example third-party plugin**: a separate repo (`mtats-example-plugin`), built and signed independently, implementing a trivial "hello world" Widget — exists only to prove the loading path, no real functionality.

### 4.2 Plugin discovery & loading

The Host scans two locations at launch and on change:
1. Built-in: a plugins directory inside `mtats.app`'s own Resources.
2. Third-party: `~/Library/Application Support/mtats/Plugins/`, watched via FSEvents for hot-load without relaunch.

For each `.bundle` found: verify a valid code signature via `SecStaticCodeCheckValidity` (reject unsigned outright — no load, no warning dialog, just a skip with a visible reason in a diagnostics view); check `pluginAPIVersion` in the bundle's `Info.plist` for an exact match against the Host's (skip + visible reason on mismatch, ADR-0004); if from the third-party directory, show a one-time warning naming the signing identity before first load. Then `Bundle(path:).load()` and instantiate the `principalClass`.

Loading signed-but-not-same-Team-ID code requires `com.apple.security.cs.disable-library-validation` in the Host's hardened-runtime entitlements (ADR-0001). This is a real trust boundary: a valid signature proves provenance, not safety.

### 4.3 Data flow

The Host never touches a Snapshot or knows a Widget's data type — it only calls `start()`/`stop()` and renders the two views `Widget` returns. Inside each concrete Widget, a `MetricsSource` produces immutable Snapshots on its own cadence; the menu-bar view and the dropdown detail view both observe the same Snapshot stream (via an internal `ObservableObject`), so nobody polls hardware twice and nobody polls hardware from a view.

## 5. v1 Widgets — data sources

| Widget | API | Notes |
|---|---|---|
| CPU | `host_processor_info`/`host_statistics` (Mach) | Per-core + aggregate; no entitlements |
| RAM | `host_statistics64` (VM stats) | wired/active/inactive/compressed, matches Activity Monitor |
| GPU | IOKit `IOAccelerator` performance-statistics dict (`"Device Utilization %"`) | Apple Silicon approach used by the open-source "Stats" app; must degrade to "N/A" rather than crash if keys are missing/change across macOS versions |
| Network | `getifaddrs`/`if_data` byte counters, delta over poll interval | Aggregate throughput in menu bar (1s cadence); per-interface (Wi-Fi/Ethernet) breakdown in dropdown |
| Local IP | `getifaddrs` | Part of Network Widget's dropdown detail |
| Public IP | `URLSession` call to an IP-echo service, with a fallback service and graceful "unavailable" on failure | Polls every 5 min + manual refresh button in dropdown; user-toggleable (external call, privacy-relevant) |

Refresh cadence: 1s for CPU/RAM/GPU/Network sparklines. Performance budget (acceptance criterion, checked during build verification, not just asserted): under ~1% average CPU, ~40-50MB RSS with all 4 built-ins loaded.

## 6. Settings (v1 scope)

- Enable/disable each Widget individually.
- One global refresh interval (no per-widget override in v1).
- Launch-at-login toggle.
- Public-IP lookup toggle.

## 7. Licensing

Open-core (ADR-0002): Host, `MTatsPluginKit`, and the 4 built-in Widgets are MIT, public on GitHub as `mtats` starting now. Revenue: a sold, signed/notarized pre-built binary, plus future paid Plugins/features gated by a license key (not built in v1).

## 8. Build & evaluation process

1. **Design** (this doc) — done.
2. Feasibility spike (`mattpocock-skills:prototype`): validate end-to-end that (a) a `.bundle` signed with a *different* identity than the Host can be loaded with library validation disabled, and (b) a `Widget` instance produced by that separately-built bundle passes `as?` / protocol-conformance checks correctly in the Host process — i.e. that weak-linking `MTatsPluginKit` from the Plugin side actually resolves to the Host's single loaded copy rather than a duplicate image (ADR-0005). (b) is the real risk; (a) alone would pass even if type identity were broken.
3. **Plan** (`writing-plans`), including a `mattpocock-skills:codebase-design` pressure-test specifically of the `Widget`/`Plugin` protocol split in §4.1 — the one seam every future Widget depends on.
4. **Execution**: Claude Code implements against the plan, in an isolated workspace.
5. **Verification loop**, repeated until all three hold, no round cap:
   - `xcodebuild` compiles cleanly.
   - Functional smoke test: all 4 built-in Plugins actually load and produce Snapshots at runtime, and the performance budget (§5) holds.
   - GLM review (`dsh --profile headless`, model `glm-5.3`) against this spec's acceptance criteria returns zero unresolved high-severity findings.
6. Human (product owner) does a final manual visual check of the menu-bar rendering — the one thing neither Claude Code nor GLM can see.

## 9. Future Plugins (not built in v1)

- **Agents**: shows running AI coding agents. Sketch captured for later: hybrid detection (process-list scan as baseline, enriched with session-file reads for tools with known formats — starting with Claude Code and `dsh`/GLM), grouped primarily by tool/provider (e.g. "2 Claude Code, 1 dsh"), with project/working directory as secondary per-agent detail when available. Local machine only. Not scoped further than this until actually built.
- Weather, News, fan temperature (SMC-based, same approach as smcFanControl/TG Pro/Stats) — mentioned only as proof that the plugin architecture doesn't preclude them; no design work done yet.

## 10. Testing strategy

- Unit tests for pure calculation logic (byte-delta → throughput, VM stat parsing) via dependency-injected raw data — these don't need real hardware.
- Integration/smoke tests for actual sensor reads and plugin loading run on real Apple Silicon hardware (not easily mockable: IOKit, Mach APIs, dynamic bundle loading). CI (GitHub Actions macOS arm64 runner) can verify compilation on every push; sensor-correctness and plugin-loading verification happen in the verification loop (§8), not CI, for v1.

## References

- `CONTEXT.md` — glossary
- `docs/adr/0001-dynamic-plugin-loading-for-all-widgets.md`
- `docs/adr/0002-open-core-licensing.md`
- `docs/adr/0003-apple-silicon-only-unsandboxed-distribution.md`
- `docs/adr/0004-plugin-api-exact-version-match.md`
- `docs/adr/0005-widget-protocol-split-and-shared-framework-identity.md`
