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

Versioned [GitHub Releases](https://github.com/prefanatic/quick_blue/releases)
provide evaluation builds for Android, iOS Simulator, macOS, Linux x64 and
Windows x64, with adjacent SHA-256 checksums. These are not store-ready signed
applications: Android uses a debug key, iOS is Simulator-only, macOS is not
notarized, and Linux needs compatible GTK/BlueZ libraries and D-Bus policy.
Follow the [download and checksum instructions](quick_blue/example/README.md#download-a-release-build)
before running an asset.

## Download an evaluation build
Each published versioned GitHub Release attaches example-app builds for
Android, iOS Simulator, macOS, Linux x64, and Windows x64. Release tags follow
the shared package version (for example `v0.5.0`). Download the assets and
adjacent `.sha256` files from the
[Releases page](https://github.com/prefanatic/quick_blue/releases). Assets are
built by CI from the release tag rather than the latest `master`.

Assets follow one naming pattern: `quick_blue-example-<tag>-<platform>.<ext>`,
where `<tag>` is the release tag (for example `quick_blue-example-v0.5.0-android.apk`).

| Target | Asset |
| --- | --- |
| Android | `quick_blue-example-<tag>-android.apk` |
| iOS Simulator | `quick_blue-example-<tag>-ios-simulator.zip` |
| macOS | `quick_blue-example-<tag>-macos.zip` |
| Linux x64 | `quick_blue-example-<tag>-linux-x64.tar.gz` |
| Windows x64 | `quick_blue-example-<tag>-windows-x64.zip` |

Every asset has an adjacent `.sha256` file (the standard two-field
`sha256sum` format, so `sha256sum -c <asset>.sha256` works on Linux and
`shasum -a 256 -c <asset>.sha256` on macOS). On Windows, compare the
checksum to `(Get-FileHash <asset> -Algorithm SHA256).Hash` in PowerShell.

To install and run the downloaded asset:

- **Android**: transfer the APK to the device, open it, and accept the
  "install unknown apps" prompt for your browser or file manager; debug-signed
  builds cannot be sideloaded on some enterprise-managed devices. Launch
  `quick_blue_example` from the launcher. Android 8.0 (API 26) or newer is
  required.
- **iOS Simulator**: unzip, then
  `xcrun simctl install booted <extracted>/Runner.app` and
  `xcrun simctl launch booted fyi.goldberg.quickblue.example` (or launch it
  from the Simulator home screen). This artifact cannot run on a physical
  iPhone or iPad.
- **macOS**: unzip to get `Runner.app`, move it anywhere (for example
  `/Applications`), and launch it. The app is not Developer ID signed or
  notarized, so Gatekeeper blocks the first launch: right-click `Runner.app`
  and choose Open. Only if you trust the downloaded app, you can instead run
  `xattr -dr com.apple.quarantine Runner.app` after unzipping to remove its
  quarantine flag. Bluetooth
  permission is prompted on first use.
- **Linux x64**: create an extraction directory with `mkdir -p quick_blue_example`,
  extract with `tar -xzf <asset>.tar.gz -C quick_blue_example`, then run
  `./quick_blue_example/quick_blue_example`. The bundle does not include system
  libraries; compatible GTK and BlueZ runtime libraries and the Quick Blue
  D-Bus policy (see the package README) are required.
- **Windows x64**: extract the ZIP anywhere and launch
  `quick_blue_example.exe`. Windows SmartScreen may warn about an unsigned
  executable: choose More info, then Run anyway.

These are evaluation builds, not store-ready signed applications. The Android
APK is debug-signed; the iOS artifact is
Simulator-only and is not an installable device IPA; the macOS app is not
Developer ID signed or notarized; and the Windows build is not Authenticode-signed.
BLE workflows require a supported host, Bluetooth LE hardware and the
permissions described in the package README. The Simulator artifact does not
establish physical iOS BLE support.

> To use the code in this repository, follow the
> [Git installation instructions](quick_blue/README.md#install). A hosted
> `quick_blue` release may not contain the changes in this fork.

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
