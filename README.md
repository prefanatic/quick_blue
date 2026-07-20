# quick_blue

`quick_blue` is a federated Flutter plugin for Bluetooth Low Energy (BLE) on
Android, iOS, macOS, Windows, and Linux.

- [Install, platform setup, and usage](quick_blue/README.md)
- [Changelog](quick_blue/CHANGELOG.md)
- [Contributing and verification](CONTRIBUTING.md)
- [Issue tracker](https://github.com/prefanatic/quick_blue/issues)

> To use the code in this repository, follow the
> [Git installation instructions](quick_blue/README.md#install). A hosted
> `quick_blue` release may not contain the changes in this fork.

## Workspace layout

- `quick_blue/`: app-facing package and Android implementation
- `quick_blue_darwin/`: iOS and macOS implementation
- `quick_blue_linux/`: Linux implementation using BlueZ
- `quick_blue_windows/`: Windows implementation using WinRT
- `quick_blue_platform_interface/`: shared APIs, models, and tests
- `quick_blue/example/`: BLE explorer example app and hardware smoke tests

See the [package README](quick_blue/README.md) for Git installation,
requirements, permissions, a quick start, API examples, platform limitations,
and multi-engine behavior.

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

## License

This repository is licensed under the terms of the [BSD 3-Clause License](LICENSE).
