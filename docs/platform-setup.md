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

### Linux service-account permissions

A headless CLI/service uses the system bus, not a desktop/session bus. It needs
running `bluetoothd`, kernel Bluetooth/LE support and a powered authorized
adapter. Run it as the intended non-root service user; changing `$USER` in the
recipe above to that identity is an administrative policy change, not a reason
to run the application as root. A systemd service must have access to the
system-bus socket (normally `/run/dbus/system_bus_socket`); container/sandbox
restrictions and LSM/SELinux rules can deny access independently.

The connection-name template grants `dev.quick_blue.Connection.*` name ownership
only. It does NOT grant `org.bluez` method authorization. Review the distribution's
BlueZ D-Bus policy and any authorization rules for that exact service identity:
it needs ObjectManager/Properties enumeration and signal reception, Adapter1
SetDiscoveryFilter/StartDiscovery/StopDiscovery, Device1 Connect/Disconnect
(Pair only when explicitly requested), and GattCharacteristic1
ReadValue/WriteValue/StartNotify/StopNotify for the chosen workflow. Reply/event
delivery must also be permitted. Do not grant unrestricted system-bus send/own
rights or assume membership in a universally named `bluetooth` group suffices.
Administrative policy installation/reload is separate from ordinary app runtime.
Validate least-privilege rules on the actual distribution as the service user;
there is no portable policy bypass or guaranteed desktop authorization fallback.

An external [pairing agent](pairing.md#headless-linux-agent-lifecycle) additionally
needs its AgentManager1 registration and, if used, default-agent authorization,
plus delivery of BlueZ callbacks to its Agent1 object. A denied default-agent
request must be surfaced, not ignored. The CLI does not register an agent,
power adapters, set Trusted, or call RemoveDevice. See the
[operator example](quickstart.md#headless-linux-operator-workflow) and
[verification boundary](limitations.md#headless-proof-boundaries).

### ARM64 Linux runtime

Deploy an AArch64 executable to 64-bit Linux, not a 32-bit ARM userspace. The
Dart 3.13.5 cross-built CLI uses `/lib/ld-linux-aarch64.so.1` and ELF shared
dependencies `libdl.so.2`, `libpthread.so.0`, `libm.so.6` and `libc.so.6`.
Use `readelf -l -d` on the actual artifact and test on the intended distribution;
a successful compiler invocation does not bundle those libraries or establish
a universal minimum glibc version. The controlled Debian 13/QEMU check is not a
musl/Alpine compatibility claim.

GATT uses the pure-Dart BlueZ/D-Bus client and needs the system-bus, bluetoothd,
kernel, adapter and service-account policy described above. It does not use
libbluetooth for GATT. Optional L2CAP loads glibc and `libbluetooth.so.3`
dynamically; that dependency will not appear as a direct ELF NEEDED entry.
The loader-only probe verifies library/symbol availability, not Bluetooth socket
permissions, kernel L2CAP support or communication. See the
[build/runtime recipe](testing.md#arm64-build-and-controlled-runtime).

Neither cross-compilation nor user-mode QEMU validates Zero 2 W memory limits,
throughput, pairing, peripheral interoperability or radio/kernel behavior.
Test these on the intended device before deployment.

## Windows

Use Windows 10 1809+ or Windows 11 with a working BLE adapter. Normal app use
needs no additional manifest changes. Native builds need Visual Studio's C++
desktop workload, C++/WinRT, and `nuget.exe` on PATH.[^source4]

Next: [quick start](quickstart.md), [capabilities](capabilities.md).

[^source1]: Android plugin manifest.
[^source3]: Linux connection policy template.
[^source4]: Windows implementation requirements.
