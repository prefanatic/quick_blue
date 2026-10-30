---
type: "Playbook"
title: "Install from Git"
description: "Use a consistent repository revision for every federated package."
tags: ["setup", "dependencies"]

sources: [{"id": "source1", "resource": "../quick_blue/pubspec.yaml"}, {"id": "source2", "resource": "../quick_blue_platform_interface/pubspec.yaml"}, {"id": "source3", "resource": "../quick_blue/README.md"}]
---

# Install from Git

The documented repository may be ahead of hosted releases. Install the app-facing
package and override all five dependencies; do not mix Git and hosted platform
implementations. This app `pubspec.yaml` fragment follows the repository recipe.[^source3]

```yaml
dependencies:
  quick_blue:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue

dependency_overrides:
  quick_blue_core:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_core
  quick_blue_platform_interface:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_platform_interface
  quick_blue_darwin:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_darwin
  quick_blue_linux:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_linux
  quick_blue_windows:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_windows
  quick_blue_web:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_web
  quick_blue_web:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue_web
```

Replace all seven `master` refs with the same tested commit SHA for reproducibility.
Run `flutter pub get` in your app. For repository development, run it at the
workspace root instead.

## Standalone Dart Linux

Import `package:quick_blue_core/quick_blue_core.dart` instead of the Flutter package.
Use it together with `package:quick_blue_linux/quick_blue_linux.dart`; call
`QuickBlueLinux.registerWith()` before using `QuickBlue`. Handles, models and
lifecycle state remain in the existing platform interface. Flutter consumers
keep `package:quick_blue/quick_blue.dart` unchanged, including Android APIs.
Core does not export `QuickBlueAndroid` or generated channel code.

For an uncommitted local checkout, put a consumer outside the repository and
override **all three** packages to paths in the same preserved checkout:

```yaml
name: headless_consumer
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  quick_blue_core: ^0.5.0
  quick_blue_linux: ^0.5.0
dependency_overrides:
  quick_blue_core:
    path: /absolute/checkout/quick_blue_core
  quick_blue_platform_interface:
    path: /absolute/checkout/quick_blue_platform_interface
  quick_blue_linux:
    path: /absolute/checkout/quick_blue_linux
```

The paths above are placeholders. External path dependencies do not pull in the
repository's Flutter workspace. To test these packages as roots, the verifier
copies their sources outside the repository and supplies `resolution: null` in
copied `pubspec_overrides.yaml` files; it never modifies source manifests or the
pub cache. Run it with a separately installed Dart 3.13 SDK:

```sh
python3 scripts/check-headless-consumer.py --dart /absolute/dart-sdk/bin/dart
```

Minimal `bin/main.dart` (registration and handle construction do not touch radio):

```dart
import 'package:quick_blue_core/quick_blue_core.dart';
import 'package:quick_blue_linux/quick_blue_linux.dart';

void main() {
  QuickBlueLinux.registerWith();
  final device = QuickBlue.device('synthetic-device');
  print(device.id);
}
```

Runtime dependencies are core → platform interface (`async`, `collection`,
`meta`, `plugin_platform_interface`), and Linux → core/platform interface,
`bluez`, `dbus`, `collection`, `logging`, `ffi`, `meta`. `dbus` also resolves
`args`, `xml` and their descendants; inspect the verifier's retained
`dependencies.json` and `resolved-manifests.json` for exact versions and closure.
Flutter plugin metadata is retained but is not a Flutter SDK dependency.
For real Bluetooth operations, complete [platform setup](platform-setup.md) and
[pairing setup](pairing.md). This local installation does not test Bluetooth
hardware or ARM64 execution. For Git dependencies, use one tested revision
containing these packages.

### Operator CLI fixture

The public Linux CLI (`quick_blue_linux/example/`, repository-relative) is copied by
`scripts/check-headless-consumer.py` into a retained external `cli/` directory,
with matched core/interface/Linux sources and explicit path overrides.
The pure-Dart CLI example retains a Dart 3.12.2 package constraint; the Flutter
workspace requires Flutter 3.47.7 with bundled Dart 3.13.5. The standalone
verification fixture uses Dart 3.13. The example's three direct
dependencies are core, Linux and platform interface;
`test` is development-only. Runtime dependency closure is the same as above.
The verifier checks this CLI's graph/manifests too, runs `dart analyze` and
`dart test`, then `dart compile exe bin/main.dart -o build/ble_cli` and
`env -u DISPLAY -u WAYLAND_DISPLAY ./build/ble_cli --help` (equivalent environment
removal is performed by Python). It also compiles/runs `bin/fake_flow.dart` with
both display variables absent. No radio/agent actions occur during verification.
Use [quickstart](quickstart.md#headless-linux-operator-workflow) for deliberate
device operations and [pairing](pairing.md#headless-linux-agent-lifecycle) for
the external agent/security boundary. ARM64 and hardware verification are
separate, not implied by compilation on the build host.

### Publication compatibility limit

This split currently supports matched source consumers, not a verified hosted
release. `dart pub publish --dry-run` rejects Linux's retained
`flutter.plugin.platforms` metadata without a Flutter environment minimum.
Restoring that minimum would violate the standalone dependency requirement;
removing metadata would lose Flutter automatic registration. The repository's
publish-readiness check therefore currently fails at Linux. A publication solution
is still needed; this change does not disable validation or provide a hosted release.

## Requirements

Flutter consumers now require Flutter 3.47.7 (bundled Dart 3.13.5); older Flutter
releases are no longer supported. Upgrade the SDK before resolving this snapshot.
CI pins both its primary and fresh-resolution minimum-toolchain lanes to 3.47.7.
The pure-Dart packages retain their Dart 3.12.2 constraint and Flutter-free graph;
standalone acceptance still uses a separately installed Dart 3.13 SDK. This
support-policy change does not solve the publication metadata limit above or
establish native or hardware compatibility. See
[platform setup](platform-setup.md) for native requirements and
[testing](testing.md) for the CI toolchain rather than treating minimums as proof
of hardware verification.

[^source3]: Main package install recipe and requirements.
