# quick_blue_core

The Quick Blue BLE API for Dart applications without Flutter. It uses the models,
handles and connection state in `quick_blue_platform_interface`.

Flutter consumers continue importing `package:quick_blue/quick_blue.dart`.
Standalone Linux consumers import `package:quick_blue_core/quick_blue_core.dart`
and `package:quick_blue_linux_dart/quick_blue_linux_dart.dart`, then explicitly call
`QuickBlueLinux.registerWith()` before Bluetooth work.

See [matched-source installation and migration](../docs/install.md#standalone-dart-linux)
and [standalone tests](../docs/testing.md#standalone-package-boundary).
Use the same source revision for all repository packages; distribution is
[Git/local only](../docs/install.md#publication-compatibility-limit), not a hosted
release. This package does not export Android/Pigeon
channel code. Companion/accessory APIs remain available; check platform
capabilities before using them.

Standalone consumers require no Flutter SDK, engine or display. BlueZ, system
D-Bus policy and a working adapter are still needed for real Linux BLE operations.
Package tests and consumer builds do not test Bluetooth hardware or ARM64 execution.
