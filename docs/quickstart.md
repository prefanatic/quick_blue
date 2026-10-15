---
type: "Playbook"
title: "Scan, connect and read"
description: "Run a small read-only workflow with explicit cleanup and caller timeouts."
tags: ["getting-started", "scan", "gatt"]

sources: [{"id": "source1", "resource": "../quick_blue_core/lib/src/quick_blue.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_device.dart"}, {"id": "source3", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_characteristic.dart"}]
---

# Scan, connect and read

First complete [platform setup](platform-setup.md). Device identifiers are
platform-specific; do not assume that an Android address is a CoreBluetooth UUID.

## Headless Linux operator workflow

Build the [external standalone CLI fixture](install.md#operator-cli-fixture),
then enter the retained fixture's `cli/` directory. The source is
`quick_blue_linux/example/` relative to the repository root.
`--help` does not open D-Bus; `--list-adapters` does. List adapter addresses,
run a service-filtered scan, then repeat with `--device` set to the exact ID
chosen by the operator. The CLI requires that device to reappear in the current
filtered scan, connects and discovers GATT through `QuickBlue.device`, and
disconnects/closes in `finally`. No internal device constructor is needed.
Reads, writes, notification observation and pairing each require their explicit
flags. Example IDs and payloads are synthetic, not instructions for a nearby
device. Unlike the normal library recovery policy, the CLI declines automatic
pairing recovery; only `--pair` initiates Pair. Provision an external
[agent](pairing.md#headless-linux-agent-lifecycle) deliberately.

With the standalone SDK's `dart` on PATH in that external `cli/` directory:

```sh
dart compile exe bin/main.dart -o build/ble_cli
env -u DISPLAY -u WAYLAND_DISPLAY ./build/ble_cli --help
dart compile exe bin/fake_flow.dart -o build/fake_flow
env -u DISPLAY -u WAYLAND_DISPLAY ./build/fake_flow
```

`build/` is created by the verifier. Help and fake flow do not access a radio.
The following real-bus/radio recipes require separate host/peripheral
authorization. Replace the synthetic IDs with your actual authorized selection:

```sh
./build/ble_cli --list-adapters
./build/ble_cli --adapter 02:00:00:00:00:01 \
  --service 12345678-1234-5678-1234-567812345678 --scan-seconds 5
./build/ble_cli --adapter 02:00:00:00:00:01 \
  --service 12345678-1234-5678-1234-567812345678 --scan-seconds 5 \
  --device 02:00:00:00:00:02
```

The last command connects/discovers only. Append `--characteristic
12345678-1234-5678-1234-567812345679` plus `--read`, `--write-hex 0102`, or
`--notify-seconds 10` only for individually authorized operations. The synthetic
payload is NOT a safe command for arbitrary peripherals; no write occurs by
default. Append `--pair` only after agent provisioning, to pair this selected
device before discovery. No agent/Trust/RemoveDevice calls are made by the CLI.
Ctrl-C cancels scan/connect/discovery observation or the notification wait;
already submitted native IO/setup/cleanup is awaited, not aborted. Errors
produce stderr and nonzero exit; secondary cleanup failures are also reported.
Protect output logs containing device IDs and raw advertisement/GATT bytes.

## Find a device

Dart fragment inside an async function, with `quick_blue.dart` imported:

```dart
final result = await QuickBlue.scanResults(
  scanFilter: ScanFilter(serviceUuids: ['180f']),
).first.timeout(const Duration(seconds: 12));
print(result.deviceId);
```

`.first` cancels its scan subscription after one match. A filter only finds
advertisements that actually include that service. See [scanning](scanning.md)
if discovery yields no result.

## Read a known characteristic

Complete Dart function; call it with a real device and readable UUIDs. Battery
Service `180f` / Battery Level `2a19` is an example, not a guaranteed device feature.

```dart
import 'dart:typed_data';
import 'package:quick_blue/quick_blue.dart';

Future<Uint8List> readCharacteristic(
  String deviceId,
  String serviceId,
  String characteristicId,
) async {
  final device = QuickBlue.device(deviceId);
  try {
    await device.connect().timeout(const Duration(seconds: 15));
    final gatt = await device.discoverGatt()
        .timeout(const Duration(seconds: 15));
    final characteristic = gatt.characteristic(
      characteristicId,
      service: serviceId,
    );
    return await characteristic.read().timeout(const Duration(seconds: 8));
  } finally {
    await device.disconnect().timeout(const Duration(seconds: 5));
  }
}
```

The `finally` covers connection timeouts too: a Dart timeout does not cancel
native work. Cleanup errors propagate and can replace the original error;
production apps should record both when diagnosing failures.

Next: [writes and notifications](gatt.md), [connection lifetimes](connections.md),
and [structured errors](pairing.md).
