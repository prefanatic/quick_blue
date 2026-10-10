# Dart adapter contract matrix (V07 / R17)

This is an implementation specification, not a passing test attestation. Evidence
proves Dart translation, event routing and fake-dependency lifecycle only; it does
not prove Android, Apple, WinRT or BlueZ hardware/runtime semantics.

## Source and integration decisions

Inspected freshly fetched upstream `0596865a0a46e18f7dc6d56561a79f538cf7bcea`.
The old local branch `wt/t_91e693c5` at `de25bde` is preserved, not reset.
This plan starts on a new branch from upstream; no production files are changed.
Actual worker runtime is subscription openai-codex / gpt-6.1-sol; the card's
launch event records low reasoning and coordinator HTTP-200 entitlement evidence.

Required predecessor heads are NOT in upstream master:

- Notification settlement: PR #15 `a26b7eb97e381cffc410a5c46183cf46129d96ab`,
  stacked on PR #14 `384b46bc148a524e806d9d862fd8f6c502969e78`.
- Snapshot handles: PR #19 `74636b30ff5f516532ef250dba250e7624b2daf9`.
- Darwin bridge: local reviewed-next implementation
  `93d13bf4af883874faf50cc5a656fef0e2c1c311`; publication belongs to its own chain.

Wrapper worker must use the exact Darwin implementation for lifecycle cases,
checking its latest review disposition first. GATT adapter cases can characterize
upstream independently; notification settlement assertions require #15/#14.
Do not merge whole predecessor branches silently: document exact commits included
and resolve shared lifecycle changes before aggregate tests. Snapshot validity is
not an adapter translation case; retain #19's existing tests during aggregation,
without duplicating them in the new harness. Linux worker starts on upstream plus
this plan; Linux race PR #20 and syscall PR #23 are independent, not prerequisites.

Open overlap inspected: #1 changes the Darwin implementation/test surface; #11
Android security work; #14/#15 shared characteristic lifecycle; #19 snapshot
surface; #20 Linux GATT tests; #23 Linux L2CAP tests; #22 validators/toolchain.
Root README, changelog, docs/gatt.md and workflows are integration hotspots.
Leaf workers do not edit them. Aggregate writer reconciles docs/tests and exact
heads before publication; an open PR is not evidence of merge.

## Ownership (one writer)

Wrapper worker owns new files:

- `quick_blue/test/adapter_contract_test.dart`
- `quick_blue/test/test_support/adapter_contract_harness.dart`
- `quick_blue_darwin/test/adapter_contract_test.dart`
- `quick_blue_darwin/test/test_support/adapter_contract_binding.dart`
- `quick_blue_windows/test/adapter_contract_test.dart`
- `quick_blue_windows/test/test_support/adapter_contract_binding.dart`
- `evidence/adapter-contracts/wrappers/` evidence.

Common harness is test-only, imported relatively by package entry tests if needed;
no pubspec changes or production abstraction. It accepts callbacks for injecting
values, pending read completion, error envelopes and initialization. Each binding
uses its OWN generated codec/types and channel prefix. Never share generated
Platform* objects across packages. Linux does not consume this fixture.

Linux worker owns new `quick_blue_linux/test/adapter_contract_test.dart`,
`quick_blue_linux/test/test_support/adapter_contract_bluez.dart`, and
`evidence/adapter-contracts/linux/`. Copy minimal local fakes from the existing
private GATT fixture rather than editing/extracting `gatt_session_test.dart`
(shared with #20). Use BlueZ interfaces, controlled property streams, read
Completer, injected connection lease and call counters. No real system D-Bus.

Aggregate documentation worker owns this plan's final case status table and
canonical testing/limitations docs, index/nav only if needed, root README and
main changelog. Implementation workers report findings without editing these.
Production files, schemas/generated files, native code and workflows are excluded.

## Executable case matrix

Use device A/B, services 180f/180a, characteristic 2a19 in BOTH services, bytes
[9] for notification and [1,2] for direct result. Use valid UUID aliases (short,
uppercase and canonical) rather than arbitrary strings for routing assertions.
Register expectations/listeners before injection; use bounded waits and awaited
cancellation, not sleeps or discarded futures.

| ID | Android | Darwin | Windows | Linux | Expected assertion |
| --- | --- | --- | --- | --- | --- |
| R1 | direct host bytes | direct host bytes | inherited event fallback | fake readValue bytes | Hold read pending, inject [9], then reply [1,2]. Android/Darwin/Linux direct future equals [1,2], never [9]; event stream still receives notification. Windows deliberately returns matching first event [9], not a fabricated direct result. |
| R2 | callback serviceUuid | callback serviceUuid | callback serviceUuid | resolved canonical service | Identical characteristic UUID in two services: service-qualified subscriptions receive only own service; wrong device/characteristic ignored; canonical UUID aliases match. Verify outgoing read/write/notify argument identity separately from event canonicalization. |
| R3 | typed GATT status | domain/code map | numeric status 3 | BlueZ NotAuthorized | Parameterize read/write/setNotifiable: security reason, native domain/code, operation and device/service/characteristic context survive. Also non-security and malformed details follow actual adapter behavior, not universal coercion. |
| R4 | shared notification claims | shared notification claims | shared notification claims | StartNotify/property watch | Listen before setup; two matching listeners share enable and final cancel disables once. Conflicting notify/indicate rejected. Pending setup success/failure cancellation follows #15 contract when included. Linux additionally asserts property hasListener and stop counts after disconnect/clearDevice, including failed setup and teardown. |
| R5 | host dynamic capability | host dynamic gates + fixed modes | fixed modes | fixed modes | Assert complete capability object and forwarded host parameters; unsupported calls throw typed unsupported with operation. Android API-dependent gates, Darwin UUID-required lookup, Windows bonding/L2CAP unsupported, Linux MTU unsupported. Capability flags are not readiness evidence. |
| R6 | empty service callback | empty service callback | empty service callback | inherited dispatcher injection | Deliberately inject serviceId='': legacy callback and matching per-service value listeners receive value, including both services with same characteristic. Nonempty service must NOT fan out. Label this backward-compatible event routing, NOT successful service-less native lookup. |
| R7 | lazy Flutter API setup | lazy setup + restoration stream | lazy Flutter API setup | withClient/lease | First host operation installs callbacks; repeat initialization does not duplicate delivery. Cancel test-owned listeners; unregister generated FlutterApi and every mock channel in tearDown. Do not claim plugin-wide dispose: no public dispose exists. Linux disconnect cleans fake device/characteristic watchers. |

R1 Windows is a real inherited `QuickBluePlatform.readCharacteristicValue` path:
its generated host read API returns void and the wrapper has no direct override.
Test early matching event plus wrong-service events explicitly. A native direct-read
correlation redesign is a separately scoped follow-up, not an in-scope schema edit.

R6 Linux should call the public inherited `handleCharacteristicValueChanged`
with empty service in a SEPARATE compatibility case. BlueZ resolution requires a
service, emits canonical nonempty identity and does not support native service-less
lookup. Assert this distinction, do not change production lookup to force parity.

## Existing source seams and fixtures

- Android: `quick_blue/lib/src/quick_blue_android.dart`: lazy `_ensureInitialized`,
  direct `readCharacteristicValue`, `_runGattOperation`, `_FlutterApi` callbacks.
  Existing `quick_blue/test/quick_blue_android_test.dart` demonstrates decoded
  BasicMessageChannel mocks, direct return and authentication errors; bond harness
  is security-specific and is NOT a universal adapter fixture.
- Darwin: `quick_blue_darwin/lib/src/quick_blue_darwin.dart`: direct read,
  `_runDarwinGattOperation`, restoration listener on initialization. Existing
  package tests supply callback sender and platform domain/code error envelopes.
  Repaired predecessor's `l2cap_lifecycle_test.dart` is the authoritative socket
  fixture; do not duplicate socket lifecycle in the GATT parameterized harness.
- Windows: `quick_blue_windows/lib/src/quick_blue_windows.dart`: void read,
  `_runWindowsGattOperation` maps numeric AccessDenied=3; other PlatformExceptions
  rethrow. Existing package test's `_sendFlutterApiMessage` uses its OWN codec.
- Linux: `QuickBlueLinux.withClient` plus `LinuxGattSession`, BlueZ device/service/
  characteristic interfaces, `QuickBlueLinuxConnectionLease`. Existing
  `gatt_session_test.dart` demonstrates private fakes, fresh read versus cached
  Value, canonical IDs, security translation and watcher cleanup. New fixture
  adds controlled pending reads and duplicate services. Linux emits an initial
  cached notification value on setup; account for it explicitly in event ordering.
- Shared `CharacteristicLifecycleCoordinator.handleValueChanged` implements empty
  service legacy fan-out. Shared value stream retention/settlement on master is
  older than #14/#15: record baseline/source and never mislabel a known failure.

## Commands and evidence gates

From the selected isolated worktree root:

```sh
flutter pub get
(cd quick_blue && flutter test test/adapter_contract_test.dart --reporter expanded)
(cd quick_blue_darwin && flutter test test/adapter_contract_test.dart --reporter expanded)
(cd quick_blue_windows && flutter test test/adapter_contract_test.dart --reporter expanded)
(cd quick_blue_linux && flutter test test/adapter_contract_test.dart --reporter expanded)
flutter analyze
```

Then full affected package suites, and platform-interface suite when stacking
#14/#15/#19. Format only touched Dart files; run `git diff --check`. Every case
executes locally: no platform-based skips. Report exact source/fixture SHA,
commands, actual executed case count and failures. Keep concise logs and a case
status table in assigned evidence directories. Production defects get failing
regression evidence and separate corrective cards; do not modify production here
or encode an intended guarantee as a fabricated passing test.

Documentation validation follows `docs/maintenance.md`: OKF checker, its unittest
suite, clean Zensical build, site checker. Plan-only change does not alter public
API, supported platforms or behavior; README/changelog/index remain unaffected
until aggregate executable coverage is documented. Hardware smoke is not proof of
these injected interleavings; no runtime claim is made by this plan.

## Unsupported seams and proof boundaries

Windows direct native read correlation is absent; split into follow-up before
aggregate completion. Plugin-wide disposal/restoration subscription cleanup is
not publicly injectable disposal: R7 proves only test-owned cleanup and existing
initialization, not lifecycle redesign. Real native callback ordering, native
service-less lookup, BLE readiness, native notification setup and Apple/Windows
runtime validation remain outside this verification-only scope. Track genuine
coverage blockers explicitly; do not expand into native rewrites or hardware
provisioning. Existing integration recipes in docs/testing.md remain authoritative
for separately authorized hardware evidence.
