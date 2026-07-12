## [0.5.0] - 2026-07-10

### Fixed

- Reject overlapping connect and disconnect operations for the same device so
  a native failure event cannot complete the wrong caller.
- Keep notification and service-discovery coordinators reusable after setup,
  teardown, or discovery failures.
- Give every publishable workspace package a self-contained strict analyzer
  configuration.
- Make Linux initialization state read-only to callers while retaining the
  compatibility getter.
- Share native characteristic notification ownership across concurrent Dart
  listeners and disable updates only after the final listener cancels.
- Coalesce concurrent service-discovery requests for the same device.
- Report Linux MTU requests as unsupported instead of returning the requested
  value as though it had been negotiated.
- Align Linux RSSI threshold equality with the shared scan filter behavior and
  make Linux initialization and asynchronous cleanup race-safe.
- Prevent a non-owning Linux Flutter engine from disconnecting another engine's
  BlueZ connection, and release ownership after unexpected disconnects.
- Report failed Darwin connection attempts as disconnected connection events
  with a failure status.
- Complete failed Android characteristic reads with an error instead of leaving
  Dart waiting indefinitely for a value event.
- Snapshot and route queued Android discovery and MTU results to the requesting
  Flutter engine so concurrent engines cannot clear or consume each other's
  results.
- Replay the latest available `bluetoothStateStream` state to every new
  listener and support concurrent Bluetooth state listeners consistently across
  platforms.

### Added

- Share one Android GATT connection across Flutter engines with per-engine
  attachment lifecycles, multicast native events, serialized GATT operations,
  and cross-engine notification reference counting.
- Add a physical-device Android integration test that attaches two Flutter
  engines to one GATT and verifies concurrent discovery and independent detach.
- Add process-wide per-device connection ownership across Flutter engines on
  Android, iOS, macOS, Linux, and Windows, with deterministic `deviceBusy`
  errors and opt-in bounded waiting for reconnecting handoffs.
- Add `QuickBlueGattException` with the raw numeric native GATT status for
  Android read, write, and notification-configuration failures.
- Add Android `bondStateStream` events and race-safe `waitForBondState()` APIs.
- Add Dart-shaped device and characteristic APIs, including `QuickBlue.device`,
  `BluetoothDevice`, and `BluetoothCharacteristic`.
- Add `BluetoothDevice.discoverGatt()` for resolving characteristics from
  discovered services by characteristic UUID.
- Add `BluetoothGatt.hasCharacteristic()` for checking discovered GATT features
  without handling lookup exceptions.
- Add `BluetoothCharacteristic.setNotifiable()` for explicit notification or
  indication lifecycle control.
- Add lifecycle-managed `scan()` and `scanResults()` streams that start scanning
  on listen and stop scanning on cancel.
- Add `bluetoothStateStream` with an initial current-state event, live Android,
  iOS, macOS, and Linux state updates, and snapshot fallback behavior for other
  platforms.
- Add `BlueScanResult.serviceData` and platform support for Android and Darwin.
- Add characteristic property metadata through
  `BluetoothService.characteristicDetails`.
- Add `serviceId` to `BluetoothCharacteristicValue` so characteristic value
  events are scoped by device, service, and characteristic.
- Add cross-platform hardware smoke testing for scan/connect/service discovery
  flows.
- Add hardware smoke-test coverage for reading discovered characteristics and
  opt-in writes against known test peripherals.
- Add `QUICK_BLUE_HIDE_TEST_WINDOW` desktop runner support for agent-friendly
  integration test runs.
- Add macOS regression tests for switching devices while a connection attempt is
  still pending.
- Add cross-platform explorer UI regression coverage for switching away from a
  pending device connection on macOS and Linux.
- Add broader Dart API, Android wrapper, Darwin wrapper, and model test
  coverage.
- Add `QuickBlue.companion` with typed companion association requests,
  associations, and support checks.
- Add `ScanFilter.rssi` and `ScanOptions` for common and platform-specific scan
  settings on Android, Darwin, Linux, and Windows.
- Add `QuickBlue.connectedDevices()` for retrieving already connected device
  handles.
- Add `QuickBlue.configure(maintainState: true)` to opt iOS and macOS into
  CoreBluetooth state preservation and restoration.
- Add `BluetoothDevice.bondState()` and `BluetoothDevice.pair()` with Android
  and Linux pairing/bonding support.
- Add a hardware-backed example benchmark for characteristic notification
  throughput and read latency.
- Add serialized write/notification-response coverage to the characteristic
  benchmark for command/notify devices.
- Add GitHub Actions CI updates and local `act` configuration.
- Add repository contributor instructions.

### Changed

- Deprecate remaining static device and GATT operation wrappers in favor of
  `QuickBlue.device(deviceId)` and characteristic object APIs.
- Reuse platform scan result event streams instead of rebuilding mapped streams
  on each `scanResultStream` access.
- Align static `QuickBlue` methods with the device object API.
- Leave operation timeouts to clients through normal `Future.timeout`
  composition.
- Make scan result lifecycle handling deterministic when multiple listeners use
  the same filter.
- Make platform-interface models value-like, with defensive copies for mutable
  byte and collection fields.
- Order notification setup so values are forwarded only after notification
  enabling succeeds.
- Complete Android `setNotifiable` calls only after the descriptor write is
  acknowledged.
- Await connection and disconnection state events in the device API.
- Tighten operation error handling for connection, disconnection, service
  discovery, reads, writes, and notifications.
- Update SDK constraints, workspace configuration, generated Pigeon output, and
  package versions for the current toolchain.
- Enable Swift Package Manager support for the Darwin package.
- Consolidate licensing at the repository root.
- Rework the example app into a BLE explorer with stable discovery ordering,
  live Bluetooth state, responsive device detail navigation, and focused
  characteristic controls.
- Refresh the example app platform projects and Bluetooth permissions used for
  manual BLE verification.
- Update README coverage for current stream/device APIs, Linux GATT support,
  characteristic metadata, and service-scoped values.
- Bring the Linux implementation up to the current Dart surface with live
  Bluetooth state, scan filters, and service data in scan results.
- Route characteristic value streams directly by characteristic to reduce
  high-throughput notification overhead.
- Return Linux characteristic read results directly.
- Replace the companion-device platform contract with association-specific
  models and deprecate the older static companion methods.
- Retire the legacy `MethodChannelQuickBlue` fallback from the platform
  interface; federated platform packages now provide the runtime
  implementations.
- Migrate Android Gradle configuration to Flutter's built-in Kotlin support.

### Fixed

- Apply Android BLE companion association manufacturer-data filters instead of
  accepting them on Dart and dropping them in Kotlin.
- Complete Android and Darwin writes after the platform reports the
  characteristic write result.
- Surface Android descriptor write failures and missing BLE scan/connect
  permissions as Flutter errors.
- Preserve pending Android and Darwin write failures when a peripheral
  disconnects before acknowledgement.
- Fix example connection switching so abandoning a pending connection does not
  block connecting another device.
- Reset pending example device actions when selecting a different device.
- Preserve stable example discovery ordering and the last non-empty advertised
  device name as scan results update.
- Replay known Linux BlueZ devices after scan startup so repeated scans surface
  nearby advertisers that BlueZ already discovered.
- Collect service discovery events before completion so Linux service discovery
  returns the full resolved BlueZ service list.
- Remove redundant manual Bluetooth status refresh from the example; the example
  now relies on `bluetoothStateStream`.
- Fix example `ExpansionTile` / `ListTile` material wrapping assertions.

## [0.5.0-dev.2] - 2022.6.3

- Update federated plugins' versions

## [0.5.0-dev.0] - 2022.5.18

- Fix discoverServices on Windows
- Fix TRANSPORT_LE on Android
- [BREAKING CHANGE] Add characteristics to OnServiceDiscoverd callback
- Add option to change platform instance

## [0.4.1+1] - 2022.3.22

- Add `manufacturerDataHead` & Refactor `manufacturerData` in BlueScanResult

## [0.4.1] - 2022.3.21

- Add `setLogger`

## [0.4.0+1] - 2022.3.21

- Add API compatibility table to README

## [0.4.0] - 2022.3.21

- Add limited Linux support via quick_blue_linux
- Workaround empty device name on Windows

## [0.3.1+3] - 2022.3.20

- Fix missing `deviceId` in `characteristicValue` message on iOS/macOS

## [0.3.1+2] - 2022.3.10

- Fix README with `readValue`

## [0.3.1+1] - 2022.3.10

- Add `readValue` for Android/iOS/macOS/Windows
- Fix missing writeOptions on Windows

## [0.3.0-dev.0] - 2022.3.3

- Migerate to Null-Safety

## [0.2.0] - 2020.11.22

Add for Android/iOS/macOS/Windows
- `connect` & `disconnect`
- `onConnectionChanged`
- `discoverServices`
- `onServiceDiscovered`
- `writeValue`
- `setNotifiable`
- `onValueChanged`

## 0.1.1+1 - 2020.11.18

* Add `scanResultStream` to README.md

## 0.1.1 - 2020.11.17

* Add `scanResultStream` for Android/iOS/macOS/Windows

## 0.1.0 - 2020.11.11

* Add `startScan` & `stopScan` for Android/iOS/macOS/Windows
