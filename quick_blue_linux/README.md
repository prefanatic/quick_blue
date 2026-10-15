# quick_blue_linux

The Linux BlueZ implementation of the `quick_blue` federated Flutter plugin.

Also usable with standalone Dart through `quick_blue_core`, with explicit
`QuickBlueLinux.registerWith()` registration and no Flutter SDK or engine.
See the [matched-source migration recipe](../docs/install.md#standalone-dart-linux).
Flutter's generated registration remains supported through federated plugin
metadata. Package/fake tests do not prove hardware or ARM64 deployment.

The [pure-Dart operator CLI](example/README.md) lists/selects adapters, scans with
a service filter and requires an exact discovered device selection. Pairing,
reads, writes and notifications are explicit opt-ins with `finally` cleanup.
Unlike normal library recovery, it never pairs automatically after a security
error. See [external agent lifecycle](../docs/pairing.md#headless-linux-agent-lifecycle)
and [service-user permissions](../docs/platform-setup.md#linux-service-account-permissions).

Follow the main package's
[Git installation instructions](https://github.com/prefanatic/quick_blue/blob/master/quick_blue/README.md#install)
to use this implementation from the fork.

See the [QuickBlue repository](https://github.com/prefanatic/quick_blue) for
usage, platform setup, and development documentation.

## Requirements

- A running BlueZ daemon and a working BLE adapter; service-user access to the
  system bus and authorized `org.bluez` method calls (not implied by name ownership).
- A D-Bus system-bus policy that lets the application user own names under
  `dev.quick_blue.Connection.*`. Without it every `connect()` fails with
  `Request to own name refused by policy`; install the supplied template:

  ```sh
  sed "s/RUN_AS_USER/$USER/" dbus/dev.quick_blue.Connection.conf \
    | sudo tee /usr/share/dbus-1/system.d/dev.quick_blue.Connection.conf >/dev/null
  sudo systemctl reload dbus-broker   # or: sudo systemctl restart dbus
  ```

- `libbluetooth.so.3` (installed with BlueZ runtime libraries) for L2CAP
  sockets; `QuickBlue.capabilities().supportsL2capSockets` reports support
  regardless, and `openL2cap` fails with an error when the library is absent.

## Adapter selection and shutdown

`QuickBlueLinux(adapterAddress: '02:00:00:00:00:01')` selects that exact
BlueZ adapter address. Omit it for the first powered adapter. `await
platform.adapters()` lists immutable address/power snapshots without powering
an adapter. A missing or unpowered selection never falls back.
See [selection](../docs/scanning.md#linux-adapter-selection).

Cancel public scan, Bluetooth-state, managed-connection and notification
subscriptions and await outstanding requests before `await platform.close()`.
Close is idempotent, disconnects only this client's owned devices using the
last-client lease rule, and makes the instance unusable. Initialization failure
also makes it unusable; create a fresh instance. See
[cleanup contracts](../docs/connections.md#linux-client-shutdown).

## Tests

```sh
python3 ../scripts/check-headless-consumer.py --dart /absolute/dart-sdk/bin/dart
```

Run this from the package directory with a standalone Dart 3.13 SDK. It creates
external matched-source copies, runs `dart test`/analysis and compiles the CLI
plus controlled fake flow. It does not access hardware. `flutter test` remains
usable in the development workspace; it is not standalone dependency proof.

Hardware-backed BLE behaviour can be exercised by the Flutter example app's integration test
(the Linux package exercises fake BlueZ/D-Bus contracts, not hardware):

```sh
cd ../quick_blue/example
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  xvfb-run -a flutter test integration_test/ble_smoke_test.dart -d linux
```
