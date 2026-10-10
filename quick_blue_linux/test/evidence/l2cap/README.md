# Linux L2CAP characterization evidence

Source: freshly fetched upstream master `0596865a0a46e18f7dc6d56561a79f538cf7bcea`.
This directory is committed with the implementation it exercises (no stacked
source dependency). Host: Linux x64, Flutter 3.47.6, Dart 3.13.5.

## Executed commands

From repository root:

```sh
flutter pub get
(cd quick_blue_linux && flutter test --reporter expanded)
(cd quick_blue_linux && flutter analyze)
(cd quick_blue/example && flutter build linux --debug)
```

Actual retained output: [package-tests.txt](package-tests.txt) (111 passed:
90 existing plus 16 channel and five subprocess characterization tests),
[analyze.txt](analyze.txt) (no issues), [linux-build.txt](linux-build.txt)
(debug example built). JSON lines in package-tests.txt are actual observations,
not generated expectations. Timing and high-frequency counts vary by machine.
Documentation/format/consumer checks are retained in validation.txt.
External clean-cache consumer output is in [consumer.txt](consumer.txt): both
`quick_blue_linux` and `quick_blue` resolved/analyzed/built successfully via
`python3 scripts/check-linux-consumer.py`. The safe single EINVAL reproduction
also executed; see [reproduction.txt](reproduction.txt). Logs retain actual tool
output with trailing whitespace stripped only to satisfy `git diff --check`.

## Observed outcomes

- Success: 150 exact bytes / three sends; partial: 150 / 12 sends; finite EINTR:
  150 / four sends. Each closed one fake fd and balanced 10 allocations/frees.
- EAGAIN twice then success: 150 bytes / five sends, 45 ms; nine heartbeat ticks
  and two receive-poll calls. Closed one fd and balanced 12 allocations/frees.
- ECONNREFUSED (111), dynamic-PSM EINVAL (22), EACCES (13): one connect attempt,
  exception, fd closed once, six allocations/frees, no polling. Persistent
  connect EINTR (4) failed after exactly eight calls with the same cleanup.
- Persistent first-chunk EINVAL: 5,000,000 send calls in the last snapshot,
  zero main heartbeat ticks, 11 independent observer ticks; one live fake fd,
  two live allocations (read/frame), no channel close. Parent SIGKILL/reap:
  actual exit -9, elapsed including startup 1731 ms.
- Persistent send EINTR: 72,100,000 calls, main/observer ticks 0/11;
  one live fake fd/two allocations. Killed/reaped -9 after 1640 ms.
- Persistent recv EINTR: 63,200,000 recv calls, ticks 1/10;
  one live fake fd/one allocation. Killed/reaped -9 after 1792 ms.
- Always-data recv: 1,900,000 recv calls, ticks 1/10;
  one live fake fd/one allocation. Killed/reaped -9 after 1850 ms.
- Zero-byte send: 24 sends, zero bytes, ticks 50/11;
  32 allocations/31 frees (read buffer still owned). Responsive but incomplete;
  killed/reaped -9 after 1798 ms.

The five characterization assertions pass because they safely measure existing
failure/non-completion. This is NOT five successful channel operations. Main
heartbeat counts measure the channel isolate; independent observer ticks only
show the reporter is alive. Snapshots are the last reported state, not an exact
final counter at kill. SIGKILL does not run Dart cleanup; OS process reclamation
must not be described as balanced channel cleanup. Fds are scripted ownership
identifiers, not real kernel Bluetooth fds. The allocator does use real calloc.

## Safe failing-flow reproduction and correction boundary

```sh
(cd quick_blue_linux && flutter test test/l2cap_harness_test.dart \
  --plain-name 'send-einval: watchdog termination is failure characterization' \
  --reporter expanded)
```

Replace the test name with the analogous `send-eintr`, `recv-eintr`, `recv-data`
or `send-zero` test to reproduce the other cases. Never invoke the child runner
without a parent watchdog: main-isolate timers cannot interrupt these spin loops.
The parent waits up to 15 seconds for arming, observes 500 ms, SIGKILLs, waits
up to five seconds for exit (reap), and bounds each pipe EOF wait to five seconds.
Its finally block also kills/reaps if assertions or startup observation fail.
Children have isolates, not additional child processes.

No production socket correction is made or claimed here. A separately authorized
correction should bound retry/work per event-loop turn in `_sendFrame` and
`_pollReadable`, choose an explicit terminal/retry policy for persistent first-
chunk EINVAL and EINTR, and specify a bounded policy for permanently zero writes.
Require the existing safe reproductions to demonstrate failing responsiveness
before correction, then regression tests showing yielding/terminal outcomes,
observable errors, no byte duplication/loss across partial+EAGAIN retry and
balanced fd/allocation cleanup after cancellation. Keep connect's existing
bounded retry behavior and sink/event semantics unchanged unless separately
specified. Native errno interpretation, SEQPACKET partial-write semantics and
real peer readiness require target hardware evidence, not this harness.

## Proof boundary

Real Dart channel control flow, scripted syscall responses and compilation only.
No libc Bluetooth socket/connect/send/recv, BlueZ adapter, peripheral, native
readiness or negotiated peer MTU is exercised. No hardware smoke is claimed.
The docs and changelog describe this testing workflow; root README is unchanged
because public BLE APIs, platform setup and supported behavior do not change.
