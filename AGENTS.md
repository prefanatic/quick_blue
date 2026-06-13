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

## Common Commands

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

Use platform builds or the example app for Android, iOS, macOS, Windows, and
Linux behavior that unit tests cannot cover.

## Development Notes

- Preserve the federated plugin boundaries: shared API/model changes usually
  belong in `quick_blue_platform_interface`, while platform behavior belongs in
  its platform package.
- Keep Android channel/API changes aligned across Dart, Kotlin, and generated
  Pigeon files.
- Keep Darwin channel/API changes aligned across Dart, Swift, and generated
  Pigeon files.
- Do not use `unawaited` futures in Dart code. If a future can throw, await it
  or route errors to an explicit handler so failures are observable.
- `pubspec.lock` is ignored in this repository.
- Before editing, check the worktree and avoid reverting or rewriting unrelated
  in-progress changes. Existing platform files may contain active BLE work.
