## Unreleased

- Map BlueZ authorization failures into cross-platform security recovery.
- Apply service-data UUID and payload-prefix filters to scan results.
- Share BlueZ connections across Flutter engines using serialized per-engine
  D-Bus memberships, and disconnect physically only after the final client.

## 0.5.0 - 2026-07-10

- Retain `isInitialized` as a deprecated read-only compatibility getter so
  callers cannot mutate internal lifecycle state.
- Add a self-contained strict analyzer configuration.
- Report MTU requests as unsupported instead of returning an unverified value.
- Make initialization single-flight and route asynchronous cleanup failures to
  logging handlers.
- Accept advertisements whose RSSI equals the configured minimum threshold.
- Bring the BlueZ implementation up to the current QuickBlue API.
- Add Bluetooth state, scan filters, service data, connected devices, pairing,
  service discovery, and characteristic operations.
- Improve repeated scanning, characteristic lookup, and notification
  throughput.
