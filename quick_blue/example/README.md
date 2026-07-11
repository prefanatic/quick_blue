# quick_blue_example

Demonstrates how to use the quick_blue plugin.

## BLE smoke test

The integration smoke test scans for nearby BLE advertisements, tries to connect
to matching devices, discovers services, reads a discovered readable
characteristic, optionally writes a caller-provided characteristic, and
disconnects. It is headless: no manual device picker is shown. Set
`QUICK_BLUE_HIDE_TEST_WINDOW=1` for desktop agent runs that should not show a
visible app window. Run it against any supported Flutter target with Bluetooth
LE hardware and permissions; for example:

```sh
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_smoke_test.dart -d macos

QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_smoke_test.dart -d linux
```

Useful Dart defines:

- `QUICK_BLUE_SMOKE_PROFILE`: built-in smoke profile name. Current profile:
  `valve_lighthouse`, which validates a Valve Lighthouse-style advertisement
  name and skips connect/read by default.
- `QUICK_BLUE_SMOKE_PROFILE_JSON`: custom profile JSON. Fields include
  `deviceId`, `namePattern`, `serviceUuids`,
  `expectedAdvertisedServiceUuids`, `expectedServiceUuids`,
  `expectedManufacturerDataHex`, `expectedServiceDataHex`, `minRssi`,
  `connect`, `read`, and `maxConnectAttempts`. Custom JSON is merged over the
  built-in profile, and explicit Dart defines override profile values.
- `QUICK_BLUE_SMOKE_SCAN_SECONDS`: scan duration before connection attempts
  begin. Defaults to `12`.
- `QUICK_BLUE_SMOKE_MAX_CONNECT_ATTEMPTS`: maximum number of candidates to try.
  Defaults to `3`.
- `QUICK_BLUE_SMOKE_DEVICE_ID`: exact platform device identifier to target.
- `QUICK_BLUE_SMOKE_NAME_PATTERN`: case-insensitive regular expression matched
  against advertised device names.
- `QUICK_BLUE_SMOKE_SERVICE_UUIDS`: comma-separated service UUID scan filter.
- `QUICK_BLUE_SMOKE_EXPECTED_ADVERTISED_SERVICE_UUIDS`: comma-separated service
  UUIDs that must be present in the advertisement.
- `QUICK_BLUE_SMOKE_EXPECTED_SERVICE_UUIDS`: comma-separated GATT service UUIDs
  that must be discovered on the connected target.
- `QUICK_BLUE_SMOKE_EXPECTED_MANUFACTURER_DATA_HEX`: manufacturer data byte
  prefix that must be present in the advertisement.
- `QUICK_BLUE_SMOKE_MIN_RSSI`: minimum advertisement RSSI in dBm.
- `QUICK_BLUE_SMOKE_CONNECT`: set to `false` for advertisement-only profiles.
- `QUICK_BLUE_SMOKE_READ`: set to `false` to skip the readable characteristic
  check after connecting and discovering services.
- `QUICK_BLUE_SMOKE_DUMP_ADVERTISEMENTS`: set to `true` to print matching
  advertisement fields that can be copied into a custom profile.
- `QUICK_BLUE_SMOKE_READ_TIMEOUT_SECONDS`: readable characteristic timeout.
  Defaults to `8`.
- `QUICK_BLUE_SMOKE_WRITE_TIMEOUT_SECONDS`: opt-in write timeout. Defaults to
  `8`.
- `QUICK_BLUE_SMOKE_WRITE_SERVICE_UUID`: service UUID for opt-in write smoke
  testing.
- `QUICK_BLUE_SMOKE_WRITE_CHARACTERISTIC_UUID`: characteristic UUID for opt-in
  write smoke testing.
- `QUICK_BLUE_SMOKE_WRITE_HEX`: hex bytes to write. Separators such as spaces,
  colons, underscores, and dashes are allowed.
- `QUICK_BLUE_SMOKE_WRITE_WITHOUT_RESPONSE`: set to `true` to use write without
  response. Defaults to write with response.

Read smoke testing prefers common readable standard characteristics such as
Generic Access Device Name (`1800/2A00`) and Battery Level (`180F/2A19`) before
falling back to the first discovered readable characteristic. Write smoke
testing is opt-in because there is no universally safe writable BLE
characteristic; provide all write defines only for a known test peripheral.

Example targeted run:

```sh
flutter test integration_test/ble_smoke_test.dart -d macos \
  --dart-define=QUICK_BLUE_SMOKE_NAME_PATTERN='sensor|heart' \
  --dart-define=QUICK_BLUE_SMOKE_MAX_CONNECT_ATTEMPTS=5
```

Example Valve Lighthouse advertisement run:

```sh
flutter test integration_test/ble_smoke_test.dart -d linux \
  --dart-define=QUICK_BLUE_SMOKE_PROFILE=valve_lighthouse
```

Use `xvfb-run` for headless Linux agents:

```sh
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  xvfb-run -a flutter test integration_test/ble_smoke_test.dart -d linux \
    --dart-define=QUICK_BLUE_SMOKE_PROFILE=valve_lighthouse
```

The built-in `valve_lighthouse` profile matches `LHB-*` advertisements and a
Valve Lighthouse manufacturer-data prefix (`00 02`). Example captured
advertisements:

- `CB:48:BE:B2:AC:69` / `LHB-DD207A0C`: `00 02 02 01 00 06 00`
- `F7:CA:86:52:A9:1D` / `LHB-9433D15E`: `00 02 01 01 00 06 00`

Add device-specific values after a scan captures them:

```sh
flutter test integration_test/ble_smoke_test.dart -d linux \
  --dart-define=QUICK_BLUE_SMOKE_PROFILE=valve_lighthouse \
  --dart-define=QUICK_BLUE_SMOKE_DUMP_ADVERTISEMENTS=true
```

Then copy stable fields into a custom profile:

```sh
flutter test integration_test/ble_smoke_test.dart -d linux \
  --dart-define=QUICK_BLUE_SMOKE_PROFILE=valve_lighthouse \
  --dart-define='QUICK_BLUE_SMOKE_PROFILE_JSON={"deviceId":"AA:BB:CC:DD:EE:FF","expectedManufacturerDataHex":"01 02","minRssi":-90}'
```

Example targeted GATT service run:

```sh
flutter test integration_test/ble_smoke_test.dart -d linux \
  --dart-define=QUICK_BLUE_SMOKE_DEVICE_ID='CB:48:BE:B2:AC:69' \
  --dart-define=QUICK_BLUE_SMOKE_EXPECTED_SERVICE_UUIDS='1800,1801,180a' \
  --dart-define=QUICK_BLUE_SMOKE_CONNECT_TIMEOUT_SECONDS=30
```

Example targeted write run:

```sh
flutter test integration_test/ble_smoke_test.dart -d macos \
  --dart-define=QUICK_BLUE_SMOKE_DEVICE_ID='DEVICE_ID' \
  --dart-define=QUICK_BLUE_SMOKE_WRITE_SERVICE_UUID='12345678-1234-5678-1234-56789abcdef0' \
  --dart-define=QUICK_BLUE_SMOKE_WRITE_CHARACTERISTIC_UUID='12345678-1234-5678-1234-56789abcdef1' \
  --dart-define=QUICK_BLUE_SMOKE_WRITE_HEX='01 02 03'
```

Run the same smoke test on Windows through a Dockur Windows VM from the
repository root:

```sh
QUICK_BLUE_WINDOWS_USB_VENDOR_ID=0x0a12 \
QUICK_BLUE_WINDOWS_USB_PRODUCT_ID=0x0001 \
QUICK_BLUE_SMOKE_NAME_PATTERN='sensor|heart' \
  scripts/windows-integration-test.sh
```

The USB vendor and product IDs should identify a Bluetooth adapter that can be
passed through to the Windows guest. The script writes the guest test log to
`.dart_tool/dockur_windows/logs/windows-integration-test.log`. The first
successful setup registers a Windows logon task, so later runs reuse the same
VM and execute the latest generated test script from the shared folder. The
guest keeps a synced NTFS checkout at `C:\quick_blue_workspace\quick_blue` so
Flutter can reuse `.dart_tool` and `build` output between runs. Set
`QUICK_BLUE_WINDOWS_CLEAN_WORKTREE=1` to recreate that checkout without
reinstalling Windows. Without a passed-through or virtualized Bluetooth
adapter, the smoke test fails because Bluetooth is unavailable.

When USB passthrough is requested, Bluetooth availability is required. If the
host USB device node is not writable by the user running Dockur, the script
fails before booting Windows and prints the temporary `setfacl` command needed
for that device. Device node permissions are reset when the adapter is
replugged.

## Android multi-engine connection test

`android_multi_engine_test.dart` starts a second headless Flutter engine in the
example process and registers Quick Blue with it. The primary and secondary
engines attach to the same live GATT connection, issue concurrent service
discoveries through the shared native operation queue, then the secondary
engine detaches and the primary verifies that the physical connection remains
usable.

Run it on a physical Android device against a known connectable peripheral:

```sh
flutter test integration_test/android_multi_engine_test.dart \
  -d ANDROID_DEVICE \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_DEVICE_ID='DEVICE_ID'
```

Keep the Android display awake and grant Nearby devices/Bluetooth permission to
the example app. The test fails rather than skipping when Bluetooth or the
target peripheral is unavailable.

## BLE characteristic benchmark

The characteristic benchmark is hardware-backed and targets a known high-volume
notifying characteristic. It connects to the target, discovers services,
subscribes for a fixed duration or runs serialized write/notification-response
cycles, optionally runs sequential reads, and prints a JSON summary with
notification throughput, byte throughput, inter-arrival latency, optional
sequence gaps, command-response latency, and read latency.

```sh
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_characteristic_benchmark_test.dart -d macos \
    --dart-define=QUICK_BLUE_BENCHMARK_DEVICE_ID='DEVICE_ID' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_SERVICE_UUID='12345678-1234-5678-1234-56789abcdef0' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_CHARACTERISTIC_UUID='12345678-1234-5678-1234-56789abcdef1'
```

Useful Dart defines:

- `QUICK_BLUE_BENCHMARK_DEVICE_ID`: exact platform device identifier to target.
- `QUICK_BLUE_BENCHMARK_NAME_PATTERN`: case-insensitive regular expression
  matched against advertised device names. Use this instead of device ID when
  IDs are unstable.
- `QUICK_BLUE_BENCHMARK_SCAN_SERVICE_UUIDS`: comma-separated service UUID scan
  filter. Defaults to no scan service filter.
- `QUICK_BLUE_BENCHMARK_NOTIFY_SERVICE_UUID`: required notifying service UUID.
- `QUICK_BLUE_BENCHMARK_NOTIFY_CHARACTERISTIC_UUID`: required notifying
  characteristic UUID.
- `QUICK_BLUE_BENCHMARK_USE_INDICATIONS`: set to `true` to benchmark
  indications instead of notifications.
- `QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_COMMAND_HEX`: optional hex command to
  write after notifications are enabled. When set, the benchmark writes the
  command sequentially and waits for the next notification after each write.
- `QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_SERVICE_UUID`: optional writable service
  UUID. If omitted, the benchmark writes the notifying characteristic when it is
  writable.
- `QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_CHARACTERISTIC_UUID`: optional writable
  characteristic UUID.
- `QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_ITERATIONS`: serialized write/notification
  cycle count. Defaults to `1`.
- `QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_TIMEOUT_SECONDS`: per-command notification
  response timeout. Defaults to `5`.
- `QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_DELAY_MILLISECONDS`: delay between
  serialized command writes. Defaults to no delay.
- `QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_WITHOUT_RESPONSE`: set to `false` to write
  with response. Defaults to `true`.
- `QUICK_BLUE_BENCHMARK_DURATION_SECONDS`: notification sampling duration.
  Defaults to `30`.
- `QUICK_BLUE_BENCHMARK_READ_SERVICE_UUID`: optional readable service UUID. If
  omitted, the benchmark reads the notifying characteristic when it is readable.
- `QUICK_BLUE_BENCHMARK_READ_CHARACTERISTIC_UUID`: optional readable
  characteristic UUID.
- `QUICK_BLUE_BENCHMARK_READ_ITERATIONS`: sequential read count. Defaults to
  `100`.
- `QUICK_BLUE_BENCHMARK_READ_DELAY_MILLISECONDS`: delay between sequential
  reads. Defaults to no delay.
- `QUICK_BLUE_BENCHMARK_SEQUENCE_OFFSET`: optional byte offset for a monotonic
  packet sequence number in notification payloads. When set, the benchmark
  reports sequence gaps and duplicate or reordered packets.
- `QUICK_BLUE_BENCHMARK_SEQUENCE_WIDTH_BYTES`: sequence width, one of `1`, `2`,
  or `4`. Defaults to `2`.
- `QUICK_BLUE_BENCHMARK_SEQUENCE_LITTLE_ENDIAN`: set to `false` for big-endian
  sequence values. Defaults to `true`.

The benchmark fails when Bluetooth is unavailable. It skips when the target
device or required notifying characteristic is not configured or not found.

SwitchBot Meter-style command/notification response benchmark:

```sh
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_characteristic_benchmark_test.dart -d linux \
    --dart-define=QUICK_BLUE_BENCHMARK_DEVICE_ID='D1:B4:29:F5:B8:7D' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_SERVICE_UUID='cba20d00-224d-11e6-9fb8-0002a5d5c51b' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_CHARACTERISTIC_UUID='cba20003-224d-11e6-9fb8-0002a5d5c51b' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_SERVICE_UUID='cba20d00-224d-11e6-9fb8-0002a5d5c51b' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_CHARACTERISTIC_UUID='cba20002-224d-11e6-9fb8-0002a5d5c51b' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_COMMAND_HEX='570f31' \
    --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_WRITE_ITERATIONS=50
```

## Device-switch regressions

The example also includes regression tests for switching devices while a
connection attempt is still pending. These tests are hardware-backed and skip
when Bluetooth is unavailable, permission is denied, or the target platform is
not supported by the test.

```sh
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/macos_ble_switch_test.dart -d macos

QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_ui_switch_test.dart -d macos

flutter test integration_test/ble_ui_switch_test.dart -d linux
```

Useful Dart defines:

- `QUICK_BLUE_SWITCH_FIRST_NAME_PATTERN`: case-insensitive regular expression
  for the device that should be abandoned while connecting. Defaults to `govee`.
- `QUICK_BLUE_SWITCH_SECOND_NAME_PATTERN`: case-insensitive regular expression
  for the device that should connect after backing out. Defaults to
  `nest\s*hub|nesthub`.
- `QUICK_BLUE_SWITCH_SCAN_SECONDS`: scan duration used to find both devices.
- `QUICK_BLUE_SWITCH_DELAY_MILLISECONDS`: delay between starting the first
  connection and switching devices.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
