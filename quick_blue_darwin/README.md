# quick_blue_darwin

The iOS and macOS CoreBluetooth implementation of the `quick_blue` federated
Flutter plugin.

Follow the main package's
[Git installation instructions](https://github.com/prefanatic/quick_blue/blob/master/quick_blue/README.md#install)
to use this implementation from the fork.

See the [QuickBlue repository](https://github.com/prefanatic/quick_blue) for
usage, platform setup, and development documentation.

## Layout

- `darwin/quick_blue_darwin/` is the Swift package backing both the podspec and
  Swift Package Manager consumers.
- `darwin/quick_blue_darwin/connection_ownership/` and
  `darwin/quick_blue_darwin/restoration_summary/` are self-contained helper
  packages with their own Swift tests.

## Requirements

- iOS 13 or later, or macOS 10.15 or later.
- Bluetooth usage descriptions in the host app's `Info.plist`.
- Optional CoreBluetooth state restoration: set the boolean `Info.plist` key
  `QuickBlueCoreBluetoothStateRestorationEnabled` to `true` to create
  CoreBluetooth during native plugin registration, before Dart starts.

## Smoke test

```sh
cd ../quick_blue/example
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  flutter test integration_test/ble_smoke_test.dart -d macos
```

Helper-package Swift tests run with
`swift test --package-path darwin/quick_blue_darwin/connection_ownership` (and
the same for `restoration_summary`). The native harness also tests write limits,
readiness, queue order, and cleanup against framework stubs:

```sh
./darwin/quick_blue_darwin/type_check/run.sh
```

These tests do not prove CoreBluetooth behavior on hardware.
