---
type: "Reference"
title: "Android native transport and companion association"
description: "Understand the bounded native-interop preview and companion UI requirements."
tags: ["android", "companion"]

sources: [{"id": "source1", "resource": "../quick_blue_core/lib/src/quick_blue.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/models.dart"}, {"id": "source3", "resource": "../quick_blue/test/quick_blue_android_test.dart"}, {"id": "source4", "resource": "../quick_blue/android/src/main/kotlin/com/example/quick_blue/QuickBluePlugin.kt"}, {"id": "native-schema", "resource": "../quick_blue/pigeons/availability.dart"}, {"id": "native-client", "resource": "../quick_blue/lib/src/native_availability.dart"}, {"id": "native-guide", "resource": "https://raw.githubusercontent.com/flutter/packages/pigeon-v30.0.2/packages/pigeon/native_interop_migration_guide.md"}]
---

# Android native transport and companion association

Use `QuickBlue.companion` for Android companion-device association, not as a
replacement for normal BLE scanning or GATT ownership. Check `isSupported()`
before offering Android-only association UI. Support depends on OS capabilities.

Dart fragment in an async function:

```dart
if (await QuickBlue.companion.isSupported()) {
  final associations = await QuickBlue.companion.associations();
  print('associated devices: ${associations.length}');
}
```

The facade also exposes `associate(CompanionAssociationRequest(...))` and
`disassociate(associationId)`. Select request filters appropriate to your product;
an association does not replace `device.connect()` or permissions setup.
Dart method-channel tests verify result mapping, not the user's system picker on
hardware.[^source3]

## Version-sensitive BLE behavior

- API 26 is the plugin minimum.
- LE L2CAP requires API 29+.
- Native service-change callbacks require API 31+.
- Runtime scan/connect permission rules change at Android 12.
- Final-client disconnect reconciliation is Android-specific, not a universal
  platform guarantee.

See [platform setup](platform-setup.md), [pairing](pairing.md),
[connections](connections.md), and [capabilities](capabilities.md).

## Native interop preview

`QuickBlue.isBluetoothAvailable()` keeps its `Future<bool>` API but invokes a
synchronous Pigeon native HostApi on Android. It executes the existing permission
and adapter query; it does not start Bluetooth work. All asynchronous BLE
operations, FlutterApi callbacks and EventChannel streams retain the existing
engine-scoped channels. No native callback into Dart is introduced by this
preview slice.[^native-schema]

Generation pins Pigeon `30.0.2`, JNI `1.1.1` and JNIgen `1.0.1`. Native interop is
an upstream **preview**. Android registration uses Flutter 3.50's binding engine
ID, with an engine-unique instance name, and unregisters the same plugin instance
before native detach cleanup. Dart resolves lazily after plugin registration.
Names matter: Pigeon's default resolver can select another engine when an exact
registration is missing. Quick Blue does not use that shared default name.
Missing named registrations fail instead of silently borrowing a peer; resolved
handles fail with `unregistered-instance` after detach. Availability is supported
from Flutter engine root isolates, including background Flutter engines, not
unassociated worker isolates.[^native-client]

Darwin retains its existing channel transport. Full native-interop adoption is
deferred: asynchronous callback shutdown requires explicit lifetime handling,
and macOS offers no plugin-detach callback equivalent to iOS. Linux and Windows
retain their existing transports; Web retains its synchronous chooser delegate.
Native preview build/registry tests do not establish Apple ABI compatibility,
Bluetooth hardware readiness, or safe asynchronous native callbacks.[^native-guide]

See [verification commands](testing.md#native-interop-generation-and-runtime)
for generation, JNI runtime and detach contracts. Android API 26 remains the OS
minimum; the example uses Gradle `9.5.0`, AGP `9.3.1`, Kotlin `2.4.20` and JDK 17
to satisfy Flutter 3.50's build-tool requirements. No app-facing BLE API or native
connection/notification ownership protocol changes.

[^source3]: Android Dart host-API mapping tests.
[^native-schema]: The separate native schema contains only the synchronous availability query.
[^native-client]: The Android-only client uses the current engine ID in its instance name.
[^native-guide]: Pigeon 30.0.2 preview migration and lifecycle constraints.
