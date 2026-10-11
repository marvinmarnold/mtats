# Dynamic plugin loading for all Widgets, including built-ins

Every Widget — the 4 v1 built-ins (CPU/RAM/GPU/Network) and any future third-party one — is exposed by a Plugin (`.bundle`) loaded at runtime by the Host via `Bundle(path:).load()` and a `principalClass`, rather than compiled directly into the Host. We considered compiling built-ins directly into the Host (simpler, zero loading risk) and rejected it because it would leave the dynamic loading path — the part third-party plugins actually depend on — untested by the app's own real usage. Loading third-party-signed code requires the Host to carry `com.apple.security.cs.disable-library-validation` in its hardened-runtime entitlements; the Host still requires every Plugin (built-in or third-party) to carry a valid code signature via `SecStaticCodeCheckValidity` and rejects unsigned bundles outright, and shows a one-time warning naming the signing identity before loading any plugin from the user-writable plugins directory.

## Consequences

- The riskiest, least-proven part of the system (dynamic loading + hardened runtime) sits in the critical path of every widget from day one, not just future third-party ones.
- A valid signature is necessary but not sufficient for safety — a signed plugin is still arbitrary code running with the Host's privileges. v1 deliberately does not attempt notarization checks, an allow/deny list, or sandboxing of plugins; that's a real future problem, not solved here.
