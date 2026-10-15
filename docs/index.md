---
okf_version: "0.2"
---

# Quick Blue knowledge bundle

## Start here

- [Choose quick_blue](overview.md) - Understand the federated packages and the handle-based BLE API.
- [Install from Git](install.md) - Use a consistent repository revision for every federated package.
- [Configure each platform](platform-setup.md) - Set permissions, entitlements and host policy before using Bluetooth.
- [Scan, connect and read](quickstart.md) - Run a small read-only workflow with explicit cleanup and caller timeouts.

## Device workflows

- [Scan results and filters](scanning.md) - Own scanning through subscriptions and select portable or native scan controls.
- [Connection lifetimes and retries](connections.md) - Choose one-shot or subscription-owned connections and handle overlapping operations.
- [Discover, write and subscribe](gatt.md) - Use valid GATT snapshots, opt-in snapshot-bound handles, explicit write framing and subscription-owned notifications.
- [Share a connection across engines](multi-engine.md) - Attach the receiving engine before detaching the previous owner.
- [Pairing and security failures](pairing.md) - Gate bonding APIs and handle coordinated security recovery without blind retries.
- [Open an L2CAP socket](l2cap.md) - Use the socket event stream and sink with explicit platform and framing checks.

## Platform and diagnostics reference

- [Runtime capability matrix](capabilities.md) - Gate optional APIs using modes rather than assuming uniform platform support.
- [Android companion association](android.md) - Keep companion UI separate from BLE connections and check OS support.
- [Darwin restoration and accessory setup](darwin.md) - Choose a restoration-first or AccessorySetupKit-first startup flow.
- [Observe operations without leaking device data](observability.md) - Adapt typed operation lifecycles to telemetry and redact sensitive context.
- [Known boundaries and pitfalls](limitations.md) - Distinguish implemented support from runtime readiness and hardware evidence.

## Repository work

- [Use the BLE explorer and test profiles](example-app.md) - Exercise device workflows and choose an integration test that proves the intended behavior.
- [Integration-test Dart defines](example-options.md) - Look up compile-time test inputs and their source defaults.
- [Verify repository changes](testing.md) - Select package, native and hardware checks and record precise evidence.
- [Maintain the knowledge bundle](maintenance.md) - Read relevant source docs before work and update and verify them with every behavior change.
