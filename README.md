# quick_blue

`quick_blue` is a federated Flutter plugin for Bluetooth Low Energy (BLE) on
Android, iOS, macOS, Windows, and Linux. Use it to scan for peripherals, connect,
discover GATT services, read and write characteristics, and subscribe to updates.

The handle-based API supports caller deadlines, optional managed reconnection,
and connection sharing across Flutter engines. Optional operations differ by
platform; check [runtime capabilities](docs/capabilities.md) and
[known limitations](docs/limitations.md) before relying on them.

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
For a fresh checkout, follow the [setup and artifact policy](quick_blue/example/README.md#fresh-checkout-setup-and-artifact-policy).

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
