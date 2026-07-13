## Unreleased

- Apply service-data UUID and payload-prefix filters to raw scan results.
- Resolve CoreBluetooth-known device UUIDs during connect so a new engine does
  not need to scan or query connected peripherals before attaching.
- Defer final engine-detach cleanup by one main-queue turn so a concurrently
  starting engine can attach to the existing CoreBluetooth host.
- Share one CoreBluetooth connection across Flutter engines, multicast native
  connection and GATT events, and keep the physical connection alive until the
  final engine detaches.
- Publish each plugin instance so headless Flutter engine destruction releases
  its native connection attachment.

## 0.5.0 - 2026-07-10

- Add the shared iOS and macOS federated implementation.
- Add Bluetooth state, scan filtering, service data, connected-device lookup,
  and lifecycle-managed GATT operations.
- Add opt-in CoreBluetooth state preservation and restoration.
- Report connection and characteristic-operation failures to Dart.
- Add Swift Package Manager support.
