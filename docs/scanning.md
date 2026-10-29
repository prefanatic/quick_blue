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
