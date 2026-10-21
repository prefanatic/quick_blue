---
type: "Playbook"
title: "Share a connection across engines"
description: "Attach the receiving engine before detaching the previous owner."
tags: ["connections", "multi-engine"]

sources: [{"id": "source1", "resource": "../quick_blue/android/src/main/kotlin/com/example/quick_blue/ConnectionClientSet.kt"}, {"id": "source2", "resource": "../quick_blue_darwin/darwin/quick_blue_darwin/connection_ownership/Sources/QuickBlueConnectionOwnership/SharedConnectionOwnership.swift"}, {"id": "source3", "resource": "../quick_blue_windows/windows/connection_ownership.h"}, {"id": "source4", "resource": "../quick_blue_linux/lib/src/connection_ownership.dart"}, {"id": "source5", "resource": "../quick_blue/example/integration_test/android_multi_engine_test.dart"}, {"id": "source6", "resource": "../quick_blue/example/integration_test/ios_multi_engine_test.dart"}]
---

# Share a connection across engines

Use this for a foreground UI and a background Flutter engine in the same app
process. Native GATT ownership is coordinated; Dart handles and subscriptions
remain local to each engine. `disconnect()` detaches one engine, and the physical
connection is closed after the final owner detaches.

## Handoff recipe

Conceptual cross-engine sequence, not a single-scope runnable snippet:

```dart
// Receiving engine: attach and establish its own subscriptions first.
await foregroundDevice.connect();
// Old engine: release its subscriptions, then detach.
await backgroundNotifications.cancel();
await backgroundDevice.disconnect();
```

Coordinate these steps with your application's inter-engine messages. Register the
plugin in each engine. Notification claims are reference-counted, so establish
the receiving subscription before releasing the old one when continuity matters.
Shared native ownership does not transfer Dart objects or automatically keep the
application process alive.

Darwin can connect directly to a stable peripheral UUID already known to
CoreBluetooth; a preceding scan is not always necessary.

## Verification boundary

Linux connection leases identify the actual local adapter and remote device
address together. Two clients using the same adapter share the final-client
disconnect rule (including default versus explicit selection); selecting a
different adapter does not retain the first adapter's native connection. Linux
retains the original native device for the lifetime of its lease: discovery/cache refresh
can expose the same remote address on another adapter, but must not redirect
disconnect or close to that replacement. Failed detach retains the original
target for retry, including a late D-Bus unlock failure after native disconnect.
Reentrant native disconnect events join the pending detach rather than retiring
the target early; attaches wait for that teardown to settle. A failed cleanup
still reports its error, but reconciles the facade to an already-disconnected
native device even without a property event, allowing a later explicit retry.
Retained cleanup identity is not proof of active D-Bus membership: after failed
detach, reconnect confirms or restores the original Client name under the existing
lease lock before reporting success. A same-adapter peer's disconnect or close
therefore cannot treat that reconnected client as absent. Reattach errors remain
observable and do not discard the retained cleanup target.
Same-client registration and detach operations are coordinated locally as well
as through the existing D-Bus lock: `alreadyOwner` is not mutual exclusion on
one bus connection. Duplicate pending attaches share registration; an intervening
detach must settle and membership must be restored before a still-live attach
succeeds. Explicit detach retires its pending connect requester; completing raw
registration still records the identity needed for cleanup, but cannot resurrect
that retired request after teardown.
Every explicit disconnect retires the connect intent preceding it, including a
reconnect waiting behind an already-pending detach. This happens before cleanup
suspends, not only when creating a new detach. Later reconnects may still wait
for the old cleanup; reentrant native events joining it do not cancel them.
The explicit transition includes notification release and final state/observer
cleanup, not just D-Bus lease detach. It is visible before StopNotify suspends,
so a newer connect cannot reuse membership that the older disconnect will remove.
Native events during notification release join this full transition too.
Reconnect retires the preceding native property observer before registration
and native connect can suspend, so a delayed old disconnect event cannot remove
the new membership. Concurrent connects in the same ownership lifetime share
that transition. After explicit detach, a fresh connect acquires membership and
its native target again even when an older native Connect reply is outstanding.
The old reply cannot emit state, replace the new observer, release the new lease
or remove a pending replacement connect. A retired native success reports
supersession; its native error remains visible to its original platform caller.
This does not abort native work. Failed reattach
restores observation of a retained cleanup target and preserves its primary error.
Registration errors attempt to release potentially granted Client/Lock names
even if the successful bus reply was lost. Cleanup failures remain observable
or logged alongside the primary error; a request with a missing reply remains
pending, not successful or implicitly aborted. A replacement lifetime need not
wait for that retired native reply once its own membership/native state is ready.
Spontaneous disconnect releases the target before a later connection can select
a replacement.
Use matching package revisions for cooperating clients: older remote-address-only
lease namespaces do not coordinate with the corrected adapter-scoped namespace.
`quick_blue_linux/test/adapter_lease_test.dart` exercises the real ownership
coordinator and `quick_blue_linux/lib/src/dbus_connection_lease.dart`
with a fake bus and BlueZ devices, including default-client cache replacement
on disconnect/close, independent close, failed connect, detach retry and
spontaneous-disconnect/retry subscription cleanup, pending unlock failures with
reentrant native events, and no-event facade retries. Each integrated late-unlock
scenario has a watchdog and completion marker.
The failed-cleanup/reconnect matrix also asserts actual bus membership and
same-adapter peer disconnect/close protection with and without native events.
`quick_blue_linux/test/reattach_transition_test.dart` additionally holds Client
registration and final unlock replies while delivering delayed native events,
checks peer disconnect/close, duplicate initial/retry connects, rejected/error
replies, retry and complete name cleanup. It also holds native reconnect itself
after registration. Ownership tests exercise synchronous and microtask callbacks
during registration without awaiting their own attach waiter.
`quick_blue_linux/test/connect_transition_test.dart` holds native Connect replies
after connected state, explicitly detaches/reconnects through facade and platform
paths, and checks actual Client names, peer disconnect/close protection, stale
success/error, pending replacement coalescing, adapter replacement and full
cleanup. Same-lifetime duplicates and settled replies remain controls; explicit
detach during pending re-registration must not resurrect retired membership.
It also holds successful/failed final unlock replies while reconnect and a newer
explicit disconnect overlap through public calls. Tests assert actual membership,
native state, pending-reply behavior, newer/duplicate reconnect controls, failed
cleanup retry, peer protection and complete final name cleanup.
`quick_blue_linux/test/notification_disconnect_test.dart` holds StopNotify through
public facade/direct disconnect/reconnect, with native events and no-event
controls. It checks settled/no-reconnect, duplicate and newer/final intent,
late StopNotify errors (logged), failed unlock/retry, native events during the
held release, restored notification watches, peer disconnect/close protection and
complete Client/Lock/native/subscription cleanup under a five-second watchdog.
`quick_blue_linux/test/clear_disconnect_test.dart` also holds asynchronous
subscription cancellation at each final-clear boundary (GATT, scan and native
observer). Delayed native events before/after the joining listener, direct/facade
and duplicate final disconnects, intentionally newer reconnects and cleanup-error
retry retain terminal completion, actual membership and peer protection. The
underlying subscription is cancelled before its cleanup reply is held; events
are not delivered to a cancelled observer. All scenarios assert no leaked names,
native connections or listeners before closing the fake event controllers.
These are not physical multi-adapter or cross-version interoperability tests.

The repository has runtime multi-engine integration suites for Android and iOS.
Linux, macOS and Windows ownership also have unit/native tests, but there is no
matching hardware multi-engine integration suite for each of those targets.
Do not turn implementation support into a claim of universal hardware validation.

See [testing](testing.md) for the Android/iOS commands and
[connections](connections.md) for per-engine lifecycle rules.
