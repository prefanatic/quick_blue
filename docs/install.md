---
type: "Playbook"
title: "Install from Git"
description: "Use a consistent repository revision for every federated package."
tags: ["setup", "dependencies"]

sources: [{"id": "source1", "resource": "../quick_blue/pubspec.yaml"}, {"id": "source2", "resource": "../quick_blue_platform_interface/pubspec.yaml"}, {"id": "source3", "resource": "../quick_blue/README.md"}]
---

# Install from Git

The documented repository may be ahead of hosted releases. Install the app-facing
package and override all four dependencies; do not mix Git and hosted platform
implementations. This app `pubspec.yaml` fragment follows the repository recipe.[^source3]

```yaml
dependencies:
  quick_blue:
    git:
      url: https://github.com/prefanatic/quick_blue.git
      ref: master
      path: quick_blue

dependency_overrides:
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
```

Replace all five `master` refs with the same tested commit SHA for reproducibility.
Run `flutter pub get` in your app. For repository development, run it at the
workspace root instead.

## Requirements

Dart 3.12.2 and Flutter 3.44.2 are the declared minimums, exercised by the
minimum-toolchain Dart analysis/test lane. This does not establish native build
or hardware compatibility at the minimum. See
[platform setup](platform-setup.md) for native requirements and
[testing](testing.md) for the CI toolchain rather than treating minimums as proof
of hardware verification.

[^source3]: Main package install recipe and requirements.
