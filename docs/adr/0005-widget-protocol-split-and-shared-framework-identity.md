# Widget/MetricsSource split; MTatsPluginKit loads as one shared image

`Widget` (crosses the Plugin↔Host seam, no associated types, views returned as `AnyView`) is split from `MetricsSource` (an internal-only, per-concrete-widget protocol with an associated `Snapshot` type, never exposed to the Host) so that presentation logic is unit-testable with canned data independent of real sensor reads. `Widget` gains explicit `start()`/`stop()` so the Host can honor per-widget enable/disable (spec §6) without destroying Plugin state. We rejected a single combined protocol (simpler on paper) because it gave the Host no lifecycle hook and forced every concrete widget to make its view logic hardware-dependent to test.

Separately: `MTatsPluginKit` must be loaded as exactly one shared image per process. The Host loads it first at launch; third-party Plugin bundles link against it weakly (two-level-namespace lookup) rather than embedding their own copy, so Swift runtime type identity for `Widget` stays consistent across the Host and every Plugin. A Plugin bundle carrying its own copy of the framework is expected to produce silent protocol-conformance failures or crashes, not a clean error — this must be verified directly in the feasibility spike (plan Task 1), since it's the real risk in ADR-0001, not merely "does a differently-signed bundle load."

## Consequences

- `Snapshot` is not part of `MTatsPluginKit`'s public surface — it's internal to each concrete widget's own `MetricsSource` implementation. The Host never sees widget-specific data types, only `Widget`'s views and lifecycle methods.
- The exact `principalClass`/Obj-C-runtime bridging mechanics for `Plugin`'s entry point are intentionally left to the feasibility spike rather than specified here — that's what the spike exists to determine.
