# Opt-in snapshot-bound characteristic implementation evidence

Proof boundary: executable fake-platform tests establish the additive Dart
snapshot-validity contract only. No native reconnect generations, schema identity,
native rollback, or hardware-bound validity behavior is established.

## Revisions and launch gates

- Fresh upstream baseline: 0596865a0a46e18f7dc6d56561a79f538cf7bcea.
- Red API stub + regression/evidence: 9249387b70b51b4d7c34d4dade8e350ed3bcb60d.
- Implemented source + app-facing compilation test:
  078c0588d5ebe733be60e2e8a4d682f3ed6b06eb.
- Branch: feature/snapshot-bound-characteristics, based on fetched origin/master.
- Isolated worktree was initially clean; unrelated worktrees were not modified.
- Configured active provider/model/effort were openai-codex/gpt-6.1-sol/low;
  runtime also identified openai-codex/gpt-6.1-sol. No configuration changed.
- Open PR file inspection found no overlap with the implementation files. PR #14
  changes characteristic_lifecycle.dart and docs/gatt.md; neither was edited here.
- Unmerged-commit file inspection across 104 local branches found only this
  branch's own red commit touching the implementation/test target set.

## Executed checks

Commands below are relative to the isolated repository root unless specified.
Output is tracked beside this file; filenames are prefixed snapshot-bound-.
Trailing log whitespace was normalized for the diff-check gate; result content
is unchanged. The baseline-to-final diff-check initially found trailing log
whitespace, then passed after normalization.

Baseline before edits, at 0596865a:

- `flutter pub get`: success.
- `(cd quick_blue_platform_interface && flutter test --reporter expanded)`:
  211 passed, 0 failed; baseline-interface.txt.
- `(cd quick_blue && flutter test --reporter expanded)`:
  88 passed, 0 failed; baseline-facade.txt.
- `flutter analyze`: no issues; baseline-analyze.txt.

Red, with boundCharacteristic deliberately delegating to an unbound handle:

- `(cd quick_blue_platform_interface && flutter test test/snapshot_bound_characteristic_test.dart --reporter expanded)`:
  3 passed, 9 failed; red.txt. Eight failures are missing invalidState assertions;
  the notifications failure is a 30-second timeout waiting for an error the
  unguarded stream never emits. This is not a compile-only red.

Green, on the implemented source tree at 078c0588:

- `dart format quick_blue_platform_interface/lib/src/bluetooth_characteristic.dart quick_blue_platform_interface/lib/src/bluetooth_device.dart quick_blue_platform_interface/lib/src/bluetooth_gatt.dart quick_blue_platform_interface/test/snapshot_bound_characteristic_test.dart quick_blue/test/snapshot_bound_public_api_test.dart`:
  touched handwritten files formatted (executed in two batches).
- `(cd quick_blue_platform_interface && flutter test test/snapshot_bound_characteristic_test.dart --reporter expanded)`:
  12 passed, 0 failed; targeted-green.txt.
- `(cd quick_blue_platform_interface && flutter test --reporter expanded)`:
  223 passed, 0 failed; interface-green.txt.
- `(cd quick_blue && flutter test --reporter expanded)`:
  89 passed, 0 failed; facade-green.txt.
- `flutter analyze`: no issues; analyze-green.txt.
- `(cd quick_blue/example && QUICK_BLUE_HIDE_TEST_WINDOW=1 xvfb-run -a flutter test integration_test/ble_smoke_test.dart -d linux)`:
  1 passed, 0 failed; linux-smoke.txt. Linux example built and generic BLE
  scan/connect/discovery/read/disconnect completed. No write define was supplied.
  This smoke does not exercise snapshot-bound handles or prove native notification
  behavior. The discovered device identifier in the retained log is redacted.
- `python3 -m venv .dart_tool/docs-venv` and
  `.dart_tool/docs-venv/bin/pip install -r scripts/requirements-docs.txt`: success.
- `.dart_tool/docs-venv/bin/python scripts/check-okf.py`:
  19 concepts, 73 local links pass; okf.txt.
- `git diff --check`: success.

## API and test coverage

One additive supported public method: BluetoothGatt.boundCharacteristic(uuid,
{service}). Resolution uses the same invalidState/notFound/ambiguous lookup as
characteristic(). BluetoothDevice.snapshotBoundCharacteristic is annotated
internal; existing public direct-ID signatures are unchanged.

A private validity closure checks at read/write/setNotifiable entry, before
instrumentation and native submission. notifications checks when listened to,
before acquiring a native notification claim; rejection is a stream error.
writeInChunks checks each new chunk through write. Existing security recovery is
part of the already-started operation and is unchanged. valueStream and payload
capacity queries are not submissions and are unguarded. Cancellation of an
already-acquired notification claim still performs existing teardown.

The 12 focused tests cover:

- Invalidated read; both write modes; notification, indication and disable calls:
  invalidState with operation and full characteristic context, calls unchanged.
- A stream obtained before invalidation rejects at listen with no setup call.
- Rediscovery returns fresh bound handles that read/write/subscribe successfully.
- Direct-ID device methods and default gatt.characteristic handles still submit.
- A write already submitted completes normally across invalidation: no rollback.
- Chunk one completes; chunk two fails validity without a second submission.
- Disconnect and reconnect do not invalidate the snapshot under today's policy;
  only a later service-changed event invalidates it. This policy was not changed.

The facade test compiles the method through package:quick_blue/quick_blue.dart.
Existing GATT and connection/discovery suites also passed in the full run.

## File ownership and remaining phases

Implementation changed only:

- quick_blue_platform_interface/lib/src/bluetooth_gatt.dart
- quick_blue_platform_interface/lib/src/bluetooth_characteristic.dart
- quick_blue_platform_interface/lib/src/bluetooth_device.dart
- quick_blue_platform_interface/test/snapshot_bound_characteristic_test.dart
- quick_blue/test/snapshot_bound_public_api_test.dart
- quick_blue_platform_interface/test/evidence/snapshot-bound-* (tracked evidence)

No native, Pigeon, generated, generation-policy, or lifecycle-coordinator source
was changed. Native-specific checks are not applicable to this Dart-only change.

Public migration docs, OKF concepts, README entrypoints and changelogs are affected
but intentionally owned by the separately pre-created documentation phase. This
implementation is a phase handoff, not final feature readiness or PR publication.
That phase must consume this source, update the canonical docs in the same eventual
PR, and run the complete documentation gate. Independent review and upstream PR
publication remain separate downstream phases; their planning-only authorization
requirements are not waived by this implementation completion.
