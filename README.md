# quick_blue

`quick_blue` is a federated Flutter plugin for Bluetooth Low Energy (BLE) on
Android, iOS, macOS, Windows, and Linux. Use it to scan for peripherals, connect,
discover GATT services, read and write characteristics, and subscribe to updates.

The handle-based API supports caller deadlines, optional managed reconnection,
and connection sharing across Flutter engines. Optional operations differ by
platform; check [runtime capabilities](docs/capabilities.md) and
[known limitations](docs/limitations.md) before relying on them.

Flutter consumers require Flutter 3.47.7 or newer; CI pins stable 3.47.7 with
Dart 3.13.5. Older Flutter support is dropped; upgrade the SDK before resolving.
Standalone Dart 3.13 acceptance and its Flutter-free dependency graph are retained.

For Linux services without Flutter, use `quick_blue_core` with `quick_blue_linux`
and register the Linux implementation explicitly. Flutter imports stay unchanged.
Follow the [standalone installation instructions](docs/install.md#standalone-dart-linux);
the packages currently require matched source revisions because Linux publication
metadata validation fails.
Linux supports explicit adapter addresses and client shutdown; see
[adapter selection](docs/scanning.md#linux-adapter-selection) and
[cleanup](docs/connections.md#linux-client-shutdown).
Use opt-in [snapshot-bound handles](docs/gatt.md#snapshot-bound-submissions) to reject
new IO after GATT invalidation, including security-recovery retries. Linux retains
native notification ownership across watch replacement, tracks acquired native
endpoints after same-UUID rediscovery, confirms setup after retiring potentially
aliasing BlueZ wrappers, and retries failed scan
stops against the original adapter. The [headless operator CLI](quick_blue_linux/example/README.md)
provides adapter/device selection and opt-in pairing, reads, writes and notifications.
[ARM64 cross-build and emulator checks](docs/testing.md#arm64-build-and-controlled-runtime)
do not test a physical Raspberry Pi or Bluetooth radio.



## Get started

1. [Install from Git](docs/install.md), using the same revision for all federated
   packages. Hosted releases may not contain the changes documented here.
2. [Configure your platform](docs/platform-setup.md), including Bluetooth
   permissions and Linux D-Bus policy.
3. Follow the [scan, connect and read quickstart](docs/quickstart.md).

The [documentation index](docs/index.md) covers device workflows, platform APIs
and troubleshooting. For specific operations, see:

- [Connection ownership, deadlines and retries](docs/connections.md)
- [GATT discovery, notifications and write limits](docs/gatt.md)
- [Pairing and security failures](docs/pairing.md)
- [Multiple Flutter engines](docs/multi-engine.md)
- [L2CAP sockets](docs/l2cap.md)

Reconnect after explicit detach does not join retired native replies; old events
and replies cannot release the replacement owner.
A final explicit disconnect retires queued reconnects; old cleanup preserves
intentionally newer requests.
Newer requests wait for complete old cleanup, including notification release.
Late native events during cleanup cannot suppress a joining facade disconnect's
terminal completion.

With [adapter-scoped connection ownership](docs/multi-engine.md#verification-boundary),
same-adapter clients share final-owner cleanup; different adapters release
independently. Cooperating clients require matching revisions.
Cache refresh cannot redirect a held connection's native cleanup to another adapter.
Pending/reentrant teardown and late unlock failure retain the native target
through retry.
Failed-teardown reconnect restores membership while retaining that target,
protecting it from peer disconnect or close.
The old native observer is retired so delayed disconnect events cannot disturb
pending reattachment.

The [executable Dart adapter contracts](docs/testing.md#dart-adapter-contracts)
cover fake messenger/BlueZ behavior, not native or hardware certification.


## Try the BLE explorer

Run the [example app](quick_blue/example/README.md) to scan for devices and
interact with their characteristics. See [example workflows](docs/example-app.md)
for source setup and hardware-test profiles.

Versioned [GitHub Releases](https://github.com/prefanatic/quick_blue/releases)
provide evaluation builds for Android, iOS Simulator, macOS, Linux x64 and
Windows x64, with adjacent SHA-256 checksums. These are not store-ready signed
applications: Android uses a debug key, iOS is Simulator-only, macOS is not
notarized, and Linux needs compatible GTK/BlueZ libraries and D-Bus policy.
Follow the [download and checksum instructions](quick_blue/example/README.md#download-a-release-build)
before running an asset.

## Repository layout

- `quick_blue/`: app-facing package and Android implementation
- `quick_blue_darwin/`: iOS and macOS implementation
- `quick_blue_linux/`: Linux implementation using BlueZ
- `quick_blue_windows/`: Windows implementation using WinRT
- `quick_blue_platform_interface/`: shared APIs, models and tests
- `quick_blue/example/`: BLE explorer and hardware integration tests

The plain Markdown [knowledge bundle](docs/index.md) is the canonical detailed
documentation. The same files power the Zensical site; see
[local preview and publication setup](docs/maintenance.md#preview-and-publish-the-site).

## Contribute

Read [CONTRIBUTING.md](CONTRIBUTING.md) and choose the relevant checks from
[repository verification](docs/testing.md). Keep documentation changes with the
behavior they describe. See the [changelog](quick_blue/CHANGELOG.md) for changes
and the [issue tracker](https://github.com/prefanatic/quick_blue/issues) to report
problems.

## License

This repository uses the [BSD 3-Clause License](LICENSE).
