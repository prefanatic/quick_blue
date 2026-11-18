# Headless Linux operator CLI

This is a pure-Dart example, not a service or a pairing agent. Start with the
[standalone build instructions](../../docs/install.md#operator-cli-fixture)
and [service-account and pairing setup](../../docs/pairing.md#headless-linux-agent-lifecycle).
No Flutter SDK, engine, display or desktop session is needed by the executable.
Its Linux implementation dependency is `quick_blue_linux_dart`; the containing
`quick_blue_linux` directory is the Flutter shell, not a CLI dependency.

From the repository root, with a separately installed Dart 3.13 SDK:

```sh
python3 scripts/check-headless-consumer.py --dart /absolute/dart-sdk/bin/dart
```

The verifier copies this example and matched package sources outside the Flutter
workspace, adds path overrides, resolves a fresh cache, inspects all transitive
manifests, runs analysis/tests, compiles and runs help plus a fake-device workflow.
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

## ARM64 build and runtime

Use the same external fixture and standalone SDK with
`scripts/check-arm64-consumer.py`; see the
[ARM64 build instructions](../../docs/testing.md#arm64-build-and-controlled-runtime).
Cross-build output is inspected as AArch64 ELF. Optional user-mode QEMU runs
help, fake flow and a separate glibc/libbluetooth loader probe without radio or
bus access. Neither this nor a successful loader probe proves real GATT/L2CAP,
pairing or physical Zero 2 W performance. Check the target distribution's
[runtime libraries and BlueZ policy](../../docs/platform-setup.md#arm64-linux-runtime).

## Select a device

These commands access the system bus and Bluetooth radio. Use only devices you
are authorized to operate. Replace the synthetic IDs with your adapter,
peripheral and protocol UUIDs. List adapters, scan, then select a result:

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
  data, NOT a safe command for an arbitrary peripheral. The CLI does not write
  by default or add chunking, retries or protocol framing.
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
of delivery. Cleanup attempts scan cancellation, notification cancellation, selected-device
disconnect and Linux close even after failures. It releases only this client's
connection leases and does not select or disconnect unrelated devices.

`fake_flow` exercises the same CLI function through public platform fakes and
asserts sequence, advertisement retention and teardown. It never touches D-Bus,
BlueZ, agents or radios. Linux pairing-error tests separately inject BlueZ/D-Bus
errors. Help checks executable startup; fake flow checks operation order and
cleanup. Neither tests real Bluetooth, authentication, ARM64 execution or
Zero 2 W performance.
