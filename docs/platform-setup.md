---
type: "Reference"
title: "Configure each platform"
description: "Set permissions, entitlements and host policy before using Bluetooth."
tags: ["setup", "permissions", "android", "darwin", "linux", "windows"]

sources: [{"id": "source1", "resource": "../quick_blue/android/src/main/AndroidManifest.xml"}, {"id": "source2", "resource": "../quick_blue/README.md"}, {"id": "source3", "resource": "../quick_blue_linux/dbus/dev.quick_blue.Connection.conf"}, {"id": "source4", "resource": "../quick_blue_windows/README.md"}]
---

# Configure each platform

## Android (API 26+)

The plugin contributes manifest permissions, not runtime permission UI. Your app
must request `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` on Android 12+; older
Android needs location permission for scanning. The contributed scan declaration
uses `neverForLocation`; review/override it if your app derives physical location
from advertisements.[^source1]

## iOS (13+) and macOS (10.15+)

Add this app Info.plist fragment:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app connects to nearby Bluetooth devices.</string>
```

Sandboxed macOS apps also need this in debug and release entitlements:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

Read [Darwin startup](darwin.md) before enabling restoration or AccessorySetupKit:
their startup order is significant, and persistent restoration conflicts with a
picker-first flow.

## Linux

Run BlueZ with a powered BLE adapter and allow the app access to the system bus.
Connection serialization additionally owns `dev.quick_blue.Connection.*` names.
If `connect()` fails with `Request to own name refused by policy`, install the
supplied policy for the application user.[^source3]

Repository-root shell recipe (requires administrative permission; review before running):

```sh
sed "s/RUN_AS_USER/$USER/" quick_blue_linux/dbus/dev.quick_blue.Connection.conf \
  | sudo tee /usr/share/dbus-1/system.d/dev.quick_blue.Connection.conf >/dev/null
sudo systemctl reload dbus-broker   # use your distro's D-Bus reload procedure
```

For a shared host, adapt the policy to an authorized group rather than granting
all users ownership. L2CAP separately needs `libbluetooth.so.3` at use time;
the Linux capability flag does not probe that library. See [L2CAP](l2cap.md).

## Windows

Use Windows 10 1809+ or Windows 11 with a working BLE adapter. Normal app use
needs no additional manifest changes. Native builds need Visual Studio's C++
desktop workload, C++/WinRT, and `nuget.exe` on PATH.[^source4]

## Web

Use HTTPS or trusted localhost and a Chromium browser exposing Web Bluetooth.
Call `QuickBlue.requestDevice` directly from a user gesture; declare all needed
services before selection. Linux may need the experimental web platform flag.
Permission/policy restrictions still apply. See [browser setup and hardware loops](web.md).

Next: [quick start](quickstart.md), [capabilities](capabilities.md).

[^source1]: Android plugin manifest.
[^source3]: Linux connection policy template.
[^source4]: Windows implementation requirements.
