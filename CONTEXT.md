# mtats

A native macOS menu bar system-monitor utility (iStat Menus-style), built around a real dynamic plugin system so that every widget — built-in or third-party — loads the same way.

## Language

**Host**:
The `mtats.app` process. Owns the status bar items, discovers and loads Plugins, schedules polling, and renders each Widget a Plugin exposes.
_Avoid_: App, main app, core

**Plugin**:
A loadable unit of code (an on-disk `.bundle`) that the Host loads at runtime via its principal class. A Plugin's only job is to expose one or more Widgets.
_Avoid_: Module, extension, widget (a Plugin is the code unit; a Widget is what it exposes — see below)

**Built-in plugin**:
A Plugin shipped inside the Host's own app bundle and signed with the same Team ID as the Host. The 4 v1 capabilities (CPU, RAM, GPU, Network) are Built-in plugins, loaded through the exact same mechanism as Third-party plugins.
_Avoid_: Core widget, native widget

**Third-party plugin**:
A Plugin installed by the user into the Host's user-writable plugins directory, potentially signed by a different Team ID (or unsigned). Loading one requires the Host to disable library validation, which is a real trust boundary, not just a code path.
_Avoid_: External plugin, add-on

**Widget**:
A single monitoring capability a Plugin exposes to the Host: a menu-bar presentation (sparkline/number) plus a dropdown detail view, backed by its own polling logic. One Plugin may expose more than one Widget architecturally, though every v1 Plugin exposes exactly one.
_Avoid_: Plugin (see above), sensor, monitor

**Snapshot**:
An immutable, timestamped reading produced by a Widget's polling logic (e.g. a CPUSnapshot carrying per-core and total usage). The Host and the Widget's own views both consume Snapshots; neither polls hardware directly.
_Avoid_: Reading, sample, metric (metric is fine as a general term for "the thing being measured," but the data point itself is a Snapshot)
