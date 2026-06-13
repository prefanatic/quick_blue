# quick_blue_example

Demonstrates how to use the quick_blue plugin.

## BLE smoke test

The integration smoke test scans for nearby BLE advertisements, tries to connect
to matching devices, discovers services, and disconnects. It is headless: no
manual device picker is shown. Set `QUICK_BLUE_HIDE_TEST_WINDOW=1` for desktop
agent runs that should not show a visible app window. Run it against any
supported Flutter target with Bluetooth LE hardware and permissions; for
example:

```sh
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_smoke_test.dart -d macos

QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_smoke_test.dart -d linux
```

Useful Dart defines:

- `QUICK_BLUE_SMOKE_SCAN_SECONDS`: scan duration before connection attempts
  begin. Defaults to `12`.
- `QUICK_BLUE_SMOKE_MAX_CONNECT_ATTEMPTS`: maximum number of candidates to try.
  Defaults to `3`.
- `QUICK_BLUE_SMOKE_DEVICE_ID`: exact platform device identifier to target.
- `QUICK_BLUE_SMOKE_NAME_PATTERN`: case-insensitive regular expression matched
  against advertised device names.
- `QUICK_BLUE_SMOKE_SERVICE_UUIDS`: comma-separated service UUID scan filter.

Example targeted run:

```sh
flutter test integration_test/ble_smoke_test.dart -d macos \
  --dart-define=QUICK_BLUE_SMOKE_NAME_PATTERN='sensor|heart' \
  --dart-define=QUICK_BLUE_SMOKE_MAX_CONNECT_ATTEMPTS=5
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
