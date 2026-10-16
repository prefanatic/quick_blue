---
type: "Reference"
title: "Observe operations without leaking device data"
description: "Adapt typed operation lifecycles to telemetry and redact sensitive context."
tags: ["telemetry", "privacy"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/src/observability.dart"}, {"id": "source2", "resource": "../quick_blue_core/test/quick_blue_test.dart"}, {"id": "source3", "resource": "../quick_blue_core/lib/src/quick_blue.dart"}]
---

# Observe operations without leaking device data

Assign `QuickBlue.observer` before the work you want to measure. The observer
starts an operation and optionally returns a per-operation handle for its end.
Quick Blue does not choose your telemetry SDK, exporter, metric names or sampling.

Complete observer classes; install with `QuickBlue.observer = ConsoleObserver()`:

```dart
import 'package:quick_blue/quick_blue.dart';

final class ConsoleObserver implements QuickBlueObserver {
  @override
  QuickBlueOperationObservation onOperationStarted(QuickBlueOperation operation) {
    print('start ${operation.kind.name}');
    return ConsoleOperation();
  }
}

final class ConsoleOperation implements QuickBlueOperationObservation {
  @override
  void onOperationEnded(QuickBlueOperationEnd operation) {
    print('${operation.outcome.name}: ${operation.duration.inMicroseconds} us');
  }
}
```

Combine adapters with `CompositeQuickBlueObserver([observerA, observerB])`; set
`QuickBlue.observer = null` to disable. `QuickBlueValueObserver` adds payload-free
value callbacks with identifiers and byte counts. A
`QuickBlueDarwinRestorationObserver` reports aggregate restoration counts, not
peripheral identifiers. See [Darwin startup](darwin.md).

## Interpret outcomes honestly

Healthy subscriber cancellation (including a scan consumed by `.first`) is
`stopped`; a superseded operation is `cancelled`, not `failed`. Observer callback
failures are ignored so telemetry cannot change Bluetooth behavior.[^source2]

## Privacy boundary

Payload bytes and advertisement results are not included, but device IDs can
identify physical hardware and scan filters can contain private byte prefixes.
Redact or hash before export. Prefer structured failure metadata; raw error and
stack trace values can include native details, device IDs and local paths.
The simple observer above logs no identifiers or raw errors.

[^source2]: Operation observer lifecycle tests.
