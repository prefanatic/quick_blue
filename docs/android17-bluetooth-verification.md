# Android 17 bond-loss and autonomous-repair verification

## Status: BLOCKED — hardware capability not established

The local attempt on 2026-10-07 booted official Android 17/API 37 images and
observed Bluetooth ON, but did **not** run any bond-loss or repair scenario.
SurfaceFlinger repeatedly crashed, preventing stable pairing UI. No physical
Android handset or validated bond-erasing peripheral was available. All ten
cases below are NOT RUN, not passed or skipped-as-success.

This document is a diagnostic record and a hardware-arrival runbook, not a
claim that an emulator, the plugin, or OS autonomous repair has been verified.
Host SDK/AVD provisioning is separate from product changes. No purchases,
consumer-device pairing, host USB rebinding, or host Bluetooth service changes
were performed.

## Choose the verification environment

- Official emulator + netsim runs an Android Bluetooth host stack and can help
  with software regressions. Bluetooth ON, a virtual advertisement, or even
  pairing does not prove autonomous repair after peripheral-only key loss.
  The attempted configuration did not reach stable UI or provision a peer.
- Android-x86 is not a substitute: its published Android 9 releases do not
  provide Android 17/API 37. Do not infer Bluetooth compatibility from booting.
- Use a physical Android 17/API 37 handset and a controlled BLE peripheral for
  faithful OS dialog, durable bond, and negotiated-security verification.
  Emulator USB HCI bridging/Bumble is not a validated fallback here; it requires
  exclusive controller ownership and validated key-storage/security behavior.

References (capability documentation is not execution evidence):

- [Emulator networking and Bluetooth](https://developer.android.com/studio/run/emulator-networking)
- [Network simulator](https://developer.android.com/studio/run/emulator-networking-advanced)
- [Emulator command line](https://developer.android.com/studio/run/emulator-commandline)
- [Android-x86 releases](https://www.android-x86.org/releases.html)

## Required hardware and controls

1. Authorized USB-debugging handset running Android 17, actual SDK 37. A
   supported Pixel 6 with an official matching build is a concrete target;
   another handset is acceptable after verifying its actual model/build/module.
   SDK 37 alone does not prove autonomous-repair feature availability.
2. nRF52840 DK (or equivalent) with firmware supplying stable identity, durable
   bonded keys across restart, an authenticated/encrypted GATT characteristic,
   and an out-of-band command to delete **only the peripheral's Android peer
   key**, without deleting Android's bond or changing the peripheral identity.
   Record firmware revision, characteristic UUID, required security level, and
   the exact firmware-specific erase/restore commands. No generic erase command
   or ready-made firmware is supplied by this runbook.
3. Peripheral serial/security logging and repeatable baseline restoration. A
   second controlled peer is required for the device-switch isolation subcase.
   ESP32/Bumble-on-USB may substitute only after equivalent controls are proven.
   A host Bluetooth dongle by itself does not meet these requirements.

Operate only on authorized test peers. Never clear phone-wide Bluetooth data,
wipe an AVD between retained-bond observations, or pair nearby consumer devices.

## Reproduce the diagnostic setup (known failing configuration)

These are runtime-image diagnostics, not a repair test or a recommendation to
change the product SDK. Run from a host with Android SDK command-line tools,
accepted SDK licenses, usable KVM, sufficient disk, and at least 4 GiB available
for the emulator. Package revisions can change; record `source.properties`
and emulator version on every attempt. The recorded installation used emulator
37.2.12.0 build 16428233 / netsimd 1.0.23 and these images:

| Package | Observed revision |
| --- | --- |
| `system-images;android-37.0;google_apis;x86_64` | 6 |
| `system-images;android-37.1;google_apis_ps16k;x86_64` | 9 |

```sh
sdkmanager 'emulator' 'system-images;android-37.0;google_apis;x86_64'
printf 'no\n' | avdmanager create avd --name quick_blue_api37 --package 'system-images;android-37.0;google_apis;x86_64' --device pixel_6
sdkmanager 'system-images;android-37.1;google_apis_ps16k;x86_64'
printf 'no\n' | avdmanager create avd --name quick_blue_api37_1 --package 'system-images;android-37.1;google_apis_ps16k;x86_64' --device pixel_6
```

Use new diagnostic AVD names; do not overwrite an existing test AVD. Before
first boot, set `disk.dataPartition.size=6G` in each new AVD's `config.ini`
(normally under `~/.android/avd/<name>.avd/`). The default 800M partition filled
and caused Bluetooth config-storage crashes. Enlarging it fixed that capacity
problem, **not** the graphics failure. Wipe only disposable diagnostic AVDs if
needed to apply partition changes, never retained-bond scenario state.

The scenario phase re-ran this invocation without wiping or snapshots:

```sh
"$ANDROID_SDK_ROOT/emulator/emulator" -avd quick_blue_api37_1 -port 5554 \
  -no-window -no-audio -no-boot-anim -no-snapshot -gpu swangle \
  -feature -Vulkan -memory 4096 -cores 2 \
  -netsim-args '--pcap --hci-port 8877'
```

In another terminal, select the exact diagnostic serial (5554 must be free):

```sh
adb -s emulator-5554 shell getprop ro.build.version.sdk
adb -s emulator-5554 shell getprop ro.build.version.release
adb -s emulator-5554 shell getprop ro.build.fingerprint
adb -s emulator-5554 shell getprop ro.build.version.security_patch
adb -s emulator-5554 shell getprop sys.boot_completed
adb -s emulator-5554 shell cmd bluetooth_manager enable
adb -s emulator-5554 shell dumpsys bluetooth_manager
adb -s emulator-5554 shell pm list packages --apex-only --show-versioncode
adb -s emulator-5554 logcat -d -b crash
adb -s emulator-5554 shell pidof surfaceflinger
adb -s emulator-5554 emu kill
adb devices -l
```

Use bounded boot waits; inspect dump content, not just command exit status.
One `wait-for-state:STATE_ON` attempt printed failure but returned exit 0.
`boot_completed=1` also preceded later graphics restarts in the 37.0 attempt.
Require sustained UI/stack stability before any pairing case. If reproducing,
stop the failing emulator rather than leaving it crash-looping.

## Actual evidence and limits

Provisioning tried 37.0 SwiftShader (host SIGSEGV), swangle/Vulkan off,
6G data with GLDMA/GLDMA2 disabled, and 37.1 swangle and Xvfb/Mesa host rendering.
All failed to establish stable graphics. The independent scenario rerun found:

- SDK 37, Android 17, patch `2026-07-05`.
- Fingerprint `google/sdk_gphone16k_x86_64/emu64xa16k:17/CP31.260623.012/16064790:userdebug/dev-keys`.
- Bluetooth APEX `com.google.android.bt` versionCode `371899999`.
- Bluetooth ON, zero Bluetooth crashes and zero bonds in the captured dump.
- Empty `sys.boot_completed`; final `pidof surfaceflinger` exit 1; crash log
  `RegionSampling` SIGABRT with `!rcEnc->featureInfo()->hasReadColorBufferDma`.
- Emulator stopped; final `adb devices -l` empty.

No APK was built/installed/executed in these provisioning/scenario phases. No
virtual peer, simulated advertisement, injected broadcast, real bond change,
protected GATT transaction, repair feature-flag check or security downgrade
case ran. Graphics failure is not a Bluetooth repair failure.

The scenario checkout was `de25bde157b5a3d1fbf501e8ac7d89ada510b32e`, which
**does not contain** the proposed repair implementation. The intended source
was inspected at `52a71198e41eb02245c23944fd4b718f52a292b2`
([draft implementation PR #11](https://github.com/prefanatic/quick_blue/pull/11)),
but inspecting it is not executing it. This documentation branch is independent
of that implementation. Future device runs must explicitly select the reviewed
implementation or a verified successor, not this documentation checkout alone.

Evidence from tasks `t_94465ab8` and `t_b3188e7e` is retained as task attachments
and in their local `.dart_tool/android17-provisioning/` and
`.dart_tool/android17-scenarios/` directories respectively. The publication task
`t_976c505d` also retains a copy of `android17-scenario-evidence.zip` (27 members,
CRC checked), including command records, guest properties, image metadata,
Bluetooth/crash dumps, collector, report and machine-readable scenario matrix.
SHA-256: `d38184e46d5f9d84472851eeb682835d7754eb0cf851ee10cae955a9d45326cf`.
These archives are local/task evidence, not public GitHub downloads. Raw startup
logs are excluded from the scenario archive because they can contain adb public
keys. Review/redact identifiers and never publish bond keys, PINs or credentials.

## Hardware-arrival runbook (not executed)

1. Select physical `SERIAL` from `adb devices -l`. Record model, SDK, release,
   fingerprint, patch, Bluetooth module/package version and feature availability
   using `adb -s "$SERIAL" shell getprop`, APEX/package metadata and
   `dumpsys bluetooth_manager`. Stop if SDK is not 37 or hardware controls fail.
2. Select the reviewed implementation checkout; record `git rev-parse HEAD`,
   `flutter --version`, firmware revision and APK SHA-256. From repository root
   run `flutter pub get`; from `quick_blue/example` run
   `flutter run -d "$SERIAL"`. Grant Bluetooth permissions and save app output.
   Build/install provenance must match the source under test. The general BLE
   smoke test alone does not exercise this matrix.
3. Before each case capture `adb -s "$SERIAL" logcat -v threadtime`, before/after
   Bluetooth dumps, peripheral serial/security logs and screenshots/video of
   the actual system dialog. Record timestamps and redact before publication.
4. Establish durable BONDED state and a successful protected GATT read at the
   recorded negotiated security level. Restore this baseline independently for
   each remote-loss case. Erase only the peripheral key via its documented
   out-of-band command, retaining phone bond and peripheral identity; reconnect
   and perform the protected read.
5. Record actual OS repairing context, key-loss and LE encryption signals,
   app recovery/generation and pairing calls. For the proposed observer, explicit
   repairing context establishes a repair; correlated enabled LE encryption
   with status 0 establishes success; KEY_MISSING during active repair is a
   failure signal. Retained BONDED alone is not success and BOND_NONE alone is
   not remote key loss. Compare these expectations with the installed source
   and real OEM ordering. Never inject broadcasts as device evidence.
6. Run separate accept/reject/ignore cases. For delayed confirmation, timestamp
   dialog appearance and wait at least 35 measured seconds before accepting.
   Record early OS dismissal, any competing app pairing at 30 seconds and the
   actual result. For ignore, declare a measured observation window and report
   unresolved if no terminal arrives, rather than inventing a failure.
7. Restore baseline for Settings Forget; remove only the controlled peer via
   Settings. This is not the peripheral-only key-loss case. Separately exercise
   a second protected operation, disconnect/reconnect, second-peer switching
   and engine teardown during repair; record each subcase and ensure an old
   generation cannot settle new work or initiate overlapping pairing. Unit-test
   late-event replay must remain labelled mocked.
8. Record each case's actual trigger, bond/security state, action and duration,
   terminal OS/app signals, read result, pairing-call/dialog counts and evidence
   filenames. Restore only controlled peer state. Add lower-security and
   Android 16/older hardware comparisons separately; those remain unverified.

## Scenario matrix from the attempted run

| Case | Status | Evidence needed when hardware arrives |
| --- | --- | --- |
| Initial durable bond/protected read | NOT RUN | Bond, peer key, identity and negotiated security |
| Peripheral-only key deletion | NOT RUN | Peer erase log and phone retained bond |
| Accept repair | NOT RUN | Real dialog/action, terminal and protected read |
| Reject repair | NOT RUN | Real rejection and actual app/OS result |
| Ignore repair | NOT RUN | Measured window and actual timeout/unresolved result |
| Confirmation >30 seconds | NOT RUN | At least 35 seconds measured; no competing pairing |
| Settings unpair | NOT RUN | Settings action and distinct bond/app transition |
| Success terminal | NOT RUN | Repair-context-correlated enabled LE encryption |
| Failure terminal | NOT RUN | Actual correlated failure or unresolved evidence |
| Stale/competing pairing | NOT RUN | Per-subcase generations, calls and dialog counts |

Only replace NOT RUN after executing that case and linking its evidence.
Bluetooth ON, a successful build, mocks, CI or a simulated connection must not
release the hardware capability blocker. Root task `t_f88bac2c` must remain
capability-blocked until the handset and validated peripheral are available.
