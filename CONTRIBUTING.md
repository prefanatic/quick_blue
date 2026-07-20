# Contributing to quick_blue

This repository is a Dart workspace for a federated Flutter plugin. Preserve
the package boundaries: shared APIs and models belong in
`quick_blue_platform_interface`, while platform behavior belongs in the owning
platform package.

## Set up and analyze

Run dependency setup from the repository root:

```sh
flutter pub get
```

Format touched Dart files and run static analysis:

```sh
dart format .
flutter analyze
```

Run the package-focused tests relevant to the change:

```sh
cd quick_blue_platform_interface && flutter test
cd quick_blue_darwin && flutter test
cd quick_blue/example && flutter test
```

## Hardware-backed integration tests

Changes to scanning, connections, service discovery, reads, writes,
notifications, device switching, or platform Bluetooth behavior require a
hardware-backed test when the target host and BLE hardware are available.

From `quick_blue/example`, run the cross-platform smoke test on the affected
target. For example:

```sh
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_smoke_test.dart -d macos

QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  xvfb-run -a flutter test integration_test/ble_smoke_test.dart -d linux
```

The smoke test requires Bluetooth permission, powered-on Bluetooth hardware,
and nearby advertisements. It includes service discovery and read coverage;
writes are opt-in because there is no universally safe writable
characteristic. See
[`quick_blue/example/README.md`](quick_blue/example/README.md) for device
profiles and all supported Dart defines.

The example also includes focused UI, multi-engine, and performance tests:

```sh
flutter test integration_test/ble_ui_switch_test.dart -d macos

flutter test integration_test/android_multi_engine_test.dart -d ANDROID_DEVICE \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_DEVICE_ID='DEVICE_ID'

flutter test integration_test/ios_multi_engine_test.dart -d IOS_DEVICE \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_DEVICE_ID='DEVICE_UUID' \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_SERVICE_UUID='SERVICE_UUID' \
  --dart-define=QUICK_BLUE_MULTI_ENGINE_CHARACTERISTIC_UUID='CHARACTERISTIC_UUID'

flutter test integration_test/ble_characteristic_benchmark_test.dart -d macos \
  --dart-define=QUICK_BLUE_BENCHMARK_DEVICE_ID='DEVICE_ID' \
  --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_SERVICE_UUID='SERVICE_UUID' \
  --dart-define=QUICK_BLUE_BENCHMARK_NOTIFY_CHARACTERISTIC_UUID='CHARACTERISTIC_UUID'
```

### Windows VM smoke test

Run the Windows smoke test through Dockur from the repository root:

```sh
QUICK_BLUE_WINDOWS_USB_VENDOR_ID=0x0bda \
QUICK_BLUE_WINDOWS_USB_PRODUCT_ID=0x8771 \
  scripts/windows-integration-test.sh
```

The script starts `dockurr/windows`, passes through the selected USB Bluetooth
adapter, and runs the example smoke test on Windows. VM state persists under
`.dart_tool/dockur_windows/`, and the guest reuses
`C:\quick_blue_workspace\quick_blue` for Flutter build caches.

Set `QUICK_BLUE_WINDOWS_CLEAN_WORKTREE=1` to refresh the guest checkout without
reinstalling Windows. Use `QUICK_BLUE_WINDOWS_RESET=1` only when the VM disk
must be rebuilt.

## Generated Pigeon code

Pigeon schemas and generated bindings must stay synchronized. Do not hand-edit
generated `messages.g.*` files.

For the Android/main plugin:

```sh
cd quick_blue
dart run pigeon --input pigeons/messages.dart
```

For iOS and macOS:

```sh
cd quick_blue_darwin
dart run pigeon --input pigeons/messages.dart
```

For Windows:

```sh
cd quick_blue_windows
dart run pigeon --input pigeons/messages.dart
```

Inspect the resulting generated-file diff before submitting the change.
