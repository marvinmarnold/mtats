# mtats v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build mtats v1 — a native macOS menu bar system monitor with CPU/RAM/GPU/Network (+local/public IP) widgets, loaded through a real dynamic plugin architecture, to a sellable quality bar.

**Architecture:** A Swift Package (`Package.swift`) at the repo root. `MTatsPluginKit` is a **dynamic** library target defining the `Widget`/`PluginEntry` protocol (crosses the Plugin↔Host seam, no associated types — ADR-0005). Each metric gets its own **static**, fully unit-testable `*Core` library target (pure calculation logic + a thin real-sensor wrapper + SwiftUI views). A manual packaging script compiles each Core into an actual loadable `.bundle` (NSPrincipalClass-based, exactly the mechanism validated in `spikes/plugin-loading-identity/`), and assembles the final `mtats.app`. No Xcode.app is required for any of this — `swift build`/`swift test` plus the packaging scripts cover the whole v1 build. Xcode/a paid Developer ID is only needed later, for notarized distribution (out of scope for this plan).

**Tech Stack:** Swift 6, SwiftPM, AppKit (`NSStatusItem`) + SwiftUI (views), Foundation/Darwin (Mach APIs), IOKit, `Network`/`URLSession`.

**Spec:** `docs/superpowers/specs/2026-10-11-mtats-v1-design.md` (read alongside this plan — it has the full rationale; this plan has the exact file paths and code). Also read `CONTEXT.md` and `docs/adr/0001` through `0005`.

## Global Constraints

- Apple Silicon only, macOS 14+ (Package.swift: `platforms: [.macOS(.v14)]`).
- Refresh cadence: 1s for CPU/RAM/GPU/Network menu-bar sparklines; public IP every 5 min + manual refresh.
- Performance budget: under ~1% average CPU, ~40-50MB RSS with all 4 built-ins loaded — checked in Task 10's smoke test, not just asserted.
- `MTatsPluginKit` must build as `type: .dynamic` and nothing else may claim its install name — this is load-bearing per ADR-0005.
- No Xcode.app or paid Developer ID required for Tasks 1-11. If one of those seems to need one, stop and re-read ADR-0005/the spike — it almost certainly doesn't. (Task 12, notarization, is the sole exception — see that task.)
- MIT license: add a one-line `// SPDX-License-Identifier: MIT` at the top of every new source file.
- A Plugin's `PluginEntry`-conforming class MUST subclass `NSObject` and carry an explicit `@objc(ExactName)` matching its Info.plist `NSPrincipalClass` string (how `Bundle.principalClass` finds it — ADR-0001/0005). This does NOT require the `Widget`/`PluginEntry` protocols themselves to be `@objc`.

## Review Focus

- **GPU widget on an unexpected macOS/hardware combination**: `IOAccelerator` performance-statistics keys are undocumented and can be missing or renamed. The widget must render "N/A" and keep polling, never crash or hang the Host.
- **Network interfaces appearing/disappearing mid-session** (Wi-Fi toggled off, laptop sleep/wake, VPN interface added): byte counters can reset or an interface can vanish between polls. The delta calculation must treat a counter decrease as "interface reset, skip this sample" rather than emit a negative/garbage throughput number.
- **Public IP lookup with no network / blocked by a firewall**: must show "unavailable" and keep the 5-minute retry cadence, never block the menu bar UI or spin.
- **The third-party plugins directory doesn't exist yet at first launch** (`~/Library/Application Support/mtats/Plugins/` — fresh install, nothing has ever written there): the Host must create it and start an FSEvents watch without erroring, not just skip watching silently.
- **Disabling a widget in Settings while its `MetricsSource` has an in-flight read** (e.g. a slow `URLSession` call for public IP): `stop()` must not crash or leak if called while a read is pending; the in-flight result must be dropped, not delivered to a torn-down view.

---

## File structure

```
mtats/
  Package.swift
  Sources/
    MTatsPluginKit/
      Widget.swift              # Widget, PluginEntry protocols, pluginAPIVersion
    CPUCore/
      CPUSnapshot.swift         # pure value type
      CPUCalculator.swift       # pure calc: ticks -> percentages
      CPUMetricsSource.swift    # real host_processor_info wrapper
      CPUWidgetView.swift       # SwiftUI menu-bar + detail views, ObservableObject
    RAMCore/  (same shape, host_statistics64)
    NetworkCore/  (same shape, getifaddrs + local/public IP + URLSession)
    GPUCore/  (same shape, IOAccelerator)
    mtats/
      main.swift
      StatusBarController.swift
      PluginLoader.swift
      SettingsStore.swift
      SettingsView.swift
  Plugins/
    CPUWidget/PluginMain.swift, Info.plist
    RAMWidget/PluginMain.swift, Info.plist
    GPUWidget/PluginMain.swift, Info.plist
    NetworkWidget/PluginMain.swift, Info.plist
  Scripts/
    build-plugin.sh             # swiftc -emit-library incantation from the spike, parameterized
    package-app.sh              # assembles mtats.app, embeds+signs built-in plugins
    verify.sh                   # build + smoke test + dsh GLM review loop
  Tests/
    CPUCoreTests/, RAMCoreTests/, NetworkCoreTests/, GPUCoreTests/
```

---

### Task 1: MTatsPluginKit protocols + the AnyView/non-@objc-protocol loading question

**Files:**
- Create: `Package.swift`
- Create: `Sources/MTatsPluginKit/Widget.swift`
- Create: `spikes/anyview-principal-class/` (throwaway — see step 5; delete after this task, do not commit it to the real source tree)

**Interfaces:**
- Produces: `public protocol Widget: AnyObject { var id: String; var displayName: String; func start(interval: TimeInterval); func stop(); func menuBarView() -> AnyView; func detailView() -> AnyView }`, `public protocol PluginEntry: AnyObject { static func makeWidgets() -> [Widget] }`, `public protocol PublicIPToggleable: AnyObject { func setPublicIPLookupEnabled(_ enabled: Bool) }`, `public let pluginAPIVersion: Int = 1`.

- [ ] **Step 1: Create the package manifest**

```swift
// swift-tools-version:5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "mtats",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MTatsPluginKit", type: .dynamic, targets: ["MTatsPluginKit"]),
        .library(name: "CPUCore", targets: ["CPUCore"]),
        .library(name: "RAMCore", targets: ["RAMCore"]),
        .library(name: "NetworkCore", targets: ["NetworkCore"]),
        .library(name: "GPUCore", targets: ["GPUCore"]),
        .executable(name: "mtats", targets: ["mtats"]),
    ],
    targets: [
        .target(name: "MTatsPluginKit"),
        .target(name: "CPUCore", dependencies: ["MTatsPluginKit"]),
        .testTarget(name: "CPUCoreTests", dependencies: ["CPUCore"]),
        .target(name: "RAMCore", dependencies: ["MTatsPluginKit"]),
        .testTarget(name: "RAMCoreTests", dependencies: ["RAMCore"]),
        .target(name: "NetworkCore", dependencies: ["MTatsPluginKit"]),
        .testTarget(name: "NetworkCoreTests", dependencies: ["NetworkCore"]),
        .target(name: "GPUCore", dependencies: ["MTatsPluginKit"]),
        .testTarget(name: "GPUCoreTests", dependencies: ["GPUCore"]),
        .executableTarget(name: "mtats", dependencies: ["MTatsPluginKit"]),
    ]
)
```

- [ ] **Step 2: Run `swift build` to verify the empty package builds**

Run: `swift build`
Expected: builds successfully (targets have no source files yet except what you add in Step 3 — add an empty `Widget.swift` first if the build complains about a target with no sources).

- [ ] **Step 3: Write the protocols**

```swift
// Sources/MTatsPluginKit/Widget.swift
// SPDX-License-Identifier: MIT
import SwiftUI

/// Crosses the Plugin<->Host seam. No associated types (ADR-0005): a dynamically loaded
/// plugin and the Host must agree on this exact, non-generic shape.
public protocol Widget: AnyObject {
    var id: String { get }
    var displayName: String { get }

    /// Begin producing data at the given cadence (spec §6: one Host-wide setting, passed
    /// in rather than hardcoded, so Plugins never need to know about Host settings types).
    /// Safe to call again with a different interval even without calling stop() first —
    /// implementations must restart cleanly (see each *MetricsSource.start(), which always
    /// calls its own stop() internally before reconfiguring).
    func start(interval: TimeInterval)

    /// Stop producing data and release resources. Safe to call even if start() was never called.
    func stop()

    /// Live menu-bar presentation. Must update reactively as new data arrives.
    func menuBarView() -> AnyView

    /// Dropdown detail presentation.
    func detailView() -> AnyView
}

/// A Plugin's entry point. The concrete implementing class MUST subclass NSObject and be
/// named via `@objc(ExactName)` matching the plugin bundle's Info.plist NSPrincipalClass key —
/// that's how Bundle.principalClass finds it at runtime (ADR-0001, ADR-0005).
public protocol PluginEntry: AnyObject {
    static func makeWidgets() -> [Widget]
}

/// Every Plugin bundle must declare this exact integer in its Info.plist under
/// MTatsPluginAPIVersion. The Host rejects any mismatch (ADR-0004).
public let pluginAPIVersion: Int = 1

/// Optional, narrow extension a Widget can additionally conform to. Kept separate from
/// `Widget` itself so the one widget that needs it (Network, for the public-IP toggle —
/// spec §6) doesn't force every other widget to carry an irrelevant requirement.
public protocol PublicIPToggleable: AnyObject {
    func setPublicIPLookupEnabled(_ enabled: Bool)
}
```

- [ ] **Step 4: Run `swift build` again to verify it still builds**

Run: `swift build`
Expected: PASS.

- [ ] **Step 5: De-risk the one open question from ADR-0005 before building on top of it — can a plain (non-@objc) Swift protocol returning `AnyView`, implemented by an `NSObject` subclass, be discovered via `Bundle.principalClass` and cast successfully?**

This extends the validated spike (`spikes/plugin-loading-identity/` on branch `spike/plugin-loading-identity`), which only tested a `String`-returning `@objc` protocol. `Widget` returns `AnyView`, which cannot be `@objc`. Build a throwaway fixture to confirm this works before any real widget code depends on it:

```bash
mkdir -p spikes/anyview-principal-class/{host,plugin}
```

```swift
// spikes/anyview-principal-class/host/main.swift
import Foundation
import MTatsPluginKit

let pluginPath = CommandLine.arguments[1]
guard let bundle = Bundle(path: pluginPath), bundle.load() else {
    print("FAIL: bundle load"); exit(1)
}
guard let principal = bundle.principalClass as? PluginEntry.Type else {
    print("FAIL: principalClass does not conform to PluginEntry"); exit(1)
}
let widgets = principal.makeWidgets()
guard widgets.count == 1 else { print("FAIL: widget count"); exit(1) }
_ = widgets[0].menuBarView() // just needs to not crash / type-check
widgets[0].start(interval: 1.0)
widgets[0].stop()
print("PASS")
```

```swift
// spikes/anyview-principal-class/plugin/PluginMain.swift
import Foundation
import SwiftUI
import MTatsPluginKit

@objc(FixtureWidget) class FixtureWidget: NSObject, Widget {
    let id = "fixture"
    let displayName = "Fixture"
    func start(interval: TimeInterval) {}
    func stop() {}
    func menuBarView() -> AnyView { AnyView(Text("fixture")) }
    func detailView() -> AnyView { AnyView(Text("fixture detail")) }
}

@objc(FixturePluginMain) public class FixturePluginMain: NSObject, PluginEntry {
    @objc public static func makeWidgets() -> [Widget] { [FixtureWidget()] }
}
```

Build and run it (reusing the exact working directory structure/flags from `spikes/plugin-loading-identity/README.md`, substituting these new sources and linking against the real `swift build` output of `MTatsPluginKit` at `.build/debug/libMTatsPluginKit.dylib` / `.build/debug/MTatsPluginKit.swiftmodule`):

```bash
swift build
swiftc -emit-library -module-name FixturePlugin \
  -I .build/debug -L .build/debug -lMTatsPluginKit \
  spikes/anyview-principal-class/plugin/PluginMain.swift \
  -o spikes/anyview-principal-class/Fixture.bundle/Contents/MacOS/Fixture \
  -Xlinker -rpath -Xlinker /nonexistent/thirdparty/path
mkdir -p spikes/anyview-principal-class/Fixture.bundle/Contents
cat > spikes/anyview-principal-class/Fixture.bundle/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Fixture</string>
  <key>CFBundleIdentifier</key><string>com.mtats.spike.fixture</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>NSPrincipalClass</key><string>FixturePluginMain</string>
</dict></plist>
EOF
codesign -s - -f spikes/anyview-principal-class/Fixture.bundle
swiftc -I .build/debug -L .build/debug -lMTatsPluginKit \
  spikes/anyview-principal-class/host/main.swift \
  -o spikes/anyview-principal-class/host-bin \
  -Xlinker -rpath -Xlinker .build/debug
codesign -s - -f spikes/anyview-principal-class/host-bin
spikes/anyview-principal-class/host-bin "$PWD/spikes/anyview-principal-class/Fixture.bundle"
```

Expected: prints `PASS`.

**If it instead fails** (e.g. `NSClassFromString` can't find `FixturePluginMain`, or the metatype cast fails): make `PluginEntry` `@objc` after all (drop the `AnyView`-returning requirements out of the `@objc` protocol and keep only `static func makeWidgets() -> [AnyObject]`, with the Host doing `widget as? Widget` as a second, non-@objc cast on each returned instance — the spike already proved that second-stage cast works). Update this file and ADR-0005 with whichever variant actually passed before continuing to Task 2.

- [ ] **Step 6: Delete the throwaway fixture, keep only the result**

```bash
rm -rf spikes/anyview-principal-class
```

Record the verdict (which variant passed) as a one-line addendum to ADR-0005, the same way the plugin-loading-identity spike's result was recorded.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/MTatsPluginKit docs/adr/0005-widget-protocol-split-and-shared-framework-identity.md
git commit -m "Add MTatsPluginKit Widget/PluginEntry protocols, verified against principalClass loading"
```

---

### Task 2: CPUCore — pure calculation, real sensor wrapper, views

**Files:**
- Create: `Sources/CPUCore/CPUSnapshot.swift`
- Create: `Sources/CPUCore/CPUCalculator.swift`
- Create: `Sources/CPUCore/CPUMetricsSource.swift`
- Create: `Sources/CPUCore/CPUWidgetView.swift`
- Test: `Tests/CPUCoreTests/CPUCalculatorTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `public struct CPUSnapshot { public let perCoreUsage: [Double]; public let totalUsage: Double; public let timestamp: Date }`, `public struct CPUCalculator { public static func usage(previous: [host_cpu_load_info], current: [host_cpu_load_info]) -> CPUSnapshot }`, `public final class CPUMetricsSource: ObservableObject { @Published public private(set) var latest: CPUSnapshot?; public func start(interval: TimeInterval = 1.0); public func stop() }`.

- [ ] **Step 1: Write the failing test for the pure calculation**

`host_cpu_load_info` (from Darwin) exposes `cpu_ticks: (UInt32, UInt32, UInt32, UInt32)` for user/system/idle/nice. Usage % between two samples = `1 - (idleDelta / totalDelta)`.

```swift
// Tests/CPUCoreTests/CPUCalculatorTests.swift
import XCTest
@testable import CPUCore
import Darwin

final class CPUCalculatorTests: XCTestCase {
    private func load(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) -> host_cpu_load_info {
        var info = host_cpu_load_info()
        info.cpu_ticks.0 = user
        info.cpu_ticks.1 = system
        info.cpu_ticks.2 = idle
        info.cpu_ticks.3 = nice
        return info
    }

    func test_fullyIdleCore_reportsZeroUsage() {
        let previous = [load(user: 0, system: 0, idle: 1000, nice: 0)]
        let current = [load(user: 0, system: 0, idle: 2000, nice: 0)]
        let snapshot = CPUCalculator.usage(previous: previous, current: current)
        XCTAssertEqual(snapshot.perCoreUsage, [0.0], accuracy: 0.001)
        XCTAssertEqual(snapshot.totalUsage, 0.0, accuracy: 0.001)
    }

    func test_fullyBusyCore_reportsFullUsage() {
        let previous = [load(user: 1000, system: 0, idle: 0, nice: 0)]
        let current = [load(user: 2000, system: 0, idle: 0, nice: 0)]
        let snapshot = CPUCalculator.usage(previous: previous, current: current)
        XCTAssertEqual(snapshot.perCoreUsage, [1.0], accuracy: 0.001)
    }

    func test_twoCoresAtDifferentLoads_averagesForTotal() {
        let previous = [load(user: 0, system: 0, idle: 0, nice: 0), load(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [load(user: 1000, system: 0, idle: 0, nice: 0), load(user: 0, system: 0, idle: 1000, nice: 0)]
        let snapshot = CPUCalculator.usage(previous: previous, current: current)
        XCTAssertEqual(snapshot.perCoreUsage, [1.0, 0.0], accuracy: 0.001)
        XCTAssertEqual(snapshot.totalUsage, 0.5, accuracy: 0.001)
    }

    func test_counterWentBackwards_treatedAsZeroNotNegative() {
        // Review Focus analog for CPU: a tick counter must never produce negative usage.
        let previous = [load(user: 5000, system: 0, idle: 0, nice: 0)]
        let current = [load(user: 1000, system: 0, idle: 0, nice: 0)] // reset/overflow
        let snapshot = CPUCalculator.usage(previous: previous, current: current)
        XCTAssertEqual(snapshot.perCoreUsage, [0.0], accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CPUCoreTests`
Expected: FAIL with "cannot find 'CPUCalculator' in scope" (or similar — the type doesn't exist yet).

- [ ] **Step 3: Write the snapshot type and the calculator**

```swift
// Sources/CPUCore/CPUSnapshot.swift
// SPDX-License-Identifier: MIT
import Foundation

public struct CPUSnapshot: Equatable {
    public let perCoreUsage: [Double]
    public let totalUsage: Double
    public let timestamp: Date

    public init(perCoreUsage: [Double], totalUsage: Double, timestamp: Date = Date()) {
        self.perCoreUsage = perCoreUsage
        self.totalUsage = totalUsage
        self.timestamp = timestamp
    }
}
```

```swift
// Sources/CPUCore/CPUCalculator.swift
// SPDX-License-Identifier: MIT
import Darwin

public struct CPUCalculator {
    public static func usage(previous: [host_cpu_load_info], current: [host_cpu_load_info]) -> CPUSnapshot {
        let count = min(previous.count, current.count)
        var perCore: [Double] = []
        perCore.reserveCapacity(count)

        for i in 0..<count {
            let p = previous[i].cpu_ticks
            let c = current[i].cpu_ticks
            let userDelta = delta(c.0, p.0)
            let systemDelta = delta(c.1, p.1)
            let idleDelta = delta(c.2, p.2)
            let niceDelta = delta(c.3, p.3)
            let total = userDelta + systemDelta + idleDelta + niceDelta
            perCore.append(total == 0 ? 0.0 : Double(total - idleDelta) / Double(total))
        }

        let totalUsage = perCore.isEmpty ? 0.0 : perCore.reduce(0, +) / Double(perCore.count)
        return CPUSnapshot(perCoreUsage: perCore, totalUsage: totalUsage)
    }

    /// Counters only ever increase in a healthy sample pair. A decrease means the counter
    /// reset (CPU went offline/online, overflow) — treat that tick's contribution as zero
    /// rather than letting it go negative (Review Focus: counters must never go negative).
    private static func delta(_ current: UInt32, _ previous: UInt32) -> UInt32 {
        current >= previous ? current - previous : 0
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CPUCoreTests`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Write the real sensor wrapper (not unit tested — needs real hardware; verified in Task 9's smoke test)**

```swift
// Sources/CPUCore/CPUMetricsSource.swift
// SPDX-License-Identifier: MIT
import Foundation
import Darwin

public final class CPUMetricsSource: ObservableObject {
    @Published public private(set) var latest: CPUSnapshot?

    private var timer: Timer?
    private var previousLoads: [host_cpu_load_info]?

    public init() {}

    public func start(interval: TimeInterval = 1.0) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        previousLoads = nil
    }

    private func tick() {
        guard let current = Self.readProcessorLoads() else { return }
        if let previous = previousLoads {
            latest = CPUCalculator.usage(previous: previous, current: current)
        }
        previousLoads = current
    }

    private static func readProcessorLoads() -> [host_cpu_load_info]? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t!
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount)
        guard result == KERN_SUCCESS else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let loadInfo = infoArray.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) { ptr in
            (0..<Int(cpuCount)).map { i -> host_cpu_load_info in
                var info = host_cpu_load_info()
                info.cpu_ticks.0 = UInt32(ptr[i].cpu_ticks.0)
                info.cpu_ticks.1 = UInt32(ptr[i].cpu_ticks.1)
                info.cpu_ticks.2 = UInt32(ptr[i].cpu_ticks.2)
                info.cpu_ticks.3 = UInt32(ptr[i].cpu_ticks.3)
                return info
            }
        }
        return loadInfo
    }
}
```

- [ ] **Step 6: Write the views**

```swift
// Sources/CPUCore/CPUWidgetView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

public struct CPUMenuBarView: View {
    @ObservedObject var source: CPUMetricsSource
    public init(source: CPUMetricsSource) { self.source = source }
    public var body: some View {
        Text(String(format: "CPU %.0f%%", (source.latest?.totalUsage ?? 0) * 100))
            .font(.system(size: 11, design: .monospaced))
    }
}

public struct CPUDetailView: View {
    @ObservedObject var source: CPUMetricsSource
    public init(source: CPUMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading) {
            Text("CPU").font(.headline)
            if let snapshot = source.latest {
                ForEach(Array(snapshot.perCoreUsage.enumerated()), id: \.offset) { index, usage in
                    Text(String(format: "Core %d: %.0f%%", index, usage * 100))
                }
            } else {
                Text("Waiting for data...")
            }
        }.padding()
    }
}
```

- [ ] **Step 7: Run `swift build` to verify everything compiles together**

Run: `swift build`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/CPUCore Tests/CPUCoreTests
git commit -m "Add CPUCore: pure calculator (tested), real sensor wrapper, views"
```

---

### Task 3: RAMCore — pure calculation, real sensor wrapper, views

**Files:**
- Create: `Sources/RAMCore/RAMSnapshot.swift`
- Create: `Sources/RAMCore/RAMCalculator.swift`
- Create: `Sources/RAMCore/RAMMetricsSource.swift`
- Create: `Sources/RAMCore/RAMWidgetView.swift`
- Test: `Tests/RAMCoreTests/RAMCalculatorTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `public struct RAMSnapshot { public let wiredBytes: UInt64; public let activeBytes: UInt64; public let inactiveBytes: UInt64; public let compressedBytes: UInt64; public let freeBytes: UInt64; public let totalBytes: UInt64; public var usedFraction: Double { get } }`, `public struct RAMCalculator { public static func snapshot(stats: vm_statistics64, pageSize: UInt64, totalPhysicalBytes: UInt64) -> RAMSnapshot }`, `public final class RAMMetricsSource: ObservableObject { @Published public private(set) var latest: RAMSnapshot?; public func start(interval: TimeInterval = 1.0); public func stop() }`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/RAMCoreTests/RAMCalculatorTests.swift
import XCTest
@testable import RAMCore
import Darwin

final class RAMCalculatorTests: XCTestCase {
    func test_knownPageCounts_convertToExpectedByteValuesAndFraction() {
        var stats = vm_statistics64()
        stats.wire_count = 100          // 100 pages wired
        stats.active_count = 200
        stats.inactive_count = 50
        stats.compressor_page_count = 25
        stats.free_count = 25
        let pageSize: UInt64 = 4096
        let totalPhysical: UInt64 = 400 * 4096 // exactly matches the pages above

        let snapshot = RAMCalculator.snapshot(stats: stats, pageSize: pageSize, totalPhysicalBytes: totalPhysical)

        XCTAssertEqual(snapshot.wiredBytes, 100 * 4096)
        XCTAssertEqual(snapshot.activeBytes, 200 * 4096)
        XCTAssertEqual(snapshot.inactiveBytes, 50 * 4096)
        XCTAssertEqual(snapshot.compressedBytes, 25 * 4096)
        XCTAssertEqual(snapshot.freeBytes, 25 * 4096)
        XCTAssertEqual(snapshot.totalBytes, totalPhysical)
        // used = total - free = 375/400
        XCTAssertEqual(snapshot.usedFraction, 375.0 / 400.0, accuracy: 0.0001)
    }

    func test_zeroTotalBytes_doesNotDivideByZero() {
        let snapshot = RAMCalculator.snapshot(stats: vm_statistics64(), pageSize: 4096, totalPhysicalBytes: 0)
        XCTAssertEqual(snapshot.usedFraction, 0.0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RAMCoreTests`
Expected: FAIL — `RAMCalculator` not found.

- [ ] **Step 3: Write the snapshot type and calculator**

```swift
// Sources/RAMCore/RAMSnapshot.swift
// SPDX-License-Identifier: MIT
import Foundation

public struct RAMSnapshot: Equatable {
    public let wiredBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let compressedBytes: UInt64
    public let freeBytes: UInt64
    public let totalBytes: UInt64

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        let used = totalBytes > freeBytes ? totalBytes - freeBytes : 0
        return Double(used) / Double(totalBytes)
    }

    public init(wiredBytes: UInt64, activeBytes: UInt64, inactiveBytes: UInt64, compressedBytes: UInt64, freeBytes: UInt64, totalBytes: UInt64) {
        self.wiredBytes = wiredBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.compressedBytes = compressedBytes
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }
}
```

```swift
// Sources/RAMCore/RAMCalculator.swift
// SPDX-License-Identifier: MIT
import Darwin

public struct RAMCalculator {
    public static func snapshot(stats: vm_statistics64, pageSize: UInt64, totalPhysicalBytes: UInt64) -> RAMSnapshot {
        RAMSnapshot(
            wiredBytes: UInt64(stats.wire_count) * pageSize,
            activeBytes: UInt64(stats.active_count) * pageSize,
            inactiveBytes: UInt64(stats.inactive_count) * pageSize,
            compressedBytes: UInt64(stats.compressor_page_count) * pageSize,
            freeBytes: UInt64(stats.free_count) * pageSize,
            totalBytes: totalPhysicalBytes
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter RAMCoreTests`
Expected: PASS.

- [ ] **Step 5: Write the real sensor wrapper**

```swift
// Sources/RAMCore/RAMMetricsSource.swift
// SPDX-License-Identifier: MIT
import Foundation
import Darwin

public final class RAMMetricsSource: ObservableObject {
    @Published public private(set) var latest: RAMSnapshot?
    private var timer: Timer?

    public init() {}

    public func start(interval: TimeInterval = 1.0) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        let totalPhysical = ProcessInfo.processInfo.physicalMemory

        latest = RAMCalculator.snapshot(stats: stats, pageSize: UInt64(pageSize), totalPhysicalBytes: totalPhysical)
    }
}
```

- [ ] **Step 6: Write the views**

```swift
// Sources/RAMCore/RAMWidgetView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

public struct RAMMenuBarView: View {
    @ObservedObject var source: RAMMetricsSource
    public init(source: RAMMetricsSource) { self.source = source }
    public var body: some View {
        Text(String(format: "RAM %.0f%%", (source.latest?.usedFraction ?? 0) * 100))
            .font(.system(size: 11, design: .monospaced))
    }
}

public struct RAMDetailView: View {
    @ObservedObject var source: RAMMetricsSource
    public init(source: RAMMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading) {
            Text("Memory").font(.headline)
            if let s = source.latest {
                Text("Wired: \(ByteCountFormatter.string(fromByteCount: Int64(s.wiredBytes), countStyle: .memory))")
                Text("Active: \(ByteCountFormatter.string(fromByteCount: Int64(s.activeBytes), countStyle: .memory))")
                Text("Compressed: \(ByteCountFormatter.string(fromByteCount: Int64(s.compressedBytes), countStyle: .memory))")
                Text("Free: \(ByteCountFormatter.string(fromByteCount: Int64(s.freeBytes), countStyle: .memory))")
            } else {
                Text("Waiting for data...")
            }
        }.padding()
    }
}
```

- [ ] **Step 7: Run `swift build` to verify it all compiles**

Run: `swift build`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/RAMCore Tests/RAMCoreTests
git commit -m "Add RAMCore: pure calculator (tested), real sensor wrapper, views"
```

---

### Task 4: NetworkCore — throughput calculation, local/public IP, real wrapper, views

**Files:**
- Create: `Sources/NetworkCore/NetworkSnapshot.swift`
- Create: `Sources/NetworkCore/ThroughputCalculator.swift`
- Create: `Sources/NetworkCore/IPAddressParser.swift`
- Create: `Sources/NetworkCore/PublicIPFetcher.swift`
- Create: `Sources/NetworkCore/NetworkMetricsSource.swift`
- Create: `Sources/NetworkCore/NetworkWidgetView.swift`
- Test: `Tests/NetworkCoreTests/ThroughputCalculatorTests.swift`
- Test: `Tests/NetworkCoreTests/PublicIPFetcherTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `public struct InterfaceCounters { public let name: String; public let rxBytes: UInt64; public let txBytes: UInt64 }`, `public struct ThroughputCalculator { public static func throughput(previous: [InterfaceCounters], current: [InterfaceCounters], elapsed: TimeInterval) -> (rxBytesPerSec: Double, txBytesPerSec: Double, perInterface: [String: (rx: Double, tx: Double)]) }`, `public struct PublicIPFetcher { public static func parse(responseBody: String) -> String? }`, `public final class NetworkMetricsSource: ObservableObject { @Published public private(set) var latest: NetworkSnapshot?; public func start(interval: TimeInterval = 1.0); public func stop(); public func refreshPublicIPNow(); public func setPublicIPLookupEnabled(_ enabled: Bool) }`.

- [ ] **Step 1: Write the failing throughput test**

```swift
// Tests/NetworkCoreTests/ThroughputCalculatorTests.swift
import XCTest
@testable import NetworkCore

final class ThroughputCalculatorTests: XCTestCase {
    func test_byteDeltaOverTime_computesBytesPerSecond() {
        let previous = [InterfaceCounters(name: "en0", rxBytes: 1000, txBytes: 500)]
        let current = [InterfaceCounters(name: "en0", rxBytes: 3000, txBytes: 1500)]
        let result = ThroughputCalculator.throughput(previous: previous, current: current, elapsed: 2.0)
        XCTAssertEqual(result.rxBytesPerSec, 1000, accuracy: 0.001) // (3000-1000)/2
        XCTAssertEqual(result.txBytesPerSec, 500, accuracy: 0.001)
        XCTAssertEqual(result.perInterface["en0"]?.rx, 1000, accuracy: 0.001)
    }

    func test_interfaceCounterReset_isSkippedNotNegative() {
        // Review Focus: an interface going down/up (Wi-Fi toggle, sleep/wake) can reset its
        // counters. A decrease must never produce negative throughput.
        let previous = [InterfaceCounters(name: "en0", rxBytes: 50_000, txBytes: 10_000)]
        let current = [InterfaceCounters(name: "en0", rxBytes: 200, txBytes: 100)]
        let result = ThroughputCalculator.throughput(previous: previous, current: current, elapsed: 1.0)
        XCTAssertEqual(result.rxBytesPerSec, 0, accuracy: 0.001)
        XCTAssertEqual(result.txBytesPerSec, 0, accuracy: 0.001)
    }

    func test_interfaceDisappearsBetweenSamples_isIgnoredNotCrashing() {
        let previous = [InterfaceCounters(name: "en0", rxBytes: 100, txBytes: 100),
                         InterfaceCounters(name: "utun0", rxBytes: 100, txBytes: 100)]
        let current = [InterfaceCounters(name: "en0", rxBytes: 200, txBytes: 200)] // utun0 gone
        let result = ThroughputCalculator.throughput(previous: previous, current: current, elapsed: 1.0)
        XCTAssertEqual(result.perInterface.count, 1)
        XCTAssertNil(result.perInterface["utun0"])
    }

    func test_zeroElapsed_doesNotDivideByZero() {
        let previous = [InterfaceCounters(name: "en0", rxBytes: 100, txBytes: 100)]
        let current = [InterfaceCounters(name: "en0", rxBytes: 200, txBytes: 200)]
        let result = ThroughputCalculator.throughput(previous: previous, current: current, elapsed: 0)
        XCTAssertEqual(result.rxBytesPerSec, 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter NetworkCoreTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Write InterfaceCounters and ThroughputCalculator**

```swift
// Sources/NetworkCore/NetworkSnapshot.swift
// SPDX-License-Identifier: MIT
import Foundation

public struct InterfaceCounters: Equatable {
    public let name: String
    public let rxBytes: UInt64
    public let txBytes: UInt64
    public init(name: String, rxBytes: UInt64, txBytes: UInt64) {
        self.name = name; self.rxBytes = rxBytes; self.txBytes = txBytes
    }
}

public struct NetworkSnapshot: Equatable {
    public let rxBytesPerSec: Double
    public let txBytesPerSec: Double
    public let perInterface: [String: Double] // combined rx+tx, for the detail view
    public let localIPv4: String?
    public let publicIP: String?
    public let timestamp: Date
    public init(rxBytesPerSec: Double, txBytesPerSec: Double, perInterface: [String: Double], localIPv4: String?, publicIP: String?, timestamp: Date = Date()) {
        self.rxBytesPerSec = rxBytesPerSec; self.txBytesPerSec = txBytesPerSec
        self.perInterface = perInterface; self.localIPv4 = localIPv4; self.publicIP = publicIP
        self.timestamp = timestamp
    }
}
```

```swift
// Sources/NetworkCore/ThroughputCalculator.swift
// SPDX-License-Identifier: MIT
import Foundation

public struct ThroughputCalculator {
    public static func throughput(
        previous: [InterfaceCounters],
        current: [InterfaceCounters],
        elapsed: TimeInterval
    ) -> (rxBytesPerSec: Double, txBytesPerSec: Double, perInterface: [String: (rx: Double, tx: Double)]) {
        guard elapsed > 0 else { return (0, 0, [:]) }

        let previousByName = Dictionary(uniqueKeysWithValues: previous.map { ($0.name, $0) })
        var perInterface: [String: (rx: Double, tx: Double)] = [:]
        var totalRx: Double = 0
        var totalTx: Double = 0

        for cur in current {
            guard let prev = previousByName[cur.name] else { continue } // new interface, no baseline yet
            let rxDelta = cur.rxBytes >= prev.rxBytes ? cur.rxBytes - prev.rxBytes : 0
            let txDelta = cur.txBytes >= prev.txBytes ? cur.txBytes - prev.txBytes : 0
            let rxRate = Double(rxDelta) / elapsed
            let txRate = Double(txDelta) / elapsed
            perInterface[cur.name] = (rx: rxRate, tx: txRate)
            totalRx += rxRate
            totalTx += txRate
        }

        return (totalRx, totalTx, perInterface)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter NetworkCoreTests`
Expected: PASS (4 tests). Note the test file references `result.perInterface["en0"]?.rx` as a plain `Double` — adjust the test's tuple access if the compiler complains about `(rx: Double, tx: Double)` naming; keep the assertions, fix only the access syntax.

- [ ] **Step 5: Write the failing public-IP parsing test**

```swift
// Tests/NetworkCoreTests/PublicIPFetcherTests.swift
import XCTest
@testable import NetworkCore

final class PublicIPFetcherTests: XCTestCase {
    func test_parsesPlainTextIPResponse() {
        XCTAssertEqual(PublicIPFetcher.parse(responseBody: "203.0.113.42\n"), "203.0.113.42")
    }

    func test_rejectsGarbageResponse() {
        // Review Focus: a captive portal or proxy can return an HTML error page instead of
        // an IP. Must return nil, not a garbage "IP".
        XCTAssertNil(PublicIPFetcher.parse(responseBody: "<html>captive portal</html>"))
    }

    func test_rejectsEmptyResponse() {
        XCTAssertNil(PublicIPFetcher.parse(responseBody: ""))
    }
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `swift test --filter PublicIPFetcherTests`
Expected: FAIL — `PublicIPFetcher` not found.

- [ ] **Step 7: Write the parser and the real fetcher**

```swift
// Sources/NetworkCore/PublicIPFetcher.swift
// SPDX-License-Identifier: MIT
import Foundation

public struct PublicIPFetcher {
    private static let endpoints = ["https://api.ipify.org", "https://icanhazip.com"]

    /// Pure parsing: a valid response is exactly one IPv4 address, nothing else.
    public static func parse(responseBody: String) -> String? {
        let trimmed = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ part in
            guard let value = Int(part) else { return false }
            return value >= 0 && value <= 255
        }) else { return nil }
        return trimmed
    }

    /// Tries each endpoint in order, falling back on failure. Returns nil if all fail
    /// (Review Focus: offline/blocked must degrade to "unavailable", never crash or hang).
    public static func fetch(urlSession: URLSession = .shared) async -> String? {
        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            if let (data, response) = try? await urlSession.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let body = String(data: data, encoding: .utf8),
               let ip = parse(responseBody: body) {
                return ip
            }
        }
        return nil
    }
}
```

- [ ] **Step 8: Run to verify it passes**

Run: `swift test --filter NetworkCoreTests`
Expected: PASS (all 7 tests).

- [ ] **Step 9: Write local-IP + real interface-counter reading**

```swift
// Sources/NetworkCore/IPAddressParser.swift
// SPDX-License-Identifier: MIT
import Foundation
import Darwin

public struct IPAddressParser {
    /// Reads getifaddrs() once. Returns both the IPv4 address of the first active,
    /// non-loopback interface and the raw byte counters for every interface.
    public static func readCurrentState() -> (localIPv4: String?, counters: [InterfaceCounters]) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return (nil, []) }
        defer { freeifaddrs(ifaddrPtr) }

        var localIPv4: String?
        var countersByName: [String: (rx: UInt64, tx: UInt64)] = [:]

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let name = String(cString: current.pointee.ifa_name)
            let family = current.pointee.ifa_addr.pointee.sa_family

            if family == UInt8(AF_INET), (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0, localIPv4 == nil {
                var addr = current.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(buffer.count))
                localIPv4 = String(cString: buffer)
            }

            if family == UInt8(AF_LINK), let data = current.pointee.ifa_data {
                let networkData = data.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
                countersByName[name] = (rx: UInt64(networkData.ifi_ibytes), tx: UInt64(networkData.ifi_obytes))
            }

            ptr = current.pointee.ifa_next
        }

        let counters = countersByName.map { InterfaceCounters(name: $0.key, rxBytes: $0.value.rx, txBytes: $0.value.tx) }
        return (localIPv4, counters)
    }
}
```

```swift
// Sources/NetworkCore/NetworkMetricsSource.swift
// SPDX-License-Identifier: MIT
import Foundation

public final class NetworkMetricsSource: ObservableObject {
    @Published public private(set) var latest: NetworkSnapshot?

    private var timer: Timer?
    private var publicIPTimer: Timer?
    private var previousCounters: [InterfaceCounters]?
    private var previousTimestamp: Date?
    private var currentPublicIP: String?
    private var isFetchingPublicIP = false
    private var publicIPLookupEnabled = true

    public init() {}

    public func start(interval: TimeInterval = 1.0) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
        restartPublicIPTimerIfEnabled()
    }

    public func stop() {
        timer?.invalidate(); timer = nil
        publicIPTimer?.invalidate(); publicIPTimer = nil
        previousCounters = nil
        previousTimestamp = nil
    }

    public func refreshPublicIPNow() {
        guard publicIPLookupEnabled else { return }
        fetchPublicIP()
    }

    /// spec §6: public-IP lookup is a privacy-relevant external call and must be
    /// independently toggleable. Reflected immediately: turning it off cancels any pending
    /// timer; turning it on restarts it and fetches right away.
    public func setPublicIPLookupEnabled(_ enabled: Bool) {
        publicIPLookupEnabled = enabled
        if enabled {
            restartPublicIPTimerIfEnabled()
        } else {
            publicIPTimer?.invalidate()
            publicIPTimer = nil
        }
    }

    private func restartPublicIPTimerIfEnabled() {
        guard publicIPLookupEnabled, timer != nil else { return }
        publicIPTimer?.invalidate()
        publicIPTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.fetchPublicIP() }
        RunLoop.main.add(publicIPTimer!, forMode: .common)
        fetchPublicIP()
    }

    private func tick() {
        let (localIP, counters) = IPAddressParser.readCurrentState()
        let now = Date()
        if let prevCounters = previousCounters, let prevTime = previousTimestamp {
            let result = ThroughputCalculator.throughput(previous: prevCounters, current: counters, elapsed: now.timeIntervalSince(prevTime))
            let perInterface = result.perInterface.mapValues { $0.rx + $0.tx }
            latest = NetworkSnapshot(rxBytesPerSec: result.rxBytesPerSec, txBytesPerSec: result.txBytesPerSec, perInterface: perInterface, localIPv4: localIP, publicIP: currentPublicIP)
        }
        previousCounters = counters
        previousTimestamp = now
    }

    private func fetchPublicIP() {
        // Review Focus: disabling the widget mid-flight must not deliver a result into a
        // torn-down source. Guard with a simple flag checked after the await.
        guard !isFetchingPublicIP else { return }
        isFetchingPublicIP = true
        Task { [weak self] in
            let ip = await PublicIPFetcher.fetch()
            guard let self else { return }
            self.isFetchingPublicIP = false
            guard self.timer != nil else { return } // stop() was called while this was in flight
            self.currentPublicIP = ip
            if let existing = self.latest {
                self.latest = NetworkSnapshot(rxBytesPerSec: existing.rxBytesPerSec, txBytesPerSec: existing.txBytesPerSec, perInterface: existing.perInterface, localIPv4: existing.localIPv4, publicIP: ip)
            }
        }
    }
}
```

- [ ] **Step 10: Write the views**

```swift
// Sources/NetworkCore/NetworkWidgetView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

private func formatRate(_ bytesPerSec: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSec), countStyle: .binary) + "/s"
}

public struct NetworkMenuBarView: View {
    @ObservedObject var source: NetworkMetricsSource
    public init(source: NetworkMetricsSource) { self.source = source }
    public var body: some View {
        Text("↓\(formatRate(source.latest?.rxBytesPerSec ?? 0)) ↑\(formatRate(source.latest?.txBytesPerSec ?? 0))")
            .font(.system(size: 11, design: .monospaced))
    }
}

public struct NetworkDetailView: View {
    @ObservedObject var source: NetworkMetricsSource
    public init(source: NetworkMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading) {
            Text("Network").font(.headline)
            if let s = source.latest {
                Text("Local IP: \(s.localIPv4 ?? "unavailable")")
                Text("Public IP: \(s.publicIP ?? "unavailable")")
                ForEach(Array(s.perInterface.keys.sorted()), id: \.self) { name in
                    Text("\(name): \(formatRate(s.perInterface[name] ?? 0))")
                }
                Button("Refresh public IP") { source.refreshPublicIPNow() }
            } else {
                Text("Waiting for data...")
            }
        }.padding()
    }
}
```

- [ ] **Step 11: Run `swift build` to verify everything compiles**

Run: `swift build`
Expected: PASS.

- [ ] **Step 12: Commit**

```bash
git add Sources/NetworkCore Tests/NetworkCoreTests
git commit -m "Add NetworkCore: throughput calculator + public IP parser (tested), real wrapper, views"
```

---

### Task 5: GPUCore — IOAccelerator parsing, real wrapper, views

**Files:**
- Create: `Sources/GPUCore/GPUSnapshot.swift`
- Create: `Sources/GPUCore/GPUCalculator.swift`
- Create: `Sources/GPUCore/GPUMetricsSource.swift`
- Create: `Sources/GPUCore/GPUWidgetView.swift`
- Test: `Tests/GPUCoreTests/GPUCalculatorTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `public struct GPUSnapshot { public let utilization: Double?; public let timestamp: Date }`, `public struct GPUCalculator { public static func utilization(fromPerformanceStatistics dict: [String: Any]) -> Double? }`, `public final class GPUMetricsSource: ObservableObject { @Published public private(set) var latest: GPUSnapshot?; public func start(interval: TimeInterval = 1.0); public func stop() }`.

- [ ] **Step 1: Write the failing test**

The real `IOAccelerator` "PerformanceStatistics" dictionary keys are undocumented and can vary or go missing across macOS versions — the Review Focus item for this widget is exactly that. The calculator must extract a known key if present and return `nil` (never crash, never a bogus number) otherwise.

```swift
// Tests/GPUCoreTests/GPUCalculatorTests.swift
import XCTest
@testable import GPUCore

final class GPUCalculatorTests: XCTestCase {
    func test_extractsDeviceUtilizationPercent() {
        let dict: [String: Any] = ["Device Utilization %": 42]
        XCTAssertEqual(GPUCalculator.utilization(fromPerformanceStatistics: dict), 0.42, accuracy: 0.001)
    }

    func test_missingKey_returnsNilNotCrashing() {
        // Review Focus: undocumented IOKit keys can disappear on a macOS update.
        let dict: [String: Any] = ["Something Else": 1]
        XCTAssertNil(GPUCalculator.utilization(fromPerformanceStatistics: dict))
    }

    func test_wrongValueType_returnsNilNotCrashing() {
        let dict: [String: Any] = ["Device Utilization %": "not a number"]
        XCTAssertNil(GPUCalculator.utilization(fromPerformanceStatistics: dict))
    }

    func test_emptyDictionary_returnsNil() {
        XCTAssertNil(GPUCalculator.utilization(fromPerformanceStatistics: [:]))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter GPUCoreTests`
Expected: FAIL — `GPUCalculator` not found.

- [ ] **Step 3: Write the snapshot and calculator**

```swift
// Sources/GPUCore/GPUSnapshot.swift
// SPDX-License-Identifier: MIT
import Foundation

public struct GPUSnapshot: Equatable {
    public let utilization: Double? // nil means "N/A" — never show a fabricated number
    public let timestamp: Date
    public init(utilization: Double?, timestamp: Date = Date()) {
        self.utilization = utilization
        self.timestamp = timestamp
    }
}
```

```swift
// Sources/GPUCore/GPUCalculator.swift
// SPDX-License-Identifier: MIT
import Foundation

public struct GPUCalculator {
    public static func utilization(fromPerformanceStatistics dict: [String: Any]) -> Double? {
        guard let raw = dict["Device Utilization %"] else { return nil }
        guard let number = raw as? NSNumber else { return nil }
        return number.doubleValue / 100.0
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter GPUCoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Write the real IOKit wrapper**

```swift
// Sources/GPUCore/GPUMetricsSource.swift
// SPDX-License-Identifier: MIT
import Foundation
import IOKit

public final class GPUMetricsSource: ObservableObject {
    @Published public private(set) var latest: GPUSnapshot?
    private var timer: Timer?

    public init() {}

    public func start(interval: TimeInterval = 1.0) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        latest = GPUSnapshot(utilization: Self.readUtilization())
    }

    /// Returns nil (never crashes) if no matching accelerator service or no usable key is
    /// found — Review Focus: this is the widget most likely to break across macOS versions.
    private static func readUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let props = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            if let value = GPUCalculator.utilization(fromPerformanceStatistics: props) {
                return value
            }
        }
        return nil
    }
}
```

- [ ] **Step 6: Write the views**

```swift
// Sources/GPUCore/GPUWidgetView.swift
// SPDX-License-Identifier: MIT
import SwiftUI

public struct GPUMenuBarView: View {
    @ObservedObject var source: GPUMetricsSource
    public init(source: GPUMetricsSource) { self.source = source }
    public var body: some View {
        if let utilization = source.latest?.utilization {
            Text(String(format: "GPU %.0f%%", utilization * 100)).font(.system(size: 11, design: .monospaced))
        } else {
            Text("GPU N/A").font(.system(size: 11, design: .monospaced))
        }
    }
}

public struct GPUDetailView: View {
    @ObservedObject var source: GPUMetricsSource
    public init(source: GPUMetricsSource) { self.source = source }
    public var body: some View {
        VStack(alignment: .leading) {
            Text("GPU").font(.headline)
            if let utilization = source.latest?.utilization {
                Text(String(format: "Utilization: %.0f%%", utilization * 100))
            } else {
                Text("Utilization: N/A")
            }
        }.padding()
    }
}
```

- [ ] **Step 7: Run `swift build` to verify everything compiles**

Run: `swift build`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/GPUCore Tests/GPUCoreTests
git commit -m "Add GPUCore: performance-statistics parser (tested, degrades to N/A), real wrapper, views"
```

---

### Task 6: Plugin packaging script + the 4 built-in Plugin shims

**Files:**
- Create: `Scripts/build-plugin.sh`
- Create: `Plugins/CPUWidget/PluginMain.swift`, `Plugins/CPUWidget/Info.plist`
- Create: `Plugins/RAMWidget/PluginMain.swift`, `Plugins/RAMWidget/Info.plist`
- Create: `Plugins/GPUWidget/PluginMain.swift`, `Plugins/GPUWidget/Info.plist`
- Create: `Plugins/NetworkWidget/PluginMain.swift`, `Plugins/NetworkWidget/Info.plist`

**Interfaces:**
- Consumes: `Widget`/`PluginEntry` from Task 1; `CPUMetricsSource`/`CPUMenuBarView`/`CPUDetailView` from Task 2 (and the equivalent RAM/Network/GPU types from Tasks 3-5).
- Produces: four `.bundle` directories under `.build/plugins/`, each loadable exactly like the Task 1 fixture.

- [ ] **Step 1: Write the packaging script, parameterized over the validated spike incantation**

```bash
#!/usr/bin/env bash
# Scripts/build-plugin.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

# Usage: build-plugin.sh <WidgetName> <PrincipalClassName>
# Builds Plugins/<WidgetName>/PluginMain.swift into .build/plugins/<WidgetName>Widget.bundle,
# linking against the Core library for <WidgetName> and the shared MTatsPluginKit — exactly
# the mechanism validated in spikes/plugin-loading-identity/.

NAME="$1"              # e.g. CPU
PRINCIPAL_CLASS="$2"   # e.g. CPUPluginMain

swift build # ensure MTatsPluginKit + <NAME>Core are up to date

OUT_DIR=".build/plugins/${NAME}Widget.bundle/Contents/MacOS"
mkdir -p "$OUT_DIR"

swiftc -emit-library -module-name "${NAME}Plugin" \
  -I .build/debug -L .build/debug -l"MTatsPluginKit" -l"${NAME}Core" \
  "Plugins/${NAME}Widget/PluginMain.swift" \
  -o "$OUT_DIR/${NAME}Widget" \
  -Xlinker -rpath -Xlinker "@loader_path/../../../../debug"
  # $OUT_DIR is .build/plugins/<Name>Widget.bundle/Contents/MacOS — 4 levels up from
  # there lands back at .build/, so appending "debug" (not ".build/debug") reaches
  # .build/debug. Verify with: cd "$OUT_DIR" && cd ../../../../debug && pwd

cp "Plugins/${NAME}Widget/Info.plist" ".build/plugins/${NAME}Widget.bundle/Contents/Info.plist"
codesign -s - --identifier "com.mtats.plugin.${NAME}" -f ".build/plugins/${NAME}Widget.bundle"

echo "Built .build/plugins/${NAME}Widget.bundle (principal class: $PRINCIPAL_CLASS)"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x Scripts/build-plugin.sh
```

- [ ] **Step 3: Write the CPU plugin shim and Info.plist**

```swift
// Plugins/CPUWidget/PluginMain.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import MTatsPluginKit
import CPUCore

@objc(CPUWidgetAdapter) class CPUWidgetAdapter: NSObject, Widget {
    let id = "cpu"
    let displayName = "CPU"
    private let source = CPUMetricsSource()
    func start(interval: TimeInterval) { source.start(interval: interval) }
    func stop() { source.stop() }
    func menuBarView() -> AnyView { AnyView(CPUMenuBarView(source: source)) }
    func detailView() -> AnyView { AnyView(CPUDetailView(source: source)) }
}

@objc(CPUPluginMain) public class CPUPluginMain: NSObject, PluginEntry {
    @objc public static func makeWidgets() -> [Widget] { [CPUWidgetAdapter()] }
}
```

```xml
<!-- Plugins/CPUWidget/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CPUWidget</string>
  <key>CFBundleIdentifier</key><string>com.mtats.plugin.cpu</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>NSPrincipalClass</key><string>CPUPluginMain</string>
  <key>MTatsPluginAPIVersion</key><integer>1</integer>
</dict></plist>
```

- [ ] **Step 4: Build it and smoke-test loading, reusing Task 1's fixture host**

```bash
Scripts/build-plugin.sh CPU CPUPluginMain
```

Expected: prints "Built .build/plugins/CPUWidget.bundle ...". If `codesign` or linking fails, the error names the exact missing symbol/path — fix the script's `-l`/`-rpath` flags, don't change the protocol.

- [ ] **Step 5: Write the RAM plugin shim and Info.plist**

```swift
// Plugins/RAMWidget/PluginMain.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import MTatsPluginKit
import RAMCore

@objc(RAMWidgetAdapter) class RAMWidgetAdapter: NSObject, Widget {
    let id = "ram"
    let displayName = "RAM"
    private let source = RAMMetricsSource()
    func start(interval: TimeInterval) { source.start(interval: interval) }
    func stop() { source.stop() }
    func menuBarView() -> AnyView { AnyView(RAMMenuBarView(source: source)) }
    func detailView() -> AnyView { AnyView(RAMDetailView(source: source)) }
}

@objc(RAMPluginMain) public class RAMPluginMain: NSObject, PluginEntry {
    @objc public static func makeWidgets() -> [Widget] { [RAMWidgetAdapter()] }
}
```

```xml
<!-- Plugins/RAMWidget/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>RAMWidget</string>
  <key>CFBundleIdentifier</key><string>com.mtats.plugin.ram</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>NSPrincipalClass</key><string>RAMPluginMain</string>
  <key>MTatsPluginAPIVersion</key><integer>1</integer>
</dict></plist>
```

Build and smoke-test it: `Scripts/build-plugin.sh RAM RAMPluginMain`. Expected: "Built .build/plugins/RAMWidget.bundle ...".

- [ ] **Step 6: Write the GPU plugin shim and Info.plist**

```swift
// Plugins/GPUWidget/PluginMain.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import MTatsPluginKit
import GPUCore

@objc(GPUWidgetAdapter) class GPUWidgetAdapter: NSObject, Widget {
    let id = "gpu"
    let displayName = "GPU"
    private let source = GPUMetricsSource()
    func start(interval: TimeInterval) { source.start(interval: interval) }
    func stop() { source.stop() }
    func menuBarView() -> AnyView { AnyView(GPUMenuBarView(source: source)) }
    func detailView() -> AnyView { AnyView(GPUDetailView(source: source)) }
}

@objc(GPUPluginMain) public class GPUPluginMain: NSObject, PluginEntry {
    @objc public static func makeWidgets() -> [Widget] { [GPUWidgetAdapter()] }
}
```

```xml
<!-- Plugins/GPUWidget/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>GPUWidget</string>
  <key>CFBundleIdentifier</key><string>com.mtats.plugin.gpu</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>NSPrincipalClass</key><string>GPUPluginMain</string>
  <key>MTatsPluginAPIVersion</key><integer>1</integer>
</dict></plist>
```

Build and smoke-test it: `Scripts/build-plugin.sh GPU GPUPluginMain`.

- [ ] **Step 7: Write the Network plugin shim and Info.plist**

The Network widget additionally conforms to `PublicIPToggleable` (Task 1) — the only one of the 4 that needs it (spec §6's public-IP toggle).

```swift
// Plugins/NetworkWidget/PluginMain.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import MTatsPluginKit
import NetworkCore

@objc(NetworkWidgetAdapter) class NetworkWidgetAdapter: NSObject, Widget, PublicIPToggleable {
    let id = "network"
    let displayName = "Network"
    private let source = NetworkMetricsSource()
    func start(interval: TimeInterval) { source.start(interval: interval) }
    func stop() { source.stop() }
    func menuBarView() -> AnyView { AnyView(NetworkMenuBarView(source: source)) }
    func detailView() -> AnyView { AnyView(NetworkDetailView(source: source)) }
    func setPublicIPLookupEnabled(_ enabled: Bool) { source.setPublicIPLookupEnabled(enabled) }
}

@objc(NetworkPluginMain) public class NetworkPluginMain: NSObject, PluginEntry {
    @objc public static func makeWidgets() -> [Widget] { [NetworkWidgetAdapter()] }
}
```

```xml
<!-- Plugins/NetworkWidget/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>NetworkWidget</string>
  <key>CFBundleIdentifier</key><string>com.mtats.plugin.network</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>NSPrincipalClass</key><string>NetworkPluginMain</string>
  <key>MTatsPluginAPIVersion</key><integer>1</integer>
</dict></plist>
```

Build and smoke-test it: `Scripts/build-plugin.sh Network NetworkPluginMain`.

- [ ] **Step 8: Commit**

```bash
git add Scripts/build-plugin.sh Plugins
git commit -m "Add plugin packaging script and the 4 built-in widget plugin shims"
```

---

### Task 7: Host app — PluginLoader (discovery, signature/version check, FSEvents watch)

**Files:**
- Create: `Sources/mtats/PluginLoader.swift`
- Test: `Tests/mtatsTests/PluginLoaderTests.swift` (the parts that don't need real bundles — path/version logic; loading itself is exercised in Task 10's smoke test)

**Interfaces:**
- Consumes: `Widget`, `PluginEntry`, `pluginAPIVersion` from Task 1.
- Produces: `public final class PluginLoader { public func loadAll(builtInDirectory: URL, userDirectory: URL) -> [Widget]; public static func isAPIVersionCompatible(infoDictionary: [String: Any]) -> Bool; public func hasValidSignature(bundlePath: URL) -> Bool; public func watchForNewPlugins(in: URL, onNewWidgets: @escaping ([Widget]) -> Void) -> PluginDirectoryWatcher }`, `public final class PluginDirectoryWatcher { public func start(); public func stop() }`

- [ ] **Step 1: Write the failing test for the pure version-check logic**

```swift
// Tests/mtatsTests/PluginLoaderTests.swift
import XCTest
@testable import mtats
import MTatsPluginKit

final class PluginLoaderTests: XCTestCase {
    func test_matchingAPIVersion_isCompatible() {
        let plist: [String: Any] = ["MTatsPluginAPIVersion": pluginAPIVersion]
        XCTAssertTrue(PluginLoader.isAPIVersionCompatible(infoDictionary: plist))
    }

    func test_mismatchedAPIVersion_isNotCompatible() {
        let plist: [String: Any] = ["MTatsPluginAPIVersion": pluginAPIVersion + 1]
        XCTAssertFalse(PluginLoader.isAPIVersionCompatible(infoDictionary: plist))
    }

    func test_missingAPIVersionKey_isNotCompatible() {
        XCTAssertFalse(PluginLoader.isAPIVersionCompatible(infoDictionary: [:]))
    }

    func test_ensureDirectoryExists_createsAMissingDirectoryRatherThanSkippingItSilently() {
        // Review Focus: a fresh install has never written to ~/Library/Application Support/mtats/Plugins —
        // the Host must create it, not silently skip watching it.
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pluginsDir = tempRoot.appendingPathComponent("mtats/Plugins")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginsDir.path))
        PluginLoader().ensureDirectoryExists(pluginsDir)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: pluginsDir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PluginLoaderTests`
Expected: FAIL — `PluginLoader` not found.

- [ ] **Step 3: Write PluginLoader**

```swift
// Sources/mtats/PluginLoader.swift
// SPDX-License-Identifier: MIT
import Foundation
import CoreServices // FSEventStream, for PluginDirectoryWatcher below
import MTatsPluginKit

public final class PluginLoader {
    public init() {}

    public static func isAPIVersionCompatible(infoDictionary: [String: Any]) -> Bool {
        guard let declared = infoDictionary["MTatsPluginAPIVersion"] as? Int else { return false }
        return declared == pluginAPIVersion
    }

    public func hasValidSignature(bundlePath: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundlePath as CFURL, [], &staticCode) == errSecSuccess, let code = staticCode else { return false }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    /// Review Focus: the third-party directory may not exist yet on a fresh install.
    /// Create it rather than skip watching it silently.
    public func ensureDirectoryExists(_ directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func loadAll(builtInDirectory: URL, userDirectory: URL) -> [Widget] {
        ensureDirectoryExists(userDirectory)
        var widgets: [Widget] = []
        for directory in [builtInDirectory, userDirectory] {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "bundle" {
                widgets.append(contentsOf: load(bundleAt: entry))
            }
        }
        return widgets
    }

    private func load(bundleAt path: URL) -> [Widget] {
        guard hasValidSignature(bundlePath: path) else {
            print("PluginLoader: skipping \(path.lastPathComponent) — invalid/missing signature")
            return []
        }
        guard let bundle = Bundle(url: path), let info = bundle.infoDictionary,
              Self.isAPIVersionCompatible(infoDictionary: info) else {
            print("PluginLoader: skipping \(path.lastPathComponent) — incompatible or unreadable plugin API version")
            return []
        }
        guard bundle.load(), let principal = bundle.principalClass as? PluginEntry.Type else {
            print("PluginLoader: skipping \(path.lastPathComponent) — failed to load or find PluginEntry")
            return []
        }
        return principal.makeWidgets()
    }

    /// spec §4.2: the third-party directory is watched so a new plugin loads without a
    /// relaunch. FSEventStream is a C API; wrap it in a small class so the closure-based
    /// callback has somewhere to route back into Swift.
    public func watchForNewPlugins(in directory: URL, onNewWidgets: @escaping ([Widget]) -> Void) -> PluginDirectoryWatcher {
        let watcher = PluginDirectoryWatcher(directory: directory) { [weak self] in
            guard let self, let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            let newWidgets = entries
                .filter { $0.pathExtension == "bundle" }
                .flatMap { self.load(bundleAt: $0) }
            if !newWidgets.isEmpty { onNewWidgets(newWidgets) }
        }
        watcher.start()
        return watcher
    }
}

/// Thin wrapper around FSEventStream. Kept separate from PluginLoader so PluginLoader's
/// core logic (signature/version checks) stays unit-testable without touching FSEvents.
public final class PluginDirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let directory: URL
    private let onChange: () -> Void

    public init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    public func start() {
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<PluginDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, callback, &context, [directory.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, UInt32(kFSEventStreamCreateFlagNone))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
```

- [ ] **Step 4: Run to verify the pure tests pass**

Run: `swift test --filter PluginLoaderTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Run `swift build` to verify it all compiles, including the FSEvents watcher**

Run: `swift build`
Expected: PASS. If `FSEventStreamCreate`'s callback closure fails to convert to `FSEventStreamCallback` (a C function pointer can't capture context the normal Swift way), that's expected — C function pointers can only close over nothing; the code above already avoids this by taking `info` as the `self` pointer instead of capturing `self` in the closure, so no change should be needed, but confirm it actually builds before moving on.

- [ ] **Step 6: Commit**

```bash
git add Sources/mtats/PluginLoader.swift Tests/mtatsTests
git commit -m "Add PluginLoader: signature/version checks (tested), discovery, FSEvents hot-reload watcher"
```

---

### Task 8: Host app — status bar, settings, lifecycle wiring

**Files:**
- Create: `Sources/mtats/main.swift`
- Create: `Sources/mtats/StatusBarController.swift`
- Create: `Sources/mtats/SettingsStore.swift`
- Create: `Sources/mtats/SettingsView.swift`
- Test: `Tests/mtatsTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `Widget` from Task 1, `PluginLoader` from Task 7.
- Produces: a runnable `mtats` executable.

- [ ] **Step 1: Write the failing test for settings persistence logic**

```swift
// Tests/mtatsTests/SettingsStoreTests.swift
import XCTest
@testable import mtats

final class SettingsStoreTests: XCTestCase {
    func test_newWidgetDefaultsToEnabled() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "mtats.tests.\(UUID())")!)
        XCTAssertTrue(store.isEnabled(widgetID: "cpu"))
    }

    func test_disablingAWidget_persists() {
        let defaults = UserDefaults(suiteName: "mtats.tests.\(UUID())")!
        let store = SettingsStore(defaults: defaults)
        store.setEnabled(false, widgetID: "cpu")
        XCTAssertFalse(store.isEnabled(widgetID: "cpu"))
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled(widgetID: "cpu"))
    }

    func test_refreshIntervalDefaultsToOneSecond() {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "mtats.tests.\(UUID())")!)
        XCTAssertEqual(store.refreshInterval, 1.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — `SettingsStore` not found.

- [ ] **Step 3: Write SettingsStore**

```swift
// Sources/mtats/SettingsStore.swift
// SPDX-License-Identifier: MIT
import Foundation
import ServiceManagement

public final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled(widgetID: String) -> Bool {
        defaults.object(forKey: "widget.\(widgetID).enabled") as? Bool ?? true
    }

    public func setEnabled(_ enabled: Bool, widgetID: String) {
        defaults.set(enabled, forKey: "widget.\(widgetID).enabled")
    }

    public var refreshInterval: TimeInterval {
        get { let value = defaults.double(forKey: "refreshInterval"); return value > 0 ? value : 1.0 }
        set { defaults.set(newValue, forKey: "refreshInterval") }
    }

    /// Actually registers/unregisters with the system (ServiceManagement), not just a
    /// stored preference — spec §6 lists this as a real toggle, not a label.
    public var launchAtLoginEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                print("SettingsStore: launch-at-login change failed: \(error)")
            }
        }
    }

    public var publicIPLookupEnabled: Bool {
        get { defaults.object(forKey: "publicIPLookupEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "publicIPLookupEnabled") }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS (3 tests). Do not add a test for `launchAtLoginEnabled` — `SMAppService` requires running inside a real, properly-identified `.app` bundle, which `swift test` doesn't provide; it's exercised manually once Task 9 produces a real `mtats.app`.

- [ ] **Step 5: Write the status bar controller**

```swift
// Sources/mtats/StatusBarController.swift
// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI
import MTatsPluginKit

public final class StatusBarController {
    private var items: [NSStatusItem] = []
    private var widgets: [Widget] = []
    private var settingsItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Call again with an expanded widget list (e.g. after the FSEvents watcher in
    /// PluginLoader reports a newly-installed third-party plugin) — existing items for
    /// widgets already presented are left alone; only genuinely new widgets get a new item.
    public func present(widgets: [Widget]) {
        let alreadyPresentedIDs = Set(self.widgets.map(\.id))
        let newWidgets = widgets.filter { !alreadyPresentedIDs.contains($0.id) }
        self.widgets.append(contentsOf: newWidgets)

        for widget in newWidgets {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let hosting = NSHostingView(rootView: widget.menuBarView())
            hosting.frame = NSRect(x: 0, y: 0, width: 80, height: 22)
            item.button?.addSubview(hosting)
            item.button?.frame = hosting.frame

            let popover = NSPopover()
            popover.contentViewController = NSHostingController(rootView: widget.detailView())
            popover.behavior = .transient
            item.button?.target = PopoverShower.shared
            item.button?.action = #selector(PopoverShower.toggle(_:))
            PopoverShower.shared.register(button: item.button!, popover: popover)

            items.append(item)
            if settings.isEnabled(widgetID: widget.id) {
                widget.start(interval: settings.refreshInterval)
            }
            if let toggleable = widget as? PublicIPToggleable {
                toggleable.setPublicIPLookupEnabled(settings.publicIPLookupEnabled)
            }
        }

        if settingsItem == nil { presentSettingsMenuItem() }
    }

    public func applyEnabledState() {
        for widget in widgets {
            if settings.isEnabled(widgetID: widget.id) {
                widget.start(interval: settings.refreshInterval)
            } else {
                widget.stop()
            }
            if let toggleable = widget as? PublicIPToggleable {
                toggleable.setPublicIPLookupEnabled(settings.publicIPLookupEnabled)
            }
        }
    }

    /// spec §6 requires Settings to actually be reachable. A small "⚙" status item is the
    /// simplest way to do that for v1 — no Dock icon (LSUIElement), so there's no menu bar
    /// "app menu" to hang a Settings item off of otherwise.
    private func presentSettingsMenuItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "⚙"
        item.button?.target = self
        item.button?.action = #selector(openSettings)
        settingsItem = item
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, widgets: widgets, onToggle: { [weak self] in self?.applyEnabledState() })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "mtats Settings"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Minimal shared target/action so each status item's button can toggle its own popover.
private final class PopoverShower: NSObject {
    static let shared = PopoverShower()
    private var popovers: [ObjectIdentifier: NSPopover] = [:]

    func register(button: NSStatusBarButton, popover: NSPopover) {
        popovers[ObjectIdentifier(button)] = popover
    }

    @objc func toggle(_ sender: NSStatusBarButton) {
        guard let popover = popovers[ObjectIdentifier(sender)] else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
```

- [ ] **Step 6: Write the settings view**

```swift
// Sources/mtats/SettingsView.swift
// SPDX-License-Identifier: MIT
import SwiftUI
import MTatsPluginKit

public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let widgets: [Widget]
    let onToggle: () -> Void

    public init(settings: SettingsStore, widgets: [Widget], onToggle: @escaping () -> Void) {
        self.settings = settings
        self.widgets = widgets
        self.onToggle = onToggle
    }

    public var body: some View {
        Form {
            ForEach(widgets, id: \.id) { widget in
                Toggle(widget.displayName, isOn: Binding(
                    get: { settings.isEnabled(widgetID: widget.id) },
                    set: { settings.setEnabled($0, widgetID: widget.id); onToggle() }
                ))
            }
            Stepper(value: Binding(
                get: { settings.refreshInterval },
                set: { settings.refreshInterval = $0; onToggle() }
            ), in: 0.5...5.0, step: 0.5) {
                Text(String(format: "Refresh every %.1fs", settings.refreshInterval))
            }
            Toggle("Launch at login", isOn: Binding(
                get: { settings.launchAtLoginEnabled },
                set: { settings.launchAtLoginEnabled = $0 }
            ))
            Toggle("Look up public IP", isOn: Binding(
                get: { settings.publicIPLookupEnabled },
                set: { settings.publicIPLookupEnabled = $0; onToggle() }
            ))
        }.padding()
    }
}
```

- [ ] **Step 7: Write main.swift wiring it all together**

```swift
// Sources/mtats/main.swift
// SPDX-License-Identifier: MIT
import AppKit
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon

let settings = SettingsStore()
let loader = PluginLoader()
let builtInDirectory = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Plugins")
let userDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("mtats/Plugins")

let widgets = loader.loadAll(builtInDirectory: builtInDirectory, userDirectory: userDirectory)
let statusBar = StatusBarController(settings: settings)
statusBar.present(widgets: widgets)

// spec §4.2: third-party plugins hot-load without a relaunch. Held at top level so it
// isn't deallocated (which would stop the FSEventStream) — main.swift has no owner above it.
let watcher = loader.watchForNewPlugins(in: userDirectory) { newWidgets in
    statusBar.present(widgets: newWidgets)
}

if let index = CommandLine.arguments.firstIndex(where: { $0.hasPrefix("--smoke-test-exit-after=") }),
   let seconds = Double(CommandLine.arguments[index].split(separator: "=")[1]) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
}

app.run()
```

- [ ] **Step 8: Run `swift build` to verify it all compiles**

Run: `swift build`
Expected: PASS. (`swift run mtats` will show no widgets yet since no plugins are embedded at `Contents/Resources/Plugins` for a plain SwiftPM executable — that's Task 9's job.)

- [ ] **Step 9: Commit**

```bash
git add Sources/mtats Tests/mtatsTests
git commit -m "Add Host: status bar controller, settings store (tested), settings view, main wiring"
```

---

### Task 9: App packaging script (assemble mtats.app with embedded built-ins)

**Files:**
- Create: `Scripts/package-app.sh`

**Interfaces:**
- Consumes: the `mtats` executable from Task 8, the 4 `.bundle`s from Task 6.
- Produces: `.build/mtats.app`, a runnable, ad-hoc-signed app bundle with the 4 built-in plugins embedded at `Contents/Resources/Plugins/`.

- [ ] **Step 1: Write the packaging script**

```bash
#!/usr/bin/env bash
# Scripts/package-app.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

swift build -c debug
for widget in CPU RAM GPU Network; do
  Scripts/build-plugin.sh "$widget" "${widget}PluginMain"
done

APP=".build/mtats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Plugins"

cp .build/debug/mtats "$APP/Contents/MacOS/mtats"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>mtats</string>
  <key>CFBundleIdentifier</key><string>com.mtats.app</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

for widget in CPU RAM GPU Network; do
  cp -R ".build/plugins/${widget}Widget.bundle" "$APP/Contents/Resources/Plugins/"
done

# Host must find MTatsPluginKit.dylib next to itself at runtime.
cp .build/debug/libMTatsPluginKit.dylib "$APP/Contents/MacOS/"
install_name_tool -add_rpath "@executable_path" "$APP/Contents/MacOS/mtats" 2>/dev/null || true

codesign -s - --identifier com.mtats.app --deep -f "$APP"

echo "Packaged $APP"
```

- [ ] **Step 2: Make it executable and run it**

```bash
chmod +x Scripts/package-app.sh
Scripts/package-app.sh
```

Expected: ends with "Packaged .build/mtats.app" and no errors. If `codesign --deep` complains about an already-valid nested signature, that's fine — the built-in plugins were already signed by `build-plugin.sh`; deep-signing re-signs the outer app without needing to touch them.

- [ ] **Step 3: Commit**

```bash
git add Scripts/package-app.sh
git commit -m "Add app packaging script: assembles mtats.app with embedded built-in plugins"
```

---

### Task 10: Verification pipeline (smoke test + GLM review loop)

**Files:**
- Create: `Scripts/smoke-test.sh`
- Create: `Scripts/verify.sh`

**Interfaces:**
- Consumes: `.build/mtats.app` from Task 9.
- Produces: a pass/fail smoke test, and a driver script that loops build → smoke test → GLM review until the spec's §8 exit condition holds.

- [ ] **Step 1: Write the functional + performance smoke test**

This can't be a normal XCTest (it launches a real GUI app and inspects process stats), so it's a script per spec §10.

```bash
#!/usr/bin/env bash
# Scripts/smoke-test.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

APP=".build/mtats.app"
LOG=$(mktemp)

open -W -g -n "$APP" --args --smoke-test-exit-after=5 >"$LOG" 2>&1 &
PID=$!
sleep 6

if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAIL: mtats exited early"; cat "$LOG"; exit 1
fi

CPU_PCT=$(ps -p "$PID" -o %cpu= | tr -d ' ')
RSS_KB=$(ps -p "$PID" -o rss= | tr -d ' ')
RSS_MB=$((RSS_KB / 1024))

kill "$PID" 2>/dev/null || true

echo "CPU: ${CPU_PCT}% RSS: ${RSS_MB}MB"

if (( $(echo "$CPU_PCT > 5.0" | bc -l) )); then
  echo "FAIL: CPU usage ${CPU_PCT}% exceeds the budget (spec allows ~1%, failing above 5% to allow for the ps sampling window)"
  exit 1
fi
if (( RSS_MB > 80 )); then
  echo "FAIL: RSS ${RSS_MB}MB exceeds the budget (spec targets ~40-50MB, failing above 80MB)"
  exit 1
fi

echo "PASS"
```

Note: `main.swift` (Task 8) already reads a `--smoke-test-exit-after=N` flag and exits after N seconds — that's what lets this script run the real app without hanging forever.

- [ ] **Step 2: Run the smoke test**

```bash
chmod +x Scripts/smoke-test.sh
Scripts/smoke-test.sh
```

Expected: `PASS`, after printing a CPU/RSS line. If it fails on CPU/RSS, profile which widget's `Timer` is too aggressive before touching anything else — the 1s interval (spec §5) should not come close to 5%/80MB for 4 widgets.

- [ ] **Step 3: Write the GLM review driver**

```bash
#!/usr/bin/env bash
# Scripts/verify.sh
# SPDX-License-Identifier: MIT
set -euo pipefail

echo "== swift build =="
swift build

echo "== swift test =="
swift test

echo "== package app =="
Scripts/package-app.sh

echo "== smoke test =="
Scripts/smoke-test.sh

echo "== GLM review =="
DIFF=$(git diff main --stat; echo; git diff main)
SPEC=$(cat docs/superpowers/specs/2026-10-11-mtats-v1-design.md)
PROMPT="You are reviewing a diff against mtats' v1 spec (attached below). Report ONLY unresolved high-severity findings (correctness bugs, spec violations, crashes) as a numbered list, or the single line NO_FINDINGS if there are none. Be specific: file, line, what's wrong, why it matters against the spec.

=== SPEC ===
$SPEC

=== DIFF ===
$DIFF"

RESULT=$(dsh --profile headless "$PROMPT")
echo "$RESULT"

if echo "$RESULT" | grep -q "NO_FINDINGS"; then
  echo "VERIFICATION PASSED: build clean, tests pass, smoke test passed, GLM found no high-severity issues."
  exit 0
else
  echo "VERIFICATION INCOMPLETE: GLM findings above need fixing, then re-run Scripts/verify.sh."
  exit 1
fi
```

- [ ] **Step 4: Run it end to end**

```bash
chmod +x Scripts/verify.sh
Scripts/verify.sh
```

Expected: either `VERIFICATION PASSED...` (exit 0), or a list of GLM findings to fix before re-running. This is the loop described in spec §8 step 5 — re-run after each fix until it passes, no round cap.

- [ ] **Step 5: Commit**

```bash
git add Scripts/smoke-test.sh Scripts/verify.sh
git commit -m "Add smoke test (perf budget) and GLM-review verification loop driver"
```

---

### Task 11: Example third-party plugin (separate repo) — dogfood proof

**Files:**
- Create (new repo, not in `mtats`): `mtats-example-plugin/PluginMain.swift`, `mtats-example-plugin/Info.plist`, `mtats-example-plugin/README.md`

**Interfaces:**
- Consumes: a copy of the `MTatsPluginKit` build artifact from the `mtats` repo (per ADR-0005, must carry the identical install-name string).

- [ ] **Step 1: Create the separate repo**

```bash
mkdir -p ~/code/mtats-example-plugin
cd ~/code/mtats-example-plugin
git init
gh repo create mtats-example-plugin --public --source=. --remote=origin
```

- [ ] **Step 2: Write the trivial widget**

```swift
// PluginMain.swift
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI
import MTatsPluginKit

@objc(HelloWidget) class HelloWidget: NSObject, Widget {
    let id = "hello-world-example"
    let displayName = "Hello World"
    func start() {}
    func stop() {}
    func menuBarView() -> AnyView { AnyView(Text("👋").font(.system(size: 11))) }
    func detailView() -> AnyView { AnyView(Text("Hello from a genuinely third-party mtats plugin.").padding()) }
}

@objc(HelloPluginMain) public class HelloPluginMain: NSObject, PluginEntry {
    @objc public static func makeWidgets() -> [Widget] { [HelloWidget()] }
}
```

```xml
<!-- Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>HelloWidget</string>
  <key>CFBundleIdentifier</key><string>com.example.mtats-hello-plugin</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>NSPrincipalClass</key><string>HelloPluginMain</string>
  <key>MTatsPluginAPIVersion</key><integer>1</integer>
</dict></plist>
```

- [ ] **Step 3: Build it against the mtats repo's kit artifact, signed with a distinct ad-hoc identity, and drop it into the user plugins directory**

```bash
MTATS_DEBUG=~/code/mtats/.build/debug
mkdir -p HelloWidget.bundle/Contents/MacOS
swiftc -emit-library -module-name HelloPlugin \
  -I "$MTATS_DEBUG" -L "$MTATS_DEBUG" -lMTatsPluginKit \
  PluginMain.swift -o HelloWidget.bundle/Contents/MacOS/HelloWidget \
  -Xlinker -rpath -Xlinker "$MTATS_DEBUG"
cp Info.plist HelloWidget.bundle/Contents/Info.plist
codesign -s - --identifier com.example.mtats-hello-plugin -f HelloWidget.bundle

mkdir -p ~/Library/Application\ Support/mtats/Plugins
cp -R HelloWidget.bundle ~/Library/Application\ Support/mtats/Plugins/
```

Note: this links against the local debug build's absolute path, which is fine for dev-time dogfooding but not how a real third-party developer would do it — ADR-0005's actionable requirement (shipping `MTatsPluginKit` as a frozen, versioned `.xcframework` with a stable install name) is future packaging work, out of scope for this plan. What matters here is proving the loading mechanism itself works from a genuinely separate project.

- [ ] **Step 4: Relaunch `.build/mtats.app` (or confirm the FSEvents watch picks it up live) and verify the 👋 widget appears**

Run: `open ~/code/mtats/.build/mtats.app`
Expected: a 👋 item appears in the menu bar alongside CPU/RAM/GPU/Network. This is the dogfood proof from spec §4.1 — a genuinely separate project, separately signed, loading correctly.

- [ ] **Step 5: Commit both repos**

```bash
cd ~/code/mtats-example-plugin
git add PluginMain.swift Info.plist
echo "# mtats-example-plugin
A trivial 'hello world' third-party plugin for mtats, proving the dynamic plugin loading path works for a genuinely separate project. See https://github.com/marvinmarnold/mtats docs/adr/0001 and 0005." > README.md
git add README.md
git commit -m "Hello-world example plugin proving third-party plugin loading"
git push -u origin main
```

---

### Task 12: Notarized distribution build — BLOCKED pending Apple Developer Program enrollment

Spec §2 lists "notarized" as a v1 goal. Every other task in this plan deliberately avoids needing a paid Apple Developer ID (Global Constraints) — this is the one piece of the spec that genuinely cannot be done without one, since `codesign` with a real Developer ID certificate and `xcrun notarytool` both require an enrolled, paid Apple Developer Program account (not just an Xcode install or a free personal-team signing identity). This is not a task an engineer can execute around; it needs the product owner to enroll first.

**Files:** `Scripts/notarize.sh` (to be created once unblocked).

- [ ] **Step 1: Confirm unblocked**

Requires: an active Apple Developer Program membership, a "Developer ID Application" certificate in the login keychain (`security find-identity -v -p codesigning` should list one, not the zero found at the start of this plan), and an app-specific password or API key for `notarytool` set up per Apple's current instructions.

- [ ] **Step 2: Re-sign with the real identity**

```bash
IDENTITY="Developer ID Application: <Name> (<TeamID>)" # from security find-identity
codesign -s "$IDENTITY" --deep --options runtime \
  --entitlements Scripts/mtats.entitlements -f .build/mtats.app
```

Create `Scripts/mtats.entitlements` with `com.apple.security.cs.disable-library-validation` set to `true` (ADR-0001) — this is the one entitlement the whole dynamic-plugin architecture depends on; omitting it will make third-party plugin loading fail under the hardened runtime even though it worked in every unsigned/ad-hoc-signed dev build so far.

- [ ] **Step 3: Submit for notarization and staple**

```bash
ditto -c -k --keepParent .build/mtats.app .build/mtats.zip
xcrun notarytool submit .build/mtats.zip --keychain-profile "mtats-notary" --wait
xcrun stapler staple .build/mtats.app
```

- [ ] **Step 4: Verify**

```bash
spctl -a -vvv .build/mtats.app
```

Expected: "accepted", "source=Notarized Developer ID".

- [ ] **Step 5: Commit the (now-unblocked) script**

```bash
git add Scripts/notarize.sh Scripts/mtats.entitlements
git commit -m "Add notarization script now that Developer ID enrollment unblocks it"
```

---

## Execution note

This plan is long because the spec demands sellable quality, not a toy. Tasks 1-10 are entirely within the `mtats` repo and don't depend on anything outside the command-line Swift toolchain already confirmed present. Task 11 needs a second repo but reuses everything already built. Task 12 is explicitly blocked on the product owner enrolling in the Apple Developer Program — everything else in this plan is buildable and testable without it. Run `Scripts/verify.sh` (Task 10) after Task 11 too, to catch anything the GLM review would flag about how the third-party path is documented.
