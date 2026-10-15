---
type: "Reference"
title: "Android companion association"
description: "Keep companion UI separate from BLE connections and check OS support."
tags: ["android", "companion"]

sources: [{"id": "source1", "resource": "../quick_blue_core/lib/src/quick_blue.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/models.dart"}, {"id": "source3", "resource": "../quick_blue/test/quick_blue_android_test.dart"}, {"id": "source4", "resource": "../quick_blue/android/src/main/kotlin/com/example/quick_blue/QuickBluePlugin.kt"}]
---

# Android companion association

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

[^source3]: Android Dart host-API mapping tests.
