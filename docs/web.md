---
type: "Playbook"
title: "Use Web Bluetooth and verify a known peripheral"
description: "Authorize a device from a user gesture and run bounded, read-only-by-default browser hardware checks."
tags: ["web", "bluetooth", "testing"]
sources: [{"id": "backend", "resource": "../quick_blue_web/lib/quick_blue_web.dart"}, {"id": "contracts", "resource": "../quick_blue_web/test/browser_test.dart"}, {"id": "hardware", "resource": "../quick_blue/example/lib/web_bluetooth_hardware.dart"}, {"id": "spec", "resource": "https://bluetooth.spec.whatwg.org/"}, {"id": "chrome", "resource": "https://developer.chrome.com/docs/capabilities/bluetooth"}]
---

# Use Web Bluetooth and verify a known peripheral

## Browser and security requirements

Use a Chromium browser that exposes `navigator.bluetooth`, on HTTPS or a trusted
localhost origin. Firefox and Safari do not expose this API. Linux may require
`chrome://flags/#experimental-web-platform-features`; the OS adapter being powered
on does not prove that the browser can access it. Embedded frames also need an
appropriate `Permissions-Policy: bluetooth` delegation. Permission denial, browser
blocklists and OS policy remain actionable errors, not empty successful scans.
See the [specification](https://bluetooth.spec.whatwg.org/) and
[Chrome guidance](https://developer.chrome.com/docs/capabilities/bluetooth).

## Selection is not scanning

Invoke `QuickBlue.requestDevice(...)` directly from a click/tap handler. Do not
await availability, permissions or other preflight first: that can consume user
activation. The returned handle is authorized, not connected. No RSSI, raw
advertisement data or scan timestamps are invented. `scan`, `scanResults` and the
legacy scan APIs report unsupported on web.[^backend]

Runnable Flutter callback fragment (inside a widget with `quick_blue.dart` imported):

```dart
Future<void> selectAndRead() async {
  // This call must happen before the first await in the gesture handler.
  final selection = QuickBlue.requestDevice(
    serviceUuids: ['180f'],
    optionalServices: ['180a'],
  );
  final device = await selection;
  try {
    await device.connect(timeout: const Duration(seconds: 25));
    final gatt = await device.discoverGatt();
    final level = gatt.characteristic('2a19', service: '180f');
    print(await level.read());
  } finally {
    await device.disconnect(timeout: const Duration(seconds: 25));
  }
}
// ElevatedButton(onPressed: selectAndRead, child: const Text('Select battery'))
```

`serviceUuids` are ANDed within the chooser filter; an optional `namePrefix` is
also ANDed. With neither, the chooser accepts all devices. `optionalServices`
authorizes services not used as filters. Declare every service you need before
selection; later discovery sees only browser-authorized, non-blocklisted primary
services, not necessarily the whole peripheral database. Numeric 16/32-bit UUID
strings and hyphenated 128-bit UUIDs are accepted and normalized to lower-case
128-bit form. Assigned-name aliases and malformed UUIDs are rejected. Repeated
service/characteristic UUIDs are rejected as ambiguous rather than silently
selecting a browser object.[^backend]

Cancellation and no matching device can both surface as browser `NotFoundError`;
Quick Blue preserves browser diagnostics in an actionable operation error rather
than pretending it can always distinguish these outcomes. Unsupported browsers
and insecure contexts are reported separately. `getAvailability` is only an API/
adapter hint, not proof of power or permission; the state stream reports unknown
when the hint is true.

## Lifetime and native-only boundaries

The federated `quick_blue_web` package uses the maintained
`flutter_web_bluetooth` 1.2 low-level bindings. `package:web` 1.1 only supplies a
BluetoothUUID shell, not the required GATT bindings. Reusing the existing binding
avoids a second custom JS Bluetooth API; Quick Blue owns session deadlines and
its shared handle/notification coordinators. It does not use that package's
high-level availability singleton or automatic reconnection.
The Flutter facade and standalone clients share the chooser API in `quick_blue_core`.
The web backend retains automatic Flutter registration.[^backend]

Browser waits are bounded at 20 seconds by default. A timeout ends the affected
session and removes event listeners; a disconnect rejects pending session waits.
Promises cannot always be cancelled physically. A device with still-pending
browser work is quarantined against reconnect until settlement; if it never
settles, reload the page. A late connect is disconnected and never adopted.
Discovery/read results from an ended session cannot publish into a new session.
Notification streams terminate on disconnect, retire their shared claims and
must be subscribed again after reconnect; retirement gates same-device reuse.
Different devices remain independent. Cancel notification subscriptions before
rediscovery, and rediscover after reconnect. Web does not provide database-change
invalidation, durable background connections, restoration, or cross-tab/engine
ownership guarantees.[^backend]

Bonding, MTU, L2CAP, companion/accessory setup, system-connected-device lookup,
raw advertisements and native scan options are unsupported. Maximum write length
is unknown (`null`). Writes use the explicitly requested response mode; browser
promise success without response is not a peripheral application acknowledgement.
Browsers choose the underlying notification/indication mechanism; Quick Blue
checks advertised mode support but cannot force a CCCD transport choice.

## Deterministic browser execution (no radio)

From repository root with Chrome installed (set `CHROME_EXECUTABLE` if needed):

```sh
flutter pub get
(cd quick_blue_web && flutter test --platform chrome)
```

These tests install JS EventTarget/Promise simulator objects on
`navigator.bluetooth`. They execute the actual Dart-to-JS binding and Quick Blue
public handles in Chrome, covering chooser failure, discovery/read/write slices,
timeouts, disconnects, late completion fencing, device switching and repeated
notification release/relisten. They do not exercise browser permission UI, BlueZ,
an adapter or a peripheral. CI uploads browser test logs and the hardware web
build separately.[^contracts]

## Safe real-hardware loop

Use your own documented peripheral/firmware. Never issue exploratory writes to
unknown nearby devices and never flash a device for this test. The example's
browser entry point is separate from the native scanning explorer.[^hardware]

```sh
# From repository root; commit the intended source before recording its SHA.
flutter pub get
cd quick_blue/example
flutter build web --target lib/web_bluetooth_hardware.dart \
  --dart-define=QUICK_BLUE_SOURCE_SHA="$(git rev-parse HEAD)"
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Open `http://localhost:8080` in the supported browser. For a different machine,
serve the build through trusted HTTPS; HTTP on a LAN IP is not localhost security.
For development, `flutter run -d chrome -t lib/web_bluetooth_hardware.dart` with
the same SHA define is an alternative. Do not substitute simulator results for
hardware results.

1. Fill the JSON profile: adapter model, peripheral model/identity, firmware,
   profile name, target service and read characteristic, and exact expected read
   bytes (decimal 0..255). Defaults are illustrative, not a known-device fixture.
2. Set a repeat count from 1 through 10. Choose your notification characteristic
   and exact expected payload. Arrange a safe physical peripheral action to emit
   that payload during each of the two listen cycles per connection.
   Chooser selection is independent of the GATT `service`: `filterServices`
   defaults to `[service]` when omitted (backwards compatible), `namePrefix`
   optionally narrows the same filter, and `optionalServices` grants access to
   services that need not be advertised. For a documented name-only target set
   `filterServices: []`, its known `namePrefix`, and include the target GATT
   service in `optionalServices`. Do not also filter on a service the target does
   not advertise: the browser ANDs those conditions. Empty services and no name
   are rejected rather than opening an unrestricted chooser. The same selection
   configuration applies to the cancel check. Leave `readCharacteristic` empty
   if no safe read is documented: discovery/reconnect still run, but the read
   stage and full aggregate remain BLOCKED; no guessed read is attempted.
3. Keep writes disabled unless your documented peripheral protocol has known-safe
   bytes. To test writes, fill `writeCharacteristic` and `safeWrite`, then
   explicitly check the authorization checkbox. A write PASS means acknowledged
   transport completion, not proof of application state; verify the peripheral's
   application response separately if its protocol requires it.
4. Click Select device and run loops. Each iteration asserts connect, authorized
   discovery, exact read, optional safe write, notification payload, cancel and
   relisten cleanup, disconnect, then reconnects on the next iteration. Ordinary
   stages have a 25-second UI deadline in addition to backend bounds. A missing
   notification/write profile is BLOCKED, never a skipped PASS.
5. Run the separate cancel check, explicitly cancel the visible chooser and
   truthfully confirm that action within 25 seconds. Only a browser not-found
   rejection is eligible for this confirmation; denial, unavailable API and
   timeout remain BLOCKED. A rejection alone is not cancellation proof.
6. Run Manual loss / recovery. Once connected, power the known peripheral OFF
   within 60 seconds. After the remote disconnect stage passes, power it ON
   within 60 seconds for reconnect and rediscovery. Cleanup is attempted on
   success and failure. Do not disable an adapter shared with unrelated users.
7. Export JSON. It records browser/OS, secure context, source SHA, selected
   device/profile and per-stage PASS/FAIL/BLOCKED plus an aggregate. Record exact
   adapter details in the profile (browsers do not reveal adapter identity).
   A failure dominates the aggregate; otherwise any blocked stage prevents PASS.
   Standalone cancel/loss entry points initialize provenance and the full required
   stage list too: cancel-only or out-of-order checks cannot pass the hardware
   suite. Missing metadata or an unselected device also prevents aggregate PASS.
   Start a new full run after changing the profile; standalone checks cannot mix
   results from different profiles.
   Preserve raw exports as test/CI artifacts, not tracked hardware dossiers.

Absent hardware, missing profile details or unavailable browser capabilities are
unresolved hardware acceptance gates, even when all simulator tests and builds
pass. Hardware evidence must name the actual stages executed; a clean build is
only readiness of the test path. See [testing](testing.md).

[^backend]: Browser implementation, bounded waits and session ownership.
[^contracts]: Executable Chrome interop simulator contracts.
[^hardware]: Hardware UI, assertions, deadlines and JSON export.
