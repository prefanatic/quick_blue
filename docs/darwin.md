---
type: "Reference"
title: "Darwin restoration and accessory setup"
description: "Choose a restoration-first or AccessorySetupKit-first startup flow."
tags: ["darwin", "ios", "macos", "restoration", "accessory-setup"]

sources: [{"id": "source1", "resource": "../quick_blue_darwin/darwin/quick_blue_darwin/Sources/quick_blue_darwin/QuickBlueDarwinPlugin.swift"}, {"id": "source2", "resource": "../quick_blue_darwin/test/quick_blue_darwin_test.dart"}, {"id": "source3", "resource": "../quick_blue/README.md"}]
---

# Darwin restoration and accessory setup

## GATT disconnect failures

Pending reads, writes and notification updates rejected with native structured
`Disconnected` carry `QuickBlueFailureReason.remoteDisconnected` while retaining
the broad `invalidState` code and operation/native diagnostics. An `InvalidState`
message mentioning a disconnect does not establish this cause. Structured security
errors retain their security exception classification; caller cancellation is not
reclassified. This is an error classification, not permission to replay writes.

## Persistent restoration

For reliable iOS background relaunch, configure native startup before Dart runs.
App Info.plist fragment:

```xml
<key>UIBackgroundModes</key>
<array><string>bluetooth-central</string></array>
<key>QuickBlueCoreBluetoothStateRestorationEnabled</key>
<true/>
```

The persistent key creates the central manager during plugin registration with
Quick Blue's stable restoration identifier. It is authoritative:
`configure(maintainState: false)` does not disable it. macOS can use the persistent
key too, without the iOS background-mode declaration.

If the key is absent, `await QuickBlue.configure(maintainState: true)` is a
runtime-only option and must run before other manager-initializing APIs. Dart
startup can be too late for iOS relaunch. Delayed-engine add-to-app integrations
need their own native pre-engine bootstrap; this plugin has no pre-engine
AppDelegate API.

Restoration requested, manager initialized, and state actually restored are
separate facts. A successful configure does not prove a `willRestoreState`
callback occurred. Native events buffer until Dart/observer attachment and are
delivered once; observe aggregate counts using [observability](observability.md).

## AccessorySetupKit-first (iOS 18+ only)

Do not enable persistent restoration in this build. The picker must run before
Quick Blue initializes CoreBluetooth. App Info.plist example for one product:

```xml
<key>NSAccessorySetupSupports</key>
<array><string>Bluetooth</string></array>
<key>NSAccessorySetupBluetoothServices</key>
<array><string>180D</string></array>
<key>NSAccessorySetupBluetoothNames</key>
<array><string>Sensor</string></array>
```

Dart fragment in an async function; `imageBytes` is a Uint8List loaded from your
product artwork asset, and the discovery values must match the app declarations:

```dart
if (await QuickBlue.appleAccessorySetup.isSupported()) {
  final accessory = await QuickBlue.appleAccessorySetup.showPicker([
    AppleAccessoryPickerItem(
      displayName: 'Sensor',
      productImage: imageBytes,
      discovery: AppleAccessoryDiscovery(
        serviceUuid: '180d',
        nameSubstring: 'Sensor',
      ),
    ),
  ]);
  if (accessory != null) {
    await QuickBlue.device(accessory.deviceId).connect();
  }
}
```

The picker authorizes but does not connect; retain the device and disconnect when
the feature ends. `accessories()` lists authorized accessories; `remove()` revokes
one. `migrationDeviceId` migrates a known peripheral UUID. Once app-level
AccessorySetupKit keys are present, CoreBluetooth scanning is limited to
accessories authorized for the app. Quick Blue validates discovery declarations.

`isSupported()` is false on macOS and iOS before 18. Picker host-call mapping is
unit-tested; it is not a hardware picker integration test.[^source2]
See [platform setup](platform-setup.md) for usage descriptions/entitlements.

[^source2]: Darwin host-API and restoration mapping tests.
