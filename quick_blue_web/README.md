# quick_blue_web

Federated Web Bluetooth implementation for Quick Blue. Apps depend on
`quick_blue`, which endorses this package for web registration.

Use `QuickBlue.requestDevice` directly from a click/tap handler; chooser results
are authorized device handles, not raw scan advertisements. Declare needed
services up front. Native scanning, bonding, MTU, L2CAP and system-connected
lookup are unsupported.

See the [canonical browser guide](../docs/web.md) for browser/security limits,
architecture, executable Chrome simulator tests and safe hardware verification.

From the workspace root:

    flutter pub get
    (cd quick_blue_web && flutter test --platform chrome)

These tests exercise JS interop in Chrome with simulated Bluetooth objects;
they are not radio or permission-UI evidence.
