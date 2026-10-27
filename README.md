# quick_blue

`quick_blue` is a federated Flutter plugin for Bluetooth Low Energy (BLE) on
Android, iOS, macOS, Windows, and Linux. Use it to scan for peripherals, connect,
discover GATT services, read and write characteristics, and subscribe to updates.

For Linux services without Flutter, use `quick_blue_core` with `quick_blue_linux`
and register the Linux implementation explicitly. Flutter imports stay unchanged.
Follow the [standalone installation instructions](docs/install.md#standalone-dart-linux);
the packages currently require matched source revisions because Linux publication
metadata validation fails.
Linux supports explicit adapter addresses and client shutdown; see
[adapter selection](docs/scanning.md#linux-adapter-selection) and
[cleanup](docs/connections.md#linux-client-shutdown).
Use opt-in [snapshot-bound handles](docs/gatt.md#snapshot-bound-submissions) to reject
new IO after GATT invalidation. The [headless operator CLI](quick_blue_linux/example/README.md)
provides adapter/device selection and opt-in pairing, reads, writes and notifications.
[ARM64 cross-build and emulator checks](docs/testing.md#arm64-build-and-controlled-runtime)
do not test a physical Raspberry Pi or Bluetooth radio.

Connection ownership is shared safely across Flutter engines. On Android, bounded
disconnect reconciliation keeps missing native callbacks from blocking later
reconnects. Remote GATT database changes are surfaced across supported
platforms so applications can invalidate stale service snapshots and
rediscover safely. Applications can query platform capabilities at runtime
instead of duplicating platform and OS-version checks, and explicit chunked
write helpers support larger application payloads without hiding their framing.
Opt-in managed connections provide bounded reconnection backoff while keeping
ordinary connections one-shot.

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
