# quick_blue_linux_dart

Pure-Dart Linux BLE implementation using BlueZ, D-Bus and native L2CAP bindings.
This package has no Flutter SDK requirement or Flutter plugin metadata. It owns
all Linux implementation and lifecycle state; `quick_blue_linux` is the Flutter
registration shell and exports the identical implementation class.

For standalone consumers, import `package:quick_blue_core/quick_blue_core.dart`
and `package:quick_blue_linux_dart/quick_blue_linux_dart.dart`, then call
`QuickBlueLinux.registerWith()` before using `QuickBlue`.

Use [matched Git/local dependencies](../docs/install.md#standalone-dart-linux).
When upgrading from standalone `quick_blue_linux`, change the dependency, override,
Git package path and import to `quick_blue_linux_dart`. Keep the same tested
revision for core/interface/backend; existing pinned consumers are unaffected.
No registry publication or package-name ownership is promised.

See [Linux setup](../docs/platform-setup.md#linux),
[adapter selection](../docs/scanning.md#linux-adapter-selection),
[shutdown](../docs/connections.md#linux-client-shutdown), and the
[operator CLI](../quick_blue_linux/example/README.md).
The D-Bus policy template is `dbus/dev.quick_blue.Connection.conf`; L2CAP requires
`libbluetooth.so.3`. Cooperating clients retain `dev.quick_blue.Connection.*`
leases across both package entry points.

From the repository root, verify a separate Dart SDK and fresh external cache:

    python3 scripts/check-headless-consumer.py --dart /absolute/dart-sdk/bin/dart

This runs analysis, retained lifecycle tests, CLI compilation/help and fake flow,
not physical BLE. In the Flutter workspace, `flutter test` in this package also
runs its fake BlueZ/D-Bus suites. Regenerate native bindings here with
`dart run ffigen --config ffigen.yaml`; do not edit generated bindings manually.
