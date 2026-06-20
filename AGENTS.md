# Repository Instructions

## Project Layout

This repository is a Dart workspace for `quick_blue`, a federated Flutter
Bluetooth LE plugin.

- `quick_blue/` is the app-facing plugin package. It contains the Android
  implementation and delegates iOS/macOS, Linux, and Windows to federated
  packages.
- `quick_blue_darwin/` implements iOS and macOS with shared Swift source.
- `quick_blue_linux/` implements Linux support with BlueZ and generated FFI
  bindings.
- `quick_blue_windows/` implements Windows support in C++.
- `quick_blue_platform_interface/` contains shared Dart APIs, models, and
  platform-interface tests.
- `quick_blue/example/` is the Flutter example app used for manual and platform
  verification.

The root `pubspec.yaml` defines the workspace members. Run dependency setup from
the repository root unless a package-specific command says otherwise.

## Generated Code

Pigeon APIs are source-of-truth files and generated outputs must stay in sync.

- Android/main plugin Pigeon source: `quick_blue/pigeons/messages.dart`
- Android/main generated outputs:
  - `quick_blue/lib/src/messages.g.dart`
  - `quick_blue/android/src/main/kotlin/com/example/quick_blue/Messages.g.kt`
- Darwin Pigeon source: `quick_blue_darwin/pigeons/messages.dart`
- Darwin generated outputs:
  - `quick_blue_darwin/lib/src/messages.g.dart`
  - `quick_blue_darwin/darwin/quick_blue_darwin/Sources/quick_blue_darwin/Messages.g.swift`

When changing a Pigeon schema, regenerate from the owning package directory:

```sh
cd quick_blue
dart run pigeon --input pigeons/messages.dart

cd ../quick_blue_darwin
dart run pigeon --input pigeons/messages.dart
```

Do not hand-edit generated `messages.g.*` files except to inspect them.

## Verification

Choose the narrowest check that proves the change, then broaden when the touched
surface is shared or platform-specific.

- Docs-only changes: run `git diff --check`.
- Dart API/model changes: format touched Dart files, run `flutter analyze`, and
  run the relevant package tests.
- Platform-interface changes: test `quick_blue_platform_interface` plus affected
  app-facing package tests.
- Example app changes: run `cd quick_blue/example && flutter analyze && flutter test`.
- Pigeon schema changes: regenerate from the owning package and verify generated
  files with `git diff`.
- Platform implementation changes: run the affected package tests and build or
  smoke-test the matching platform when available.

Common repo checks:

```sh
flutter pub get
dart format .
flutter analyze
```

Package-focused tests:

```sh
cd quick_blue_platform_interface && flutter test
cd quick_blue_darwin && flutter test
cd quick_blue/example && flutter test
```

Hardware-backed BLE smoke tests are required for changes touching scan, connect,
service discovery, read/write, notifications, device switching, or platform
Bluetooth behavior unless the target hardware or host environment is genuinely
unavailable.

macOS smoke test:

```sh
cd quick_blue/example
QUICK_BLUE_HIDE_TEST_WINDOW=1 flutter test integration_test/ble_smoke_test.dart -d macos
```

Headless Linux smoke test:

```sh
cd quick_blue/example
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  xvfb-run -a flutter test integration_test/ble_smoke_test.dart -d linux
```

Known-device advertisement smoke test:

```sh
cd quick_blue/example
QUICK_BLUE_HIDE_TEST_WINDOW=1 \
  xvfb-run -a flutter test integration_test/ble_smoke_test.dart -d linux \
    --dart-define=QUICK_BLUE_SMOKE_PROFILE=valve_lighthouse
```

Windows BLE smoke test through Dockur, for Windows platform work or USB
Bluetooth passthrough verification:

```sh
QUICK_BLUE_WINDOWS_USB_VENDOR_ID=0x0bda \
QUICK_BLUE_WINDOWS_USB_PRODUCT_ID=0x8771 \
  scripts/windows-integration-test.sh
```

The Dockur VM state is persisted under `.dart_tool/dockur_windows/`. The guest
reuses `C:\quick_blue_workspace\quick_blue` so Flutter can keep `.dart_tool`
and build caches. Use `QUICK_BLUE_WINDOWS_CLEAN_WORKTREE=1` to refresh the
guest checkout without reinstalling Windows, and `QUICK_BLUE_WINDOWS_RESET=1`
only when the VM disk itself needs to be rebuilt.

These tests need Bluetooth permission, powered-on Bluetooth hardware, and nearby
BLE advertisements or explicit smoke-test Dart defines. If Bluetooth is
unavailable on a supported target, `ble_smoke_test.dart` should fail rather
than skip.

Use platform builds or the example app for Android, iOS, macOS, Windows, and
Linux behavior that unit tests cannot cover.

When verification cannot be run, report the exact command attempted, the
blocker, and what remains unverified.

## Development Notes

- Preserve the federated plugin boundaries: shared API/model changes usually
  belong in `quick_blue_platform_interface`, while platform behavior belongs in
  its platform package.
- Keep Android channel/API changes aligned across Dart, Kotlin, and generated
  Pigeon files.
- Keep Darwin channel/API changes aligned across Dart, Swift, and generated
  Pigeon files.
- When changing APIs, user-facing behavior, examples, supported platforms, or
  setup requirements, update the root `README.md` and root package changelog
  (`quick_blue/CHANGELOG.md`) so they stay representative of the work.
- Do not use `unawaited` futures in Dart code. If a future can throw, await it
  or route errors to an explicit handler so failures are observable.
- `pubspec.lock` is ignored in this repository.
- Before editing, check the worktree and avoid reverting or rewriting unrelated
  in-progress changes. Existing platform files may contain active BLE work.
- Before committing, inspect recent commit subjects and match the repo style:
  lower-case scoped subjects such as `quick_blue: tighten README docs` or
  `quick_blue,platform_interface: document public APIs`.
