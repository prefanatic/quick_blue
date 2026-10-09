# Android 17 repair coordination: implementation and verification

Task: t_0ceb47e9. Local-only changes on wt/t_0ceb47e9; no commit, push, or PR.
This is a review handoff, not a claim of Android 17 device validation.

## Implementation contract

- Public bond states and cross-platform APIs are unchanged. The owning Android
  Pigeon schema adds only an internal repair observation (device, generation,
  unknown/in-progress/succeeded/failed), its query, and its event channel.
- Native observation requires explicit API-37 REPAIRING context from a pairing
  request or an observed transition into BONDING (with a known non-BONDING
  previous state) for a device tracked by this plugin connection. Context on a
  terminal BONDED/NONE broadcast cannot start or reopen repair; missing bond
  stage/previous-stage evidence falls back conservatively.
  API level alone, retained BONDED, and ordinary NONE do not establish repair.
- Only a subsequent successful, enabled LE encryption broadcast settles repair
  successfully. Missing status, disabled encryption, failed encryption, and
  BR/EDR encryption are not success proof. KEY_MISSING after observed context
  settles failure. Intermediate bond changes do not resolve an active repair's
  pending pair; ordinary fresh-pair rejection retains prompt failure dispatch.
- The OS owns UI, replacement keys, and security-level enforcement. The plugin
  does not approve/cancel dialogs or remove bonds. Native createBond guards also
  refuse competing requests while observed repair is active.
- Dart observes before querying to catch races. A retained bond with active
  repair waits within the existing 30-second completion bound. Only correlated
  terminal success permits the existing single retry; a cached success from a
  previous operation is not reused. Failure, unavailable evidence, or timeout
  produces userActionRequired, not a definitive verdict that OS repair failed.
- Per-device generations reject old Dart events. Connection eligibility is
  invalidated on the native disconnect callback before queued Flutter delivery;
  engine detach clears native state and ends the repair stream. A new connection
  needs fresh explicit context before a terminal event can be used. Official
  broadcasts contain no connection token: correlation is observational, not a
  guarantee against arbitrary OEM broadcast reordering across a new context.
- API 36/older and missing-context OEMs retain conservative bonded behavior and
  ordinary explicit fresh pairing. No generic GATT 133/19 remapping or reconnect
  redesign is included.

The public API-36/37 broadcast names are wire constants, allowing compileSdk 35
consumers to build without hidden API reflection or a blanket SDK increase.

## Reproduction of generated outputs

From the repository root:

```sh
python3 scripts/generate-android-messages.py
```

This runs `dart run pigeon --input pigeons/messages.dart` from quick_blue, then
mechanically removes trailing generator whitespace from both generated outputs.
Pigeon 29 emits space-only EventChannel lines; no generated logic is hand-edited.
Two consecutive wrapper runs produced byte-identical Dart and Kotlin outputs.
Handwritten touched Dart files were formatted; raw generated template layout is
otherwise preserved to avoid unrelated formatting churn.

## Actual checks

- `flutter pub get`: succeeded.
- `dart format` on handwritten changed/new Dart files and the Pigeon source:
  succeeded; the final format pass made no changes before the last test edit,
  and that last test edit was formatted before final analysis/testing.
- `flutter analyze` from the workspace root: no issues found.
- `cd quick_blue && flutter test --reporter expanded`: 102 tests passed.
- `cd quick_blue_platform_interface && flutter test --reporter expanded`:
  168 tests passed.
- `cd quick_blue/example/android && ./gradlew :quick_blue:testDebugUnitTest --rerun-tasks`:
  BUILD SUCCESSFUL; XML reports contain 47 tests, zero failures/errors/skips,
  including 14 AndroidRepairObserver tests.
- `cd quick_blue/example && flutter build apk --debug`: succeeded, producing
  `quick_blue/example/build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: passed after automatic generated whitespace normalization.
- Existing Gradle/AGP/Kotlin deprecation/version warnings remain; no toolchain
  upgrade was attempted as part of this focused change.

New Dart tests cover retained bonds, proof-gated success, rejection, no extra bond
request, one retry and no second retry, cached successes, failure snapshots,
missing context, query failure/timeout, stream error/closure, old generations,
disconnect invalidation, per-device isolation, event/query races, repair starting
during implicit observation, and a simulated dialog delay beyond 30 seconds.
Native tests cover SDK gates (26/35/36/37), missing/ordinary/repair context,
intermediate NONE versus fresh rejection, encryption fields/transport, KEY_MISSING,
per-device isolation, reconnect generations, queued stale disconnect, terminal
state, and detach cleanup. These are deterministic tests, not device traces.

## Review round 1 correction

The original observer treated any contextual bond broadcast as an attempt start.
Because Android also attaches REPAIRING context to terminal bond broadcasts, a
late contextual BONDED after encryption success, or NONE after KEY_MISSING,
could invent a new active repair and generation. The receiver now passes current
and previous bond stages into the pure seam; only a pairing request or an actual
contextual transition into BONDING establishes a new attempt. Terminal snapshots
and generations survive late terminal bond broadcasts. BONDED alone remains
insufficient proof of successful repair.

Added native tests reproduce both terminal sequences, verify state/generation
stability and ordinary pair dispatch, exercise a genuine new contextual BONDING
attempt after failure, and reject incomplete/repeated stage evidence. Existing
pairing-request restart, no-competing-bond and fresh-rejection tests remain.
The downstream Dart/Pigeon test consumes the preserved terminal snapshot after
a late bond event, requires subsequent recovery to complete within one second
without claiming recovery, and checks explicit pair forwarding. It does not
pretend to execute Android broadcasts or native createBond from a Dart mock.

All checks above were rerun after the correction; regenerated outputs were
byte-identical by SHA-256 comparison. The first version of the new Dart test
hung because the test harness's real event-queue delay was awaited inside fake
widget time; converting that test to real async time with an explicit bound
fixed the test-only issue. The final focused and full suites pass.

## Hardware limitation and outstanding manual plan

Actual discovery commands:

```sh
adb devices -l
flutter devices
```

ADB listed no devices; Flutter listed only Linux desktop. The Android SDK emulator
executable was absent. No API-37 BLE-capable Android host was available.
The attempted hardware smoke command was:

```sh
cd quick_blue/example
QUICK_BLUE_HIDE_TEST_WINDOW=1 flutter test integration_test/ble_smoke_test.dart -d android
```

It failed with `No supported devices found with name or id matching 'android'`.
No device validation was performed. Installing an SDK platform alone would not
supply an Android BLE peer transport or a controllable bonded peripheral.

When suitable hardware is available, execute the upstream decision's full plan:

1. Capture `adb devices -l`, `adb shell getprop ro.build.version.sdk`,
   `adb shell getprop ro.build.fingerprint`, `adb shell dumpsys bluetooth_manager`,
   and `adb logcat -v threadtime`. Record app target SDK, Bluetooth module,
   peripheral firmware/security mode, pairing context, encryption and KEY_MISSING,
   native GATT status, bond requests, recovery result, and operation retry count.
2. Establish a baseline encrypted read/write. Delete only peripheral-side bond
   keys while retaining Android's bond. Trigger a protected operation. Accept,
   reject, ignore, and accept after more than 30 seconds in separate clean runs.
   Verify no competing app bond request/removal/UI approval; acceptance must show
   correlated LE encryption before retry, rejection must not report recovery,
   and app timeout must not be labeled OS repair failure.
3. Repeat after Settings > Connected devices > peripheral > Forget/unpair.
   Distinguish ordinary fresh pairing from repair context. Fresh rejection must
   fail promptly; NONE alone must not be labeled remote key loss.
4. Repeat on Android 16 and an older supported Android release, and with two
   devices. Where supported by peripheral firmware, attempt weaker re-pairing
   and verify Android does not replace keys below the prior security level.

All UI timing, OEM/module behavior, peripheral-only key deletion, Settings-unpair,
and security-mode regression scenarios above remain hardware-unverified.

## Authoritative references

- https://developer.android.com/about/versions/17/behavior-changes-all
- https://developer.android.com/about/versions/16/behavior-changes-all
- https://developer.android.com/reference/android/bluetooth/BluetoothDevice
- https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/android17-release/framework/java/android/bluetooth/BluetoothDevice.java
- https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/android17-release/android/app/src/com/android/bluetooth/btservice/BondStateMachine.java

The parent decision was read at
`/home/hermes/quick_blue/.worktrees/t_a91dbe73/docs/research/android17-quick-blue-decision.md`.
This implementation preserves its correction: returning from the Kotlin
suspendCancellableCoroutine registration block does not resume the coroutine.
