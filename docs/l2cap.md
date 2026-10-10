---
type: "Reference"
title: "Open an L2CAP socket"
description: "Use the socket event stream and sink with explicit platform and framing checks."
tags: ["l2cap", "transport"]

sources: [{"id": "source1", "resource": "../quick_blue_platform_interface/lib/models.dart"}, {"id": "source2", "resource": "../quick_blue_platform_interface/lib/src/bluetooth_device.dart"}, {"id": "source3", "resource": "../quick_blue_linux/lib/quick_blue_linux.dart"}, {"id": "source4", "resource": "../quick_blue_linux/lib/src/l2cap_channel.dart"}, {"id": "source5", "resource": "../quick_blue_windows/lib/src/quick_blue_windows.dart"}, {"id": "source6", "resource": "../quick_blue_darwin/lib/src/quick_blue_darwin.dart"}, {"id": "regressions", "resource": "../quick_blue_darwin/test/l2cap_lifecycle_test.dart"}, {"id": "native", "resource": "../quick_blue_darwin/darwin/quick_blue_darwin/Sources/quick_blue_darwin/QuickBlueDarwinPlugin.swift"}]
---

# Open an L2CAP socket

Use LE credit-based L2CAP when the peripheral protocol exposes a known PSM.
This is separate from characteristic writes; neither a GATT UUID nor an ATT MTU
is a PSM. Android requires API 29+, Darwin and Linux implement sockets, and
Windows throws `unsupported`.

## Event-driven use

Complete receive-only Dart function. Call with a known peripheral PSM;
`handleData` must process inbound bytes according to that protocol. This example
owns the connection exclusively in its engine and returns after the socket closes.

```dart
import 'dart:typed_data';
import 'package:quick_blue/quick_blue.dart';

Future<void> receiveL2cap(
  String deviceId,
  int psm,
  void Function(Uint8List) handleData,
) async {
  final capabilities = await QuickBlue.capabilities();
  if (!capabilities.supportsL2capSockets) {
    throw UnsupportedError('L2CAP is unavailable on this platform');
  }
  final device = QuickBlue.device(deviceId);
  try {
    await device.connect().timeout(const Duration(seconds: 15));
    final socket = await device.openL2cap(psm);
    try {
      await for (final event in socket.stream) {
        if (event is BleL2CapSocketEventOpened) {
          print('L2CAP open event');
        } else if (event is BleL2CapSocketEventData) {
          handleData(event.data);
        } else if (event is BleL2CapSocketEventError) {
          throw StateError('L2CAP socket reported an error');
        } else if (event is BleL2CapSocketEventClosed) {
          break;
        }
      }
    } finally {
      socket.sink.close();
    }
  } finally {
    await device.disconnect().timeout(const Duration(seconds: 5));
  }
}
```

Add application cancellation/deadlines for a peer that never opens or closes.
An EventSink `add` has no awaitable peer acknowledgement; stream errors and typed
error events both need handling. Do not assume that inbound event boundaries
provide application message framing across every platform.

Outbound fragment, only once your platform-specific flow has established socket
readiness (`payload` is a Uint8List): `socket.sink.add(payload)`.
Do not wait for an `Opened` event as a portable prerequisite: Darwin waits for
open before returning the socket, and Linux emits its open event before returning
a broadcast stream, so a later listener may not see that event. This API does not
provide a uniform replayed ready-state contract. Test send timing on your target.

## Darwin bridge lifecycle

Darwin installs its event listener before submitting the host open request.
An `error` or `closed` event before readiness rejects `openL2cap` with an
`operationFailed` exception; host bridge failures also reject the future.
The host reply and opened event must both arrive within five seconds.
The returned socket has a buffered, single-subscription stream: attach one
listener, handle both typed error events and stream errors, and always close
the sink. Stream cancellation alone is not native socket closure.

`sink.close()` invokes the existing native close bridge once per active socket;
repeated closes do not resubmit it. After a remote closed event, closing the old
sink is a no-op, including after a replacement socket opens for that device.
Late write/close bridge replies cannot dispose the replacement session; failures
after disposal are reported through `FlutterError.reportError`. Because the public sink is an `EventSink`,
close is not awaitable. Write and close bridge failures are stream errors,
not peer acknowledgements. `sink.addError` forwards a stream error. Writes
after close are rejected. A remote closed event ends the stream.

On an open deadline, Dart attempts native close and retains the event listener
for five additional seconds. A controlled late opened event within this window
triggers another close and releases the listener; a terminal error/closed event
or expiry also releases it. Another open for that device in this platform
instance is rejected while its session or cleanup window remains active.
This is bounded cleanup, not native cancellation: the existing Swift close
API requires an installed stream delegate and can fail before one exists.
Cleanup failures when there is no returned socket are reported through
`FlutterError.reportError`. Events after the cleanup window, other engines or
another platform instance cannot be correlated or safely cancelled by this
device-only schema. Avoid immediate retry after an unresolved timeout.

These contracts are exercised by the fake-messenger regressions, not Apple
peripheral tests. Native nil-channel error emission and physical Apple L2CAP
behavior remain unverified; Swift and the Pigeon schema are unchanged.[^source6][^regressions][^native]

## Linux gotcha

Linux reports `supportsL2capSockets: true` unconditionally; it does not probe
`libbluetooth.so.3` when returning capabilities. Install the distro's BlueZ runtime
library. Missing libraries fail when opening the socket, not during the capability
query.[^source3]

See [platform setup](platform-setup.md), [capabilities](capabilities.md), and
[GATT chunked writes](gatt.md) for the alternative transport.

[^source3]: Linux capability declaration and L2CAP opening path.
[^source6]: Darwin Dart L2CAP session bridge.
[^regressions]: Controlled fake-messenger lifecycle regressions.
[^native]: Existing device-keyed open/close/write Swift bridge.
