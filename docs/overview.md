---
type: "Reference"
title: "Choose quick_blue"
description: "Understand the federated packages and the handle-based BLE API."
tags: ["architecture", "api"]

sources: [{"id": "source1", "resource": "../pubspec.yaml"}, {"id": "source2", "resource": "../quick_blue_core/lib/src/quick_blue.dart"}, {"id": "source3", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_device.dart"}]
---

# Choose quick_blue

Use Quick Blue for a shared Flutter BLE API on Android, iOS, macOS, Windows,
and Linux. Keep application policy (permissions, timeouts, framing, telemetry)
explicit; use [capabilities](capabilities.md) for platform differences.

## Package map

| Directory | Responsibility |
| --- | --- |
| `quick_blue/` | Flutter reexports, Android channels and Kotlin implementation |
| `quick_blue_core/` | Pure-Dart BLE API using platform-interface state |
| `quick_blue_platform_interface/` | Shared models, handles and lifecycle coordinators |
| `quick_blue_darwin/` | iOS/macOS CoreBluetooth and Swift |
| `quick_blue_linux/` | BlueZ, D-Bus and native L2CAP bindings |
| `quick_blue_windows/` | WinRT and C++ |
| `quick_blue/example/` | Explorer UI and integration tests |

Import `package:quick_blue/quick_blue.dart`. Prefer `QuickBlue.device(id)` and
its characteristic handles over deprecated static connection/GATT methods.
Creating a handle does not scan, connect, or prove that a device exists.[^source3]

Standalone Linux consumers import core and explicitly register Linux; see
[migration and dependency isolation](install.md#standalone-dart-linux).
Flutter and standalone callers share the same platform instance and lifecycle
implementation, not independent connection state.

## Start here

1. [Install all federated packages](install.md).
2. [Configure the target platform](platform-setup.md).
3. [Scan and read a characteristic](quickstart.md).
4. Choose [one-shot or managed connections](connections.md), and handle
   [GATT invalidation](gatt.md).

For repository work, read [maintenance](maintenance.md) and [testing](testing.md).

[^source3]: BluetoothDevice handle contract.
