# quick_blue_core

The pure-Dart generic Quick Blue BLE facade. Models, handles, lifecycle
coordinators and the platform instance remain authoritative in
`quick_blue_platform_interface`; this package adds no duplicate connection state.

Flutter consumers continue importing `package:quick_blue/quick_blue.dart`.
Standalone Linux consumers import `package:quick_blue_core/quick_blue_core.dart`
and `package:quick_blue_linux/quick_blue_linux.dart`, then explicitly call
`QuickBlueLinux.registerWith()` before Bluetooth work.

See [matched-source installation and migration](../docs/install.md#standalone-dart-linux)
and [standalone verification](../docs/testing.md#standalone-package-boundary).
Use the same source revision for all repository packages. Android/Pigeon channel
code is deliberately not exported here; generic companion/accessory delegates
remain available and use the platform's capability/unsupported contracts.

Standalone consumers require no Flutter SDK, engine or display. BlueZ, system
D-Bus policy and a working adapter are still needed for real Linux BLE operations.
Package tests and external consumer builds are not hardware or ARM64 acceptance.
