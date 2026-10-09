# quick_blue

`quick_blue` is a federated Flutter plugin for Bluetooth Low Energy (BLE) on
Android, iOS, macOS, Windows, and Linux.

Connection ownership is shared safely across Flutter engines. On Android, bounded
disconnect reconciliation keeps missing native callbacks from blocking later
reconnects. Remote GATT database changes are surfaced across supported
platforms so applications can invalidate stale service snapshots and
rediscover safely. Applications can query platform capabilities at runtime
instead of duplicating platform and OS-version checks, and explicit chunked
write helpers support larger application payloads without hiding their framing.
Opt-in managed connections provide bounded reconnection backoff while keeping
ordinary connections one-shot.

## Write payload limits and backpressure

Use `device.maximumWriteValueLength(BleOutputProperty.withResponse)` or
`characteristic.maximumWriteValueLength(BleOutputProperty.withoutResponse)` to
query the native maximum payload in bytes for each mode. Darwin queries
CoreBluetooth's `maximumWriteValueLength(for:)` independently for each mode;
with-response writes can have a different limit from without-response writes.
Android, Linux's BlueZ `WriteValue` API, and Windows WinRT have no equivalent
direct payload-limit query and return `null` (unknown), not an MTU-derived guess.
Query after connecting and again after reconnecting. A transport limit is not
a guarantee about a characteristic's supported application-level length.

Writes without response never confirm receipt or processing by the peripheral:

| Platform | Future completion and backpressure |
| --- | --- |
| iOS/macOS | Completes after CoreBluetooth handoff. Rejects before handoff with `invalidState` when `canSendWriteWithoutResponse` is false; the caller decides when to retry. Oversized writes are rejected against the native limit for the selected mode. |
| Android | The shared per-device GATT queue serializes operations and completes on `onCharacteristicWrite`. Failure to initiate or a failing native status is an error, not a successful handoff. |
| Linux | Completes on the BlueZ `WriteValue` D-Bus reply with type `command`. BlueZ busy/in-progress and other errors propagate; no automatic busy retry. |
| Windows | Completes when WinRT `WriteValueAsync` returns success for `WriteWithoutResponse`. Failing communication statuses and native errors propagate; no automatic busy retry. |

Await writes sequentially. Darwin's busy rejection is fail-fast, not an internal
queue or a readiness subscription: awaiting a previous handoff does not ensure
the next write will fit its buffer. Choose any retry delay and retry budget in
the application. Writes with response await the platform's acknowledged-write
result. `writeInChunks` remains opt-in with an explicit `chunkSize`; it stops on
the first error and adds no framing, automatic reassembly, or application ACKs.

- [Knowledge bundle: setup, usage, platforms, and verification](docs/index.md)
- [Install from Git](docs/install.md)
- [Package README](quick_blue/README.md)
- [Changelog](quick_blue/CHANGELOG.md)
- [Contributing and verification](CONTRIBUTING.md)
- [Issue tracker](https://github.com/prefanatic/quick_blue/issues)

## Download the example app

The [BLE explorer lifecycle reference](docs/example-app.md#explorer-connection-ownership)
uses public connection deadlines, explicit bounded client-local abandonment and
awaitable shutdown. Its fake-clock tests verify Dart UI ownership, not physical
Bluetooth behavior.

Each published versioned GitHub Release attaches example-app builds for
Android, iOS Simulator, macOS, Linux x64, and Windows x64. Download the assets
and adjacent `.sha256` files from the
[Releases page](https://github.com/prefanatic/quick_blue/releases). Assets are
built from the source pointed to by that release tag. Verify an asset with
`sha256sum -c <asset>.sha256` on Linux, `shasum -a 256 -c <asset>.sha256` on
macOS, or compare its SHA-256 with `Get-FileHash <asset> -Algorithm SHA256` in
PowerShell.

These are evaluation builds, not store-ready signed applications. The Android
APK uses a debug key. The iOS artifact runs only in the iOS Simulator and is
not an installable device IPA. The macOS app is not Developer ID signed or
notarized, so Gatekeeper may block it. The Linux x64 bundle requires compatible
GTK/BlueZ runtime libraries and the Linux D-Bus policy described in the package
README. The Windows x64 ZIP contains the app bundle; extract it and launch
`quick_blue_example.exe`.

> To use the code in this repository, follow the
> [Git installation instructions](docs/install.md). A hosted
> `quick_blue` release may not contain the changes in this fork.

## Workspace layout

- `quick_blue/`: app-facing package and Android implementation
- `quick_blue_darwin/`: iOS and macOS implementation
- `quick_blue_linux/`: Linux implementation using BlueZ
- `quick_blue_windows/`: Windows implementation using WinRT
- `quick_blue_platform_interface/`: shared APIs, models, and tests
- `quick_blue/example/`: BLE explorer example app and hardware smoke tests

The [plain Markdown OKF bundle](docs/index.md) is the canonical detailed
documentation for requirements, permissions, APIs, platform limitations, and
multi-engine behavior. It is readable without a website or special tooling.
Maintain it with source-linked updates and validation; no separate update log
or generation metadata is required.

The same files power a searchable Zensical site with light/dark themes. See
[documentation maintenance](docs/maintenance.md#preview-and-publish-the-site)
for local preview and GitHub Pages publication requirements. The configured
target is `https://prefanatic.github.io/quick_blue/`; configuration alone does
not mean the site has been published.

## Caller deadlines and cancellation

Device `connect`, `disconnect`, `discoverServices`, `discoverGatt`, and
`requestMtu` accept optional `timeout` and `cancellationToken` arguments:

```dart
final cancellation = QuickBlueCancellationToken();
await QuickBlue.device(deviceId).connect(
  timeout: const Duration(seconds: 15),
  cancellationToken: cancellation,
);
// Elsewhere, cancellation.cancel() stops only this caller's wait.
```

A deadline throws Dart's `TimeoutException`; cancellation throws
`QuickBlueException` with code `cancelled` and reason `callerCancelled`.
A cancelled token is one-shot: use a
new token for a retry. Negative durations fail before starting work; zero uses
the normal Dart timer/event-loop ordering. Without options, waits are unbounded.

These are caller-interest cancellation, not native-operation cancellation.
Timers and token listeners are removed as soon as each wait settles. Cancelling
one caller does not disconnect an engine, cancel another caller's discovery, or
undo a disconnect already requested. A late successful connect can therefore
still leave this engine attached: explicitly disconnect when releasing that
ownership. Engine-local coordination never sends a native cancel on timeout,
preserving the existing process-wide ownership rules across Flutter engines.

Concurrent same-device connects/disconnects and identical MTU requests now share
outstanding work, as discovery already does. An MTU request with a different
value is rejected while negotiation is outstanding. Immediate retries after a
deadline or cancellation rejoin that work, rather than starting a replacement
that could consume an old, uncorrelated native callback. Late completion retires
the shared operation; late errors are consumed even if every caller has left.
If callbacks never arrive, one operation per device/kind remains quarantined,
not an accumulating list of expired callers. Each new caller can still set its
own deadline. Explicit opposite connection operations supersede pending
connect/disconnect; disconnect or GATT invalidation resets discovery. There is
no portable abort/reset for an outstanding MTU request: it remains quarantined
until the platform completes it or the engine is disposed. Caller expiration
does not claim the native procedure has completed or been reset.

Deadline/cancellation options leave federated platform and Pigeon method
signatures, deprecated static helpers, and managed-connection policy unchanged.
The write-limit API adds a default nullable platform hook and a Darwin Pigeon
method; ship matching Darwin Dart/native bindings. Use device methods for the
new wait options. Hardware availability still determines native success.

## Typed failure reasons

`QuickBlueException.failureReason` exposes `QuickBlueFailureReason` values
`connectionFailed`, `callerCancelled`, and `remoteDisconnected`. Match these
values rather than exception message wording. A reason is nullable when the
cause is unknown; it is not a promise that a retry is safe or will succeed.

Connection attempts through `QuickBlue.connect`, `BluetoothDevice.connect`,
and managed connections classify native failures using operation context.
Unexpected disconnection after an observed successful connection is reported
in `BluetoothConnectionStateChange.error`, even when the native status is
success; the original state and status are unchanged. A local disconnect
request is not reported as a remote failure. Superseding a pending connection
operation or cancelling pending discovery through a local disconnect reports
`callerCancelled`. GATT database invalidation remains
`code: cancelled` but is not caller cancellation. Pending discovery interrupted
by remote link loss retains the remote reason and diagnostic cause in `details`.

Existing error codes, messages and security reasons remain available. GATT
statuses (including unknown vendor values), Darwin domains/codes, and structured
security subclasses are preserved. Previously raw native exceptions escaping
a connection attempt now become `QuickBlueException` with `connectionFailed`;
the original exception (including its native details) is retained in `details`
and the Dart throw stack is preserved. Other APIs and unknown causes do not
acquire a reason based on their text.

## Development

Set up the workspace and run the common checks from the repository root:

```sh
flutter pub get
dart format .
flutter analyze
```

Platform changes usually require package tests plus a hardware-backed BLE smoke
test. See [CONTRIBUTING.md](CONTRIBUTING.md) for package-specific checks,
integration-test profiles, Windows VM testing, and Pigeon generation.

CI also checks isolated external Git consumers with empty Pub caches, both for
`quick_blue_linux` alone and for the app-facing plugin. Linux consumers need no
direct `bluez` dependency. To run the install, analysis, and Linux build check:

```sh
python3 scripts/check-linux-consumer.py
```

The check snapshots tracked working-tree files into a disposable Git repository
and uses a separate empty cache for each consumer, without workspace resolution.
It requires the Flutter Linux build toolchain, Git, Python 3, and Pub network
access; it does not require Bluetooth hardware.

## License

This repository is licensed under the terms of the [BSD 3-Clause License](LICENSE).
