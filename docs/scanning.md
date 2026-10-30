---
type: "Reference"
title: "Scan results and filters"
description: "Own scanning through subscriptions and select portable or native scan controls."
tags: ["scan", "filters"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/src/scan_lifecycle.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/models.dart"}, {"id": "source3", "resource": "../quick_blue_platform_interface/test/quick_blue_platform_scan_test.dart"}, {"id": "source4", "resource": "../quick_blue_linux/lib/quick_blue_linux.dart"}]
---

# Scan results and filters

These scan APIs are native-only. On [web](web.md), invoke
`QuickBlue.requestDevice` directly from a gesture. Chooser results are authorized
device handles, never fabricated advertisement telemetry.

Choose `QuickBlue.scan()` for device handles, or `scanResults()` for advertisement
name, RSSI, service UUIDs, service data and manufacturer bytes.

## Example

Dart fragment in an async scope; imports: `dart:typed_data` and `quick_blue.dart`.

```dart
final subscription = QuickBlue.scanResults(
  scanFilter: ScanFilter(
    rssi: -80,
    serviceData: <String, Uint8List>{'180a': Uint8List(0)},
  ),
  scanOptions: const ScanOptions(
    allowDuplicates: false,
    scanMode: ScanMode.balanced,
  ),
).listen(
  (result) => print('${result.name}: ${result.rssi}'),
  onError: (Object error) => print('scan failed: $error'),
);
// Keep the subscription while the feature is active; cancel on teardown.
await subscription.cancel();
```

Service-data values match payload prefixes; an empty value matches any data for
that UUID. Multiple service-data entries use OR semantics. Service-data filtering
is distinct from filtering the advertised service UUID list.

## Ownership and native options

- A returned scan stream is single-subscription. Call `scanResults()` again for
  another listener; compatible listeners share native scanning.
- A differing active filter/options request is rejected; cancel the old scan
  subscriptions before replacing their settings.[^source3]
- The final cancellation stops scanning. Do not use deprecated `startScan` /
  `stopScan` to manage new code.
- `ScanOptions` exposes `android`, `darwin`, `linux`, and `windows` option objects.
  Native knobs include Android PHY, Darwin solicited services, Linux pathloss,
  and Windows signal-strength timing. Omitted common values preserve defaults.
- Linux option forwarding has dedicated filter/default unit tests in
  `quick_blue_linux/test/scan_session_test.dart`; mocked forwarding is not
  hardware verification.[^source4]

If scanning is empty, check permissions, power, advertisements, and overly narrow
filters. [Testing](testing.md) includes an advertisement-only profile.

[^source3]: Shared scan lifecycle tests.
[^source4]: Linux facade delegating to `lib/src/scan_session.dart`.

## Linux adapter selection

The [operator CLI](quickstart.md#headless-linux-operator-workflow) requires an explicit
adapter and service filter for scanning. It retains full `BlueScanResult`
objects keyed by device ID and emits JSON including service data in hex;
names never decide identity. `--device` must match a result from the current
scan. Service-filter absence in an advertisement can legitimately exclude a
device that has that GATT service after connecting. Scan-only mode never pairs
or connects. Canceling its subscription stops this client's scan ownership.

Construct `QuickBlueLinux(adapterAddress: '02:00:00:00:00:01')` and register
that instance with `QuickBluePlatform.instance = platform` (import the platform
interface as well as core and Linux); the address is a
synthetic placeholder, not a discovered device. `await platform.adapters()`
returns immutable address/power snapshots. Neither call powers on an adapter.
Omitting the selector retains the first-powered default and `registerWith()`
continues to use that default for Flutter registration. A requested missing,
unpowered or removed adapter never falls back to another. Scan results and
device resolution are scoped to an explicit selection, including when multiple
adapters know the same remote address; foreign add/remove events cannot replace
or clear the selected device. Stop retains the adapter
that started discovery even if availability changes. A failed native stop keeps
that exact target for retry, while local result watches are canceled. Direct Linux
start/stop requests are serialized in call order: a start waits for preceding
stop completion and releases any retained scan before selecting a new adapter.
A queued stop after an in-flight start releases that scan after start completes;
old cleanup cannot clear a newer scan's filters or target. A failed release is
observable and must succeed before a replacement scan starts. Shutdown uses the
same queue; it does not abort stalled native calls. Local BlueZ fakes test
these contracts; adapter removal/radio behavior remains unverified.[^source4]

The [scan lifecycle regressions](https://github.com/prefanatic/quick_blue/blob/master/quick_blue_linux/test/scan_session_test.dart)
hold native start/stop replies, inject a failed stop, remove/replace adapters and
assert retries, queued starts, independent filter/watch state and final stop calls.
