# Headless Linux operator CLI

This is a pure-Dart example, not a service or a pairing agent. Start with the
[canonical install/fixture recipe](../../docs/install.md#operator-cli-fixture)
and [service-account and pairing setup](../../docs/pairing.md#headless-linux-agent-lifecycle).
No Flutter SDK, engine, display or desktop session is needed by the executable.

From the repository root, with a separately installed Dart 3.13 SDK:

```sh
python3 scripts/check-headless-consumer.py --dart /absolute/dart-sdk/bin/dart
```

The verifier copies this example and matched package sources outside the Flutter
workspace, adds path overrides, resolves a fresh cache, inspects all transitive
manifests, analyzes/tests, compiles and runs help plus a controlled fake flow.
It prints the retained fixture path. In its `cli/` directory:

```sh
dart compile exe bin/main.dart -o build/ble_cli
env -u DISPLAY -u WAYLAND_DISPLAY ./build/ble_cli --help
dart compile exe bin/fake_flow.dart -o build/fake_flow
env -u DISPLAY -u WAYLAND_DISPLAY ./build/fake_flow
```

Use the standalone SDK's `dart` on PATH. `build/` is created by the verifier.
Do not resolve this example inside the repository workspace using standalone
Dart: the root workspace intentionally includes Flutter packages. No cache
manifest edits or Git commits are needed.

## Deliberate operator actions

These commands access a real system bus/radio and are recipes, not evidence of
hardware verification. Replace all synthetic IDs below with authorized adapter,
peripheral and protocol UUIDs. First list, then scan, then select a result:

```sh
./build/ble_cli --list-adapters
./build/ble_cli --adapter 02:00:00:00:00:01 \
  --service 12345678-1234-5678-1234-567812345678 --scan-seconds 5
./build/ble_cli --adapter 02:00:00:00:00:01 \
  --service 12345678-1234-5678-1234-567812345678 --scan-seconds 5 \
  --device 02:00:00:00:00:02
```

The last command rescans with that filter, rejects devices absent from this
scan, connects and prints discovered GATT services/characteristics. Selection is
by exact ID, never a matching name or the first advertisement. JSON preserves
identity, timestamp, RSSI, service UUIDs, service-data and manufacturer bytes.
The output can contain sensitive identifiers and payloads; protect logs.

To the last command, add `--characteristic
12345678-1234-5678-1234-567812345679` plus individually authorized actions:

- `--read`: read the selected characteristic.
- `--write-hex 0102`: send exactly these bytes with response. This is synthetic
  data, NOT a safe command for an arbitrary peripheral. No default write,
  chunking, replay or protocol framing is inferred.
- `--notify-seconds 10`: enable notifications, print values, await cancellation
  after this interval (or Ctrl-C), then disconnect.
- `--pair`: pair this one discovered device after connect, before discovery.
  Pairing is independent of writing. Provision a suitable external agent first.

The CLI explicitly installs its Linux platform instance; its documented public
security-recovery hook declines automatic pairing, even after protected IO fails.
Normal library/Flutter consumers retain the existing coordinated recovery policy.
There is no agent registration, default-agent request, Trust or RemoveDevice
call. Failed pairing is not repaired by replacing a bond or accepting another
peripheral. Errors reach stderr and nonzero exit status; cleanup errors are
reported separately while preserving a primary operation failure.

## Cancellation and limits

Ctrl-C cancels scan/connection/discovery observation and the notification wait.
Connection/discovery use built-in 20-second caller deadlines. It does not abort
already submitted BlueZ pairing, reads, writes, notification setup or cleanup;
these are awaited before cleanup. A stalled native call may therefore delay
shutdown. External `Future.timeout` is not a native abort. Notification setup
may succeed without any notification arriving; an empty interval is not proof
of delivery. Finally attempts scan cancel, notification cancel, selected-device
disconnect and Linux close even after failures. Only owned leases detach; no
unrelated device is selected or disconnected intentionally.

`fake_flow` exercises the same CLI function through public platform fakes and
asserts sequence, advertisement retention and teardown. It never touches D-Bus,
BlueZ, agents or radios. Linux pairing-error tests separately inject BlueZ/D-Bus
errors. Help proves executable startup; fake flow proves control flow. Neither
proves real BLE, real authentication, ARM64 execution or Zero 2 W suitability.
