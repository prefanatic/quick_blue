# Notification setup settlement evidence

## Revisions and reproduction

- Fresh upstream master / audit baseline: `0596865a0a46e18f7dc6d56561a79f538cf7bcea`.
- Implementation base: freshly fetched V01 result `384b46bc148a524e806d9d862fd8f6c502969e78` (fork `fix/reusable-characteristic-value-stream`, upstream PR #14; open, not merged at implementation time).
- Red-only regression commit: `5654247cda9dd59a9ed8ff0568770178fd0986fd`.
- Fix and canonical documentation commit: `88637becfc48874749a6ace480e5a4f28d4e94d3`.
- Feature branch: `fix/notification-stream-settlement`. Publication is a separate reviewed phase.

Run from the repository root after `flutter pub get`:

```sh
(cd quick_blue_platform_interface && flutter test test/bluetooth_notifications_test.dart --reporter expanded)
(cd quick_blue_platform_interface && flutter test --reporter expanded)
(cd quick_blue && flutter test --reporter expanded)
flutter analyze
```

The existing notification suite executed 9/9 green before adding regressions at the implementation base. The red commit adds five cases using the existing fake's controllable setup/teardown futures, without changing production code or the fake. `red-final-notifications.txt` records 11 passed / 3 failed (exit 1); `red-platform-interface.txt` records 219 passed / 3 failed (exit 1). The three failures are bounded two-second waits for a missing done event, not compile failures. The tests verify one setup error and no disable call before waiting, never cancel to obtain done, and register cancellation only as test teardown cleanup. `red-notifications.txt` is the earlier equivalent run before adding those pre-wait assertions; final reproduction uses the red commit.

Green executions at the fix commit: notification suite 14 passed, platform-interface 222 passed, app-facing quick_blue 88 passed, root analysis no issues (all exit 0). Raw output and exact commands are in the corresponding `green-*.txt` files.

## Acceptance and correction boundary

1. Immediate terminal setup failure: exactly the original error then done, with no consumer cancellation and no disable. Retry can acquire and release a fresh claim. Red before fix, green afterward.
2. Delayed terminal setup failure: injected values remain buffered during setup and are discarded on failure; exactly error then done and no disable. Retry succeeds. Red before fix, green afterward.
3. Conflicting mode: rejected indication stream emits one invalidState error then done, does not release the notification owner's claim, and that owner still receives values and disables only when cancelled. Red before fix, green afterward.
4. Cancellation during pending setup, followed by late success: cancellation remains pending through enable and disable; exactly one enable and one disable occur, including after repeated cancel and additional event-loop drains. No values/errors/done reach the cancelled consumer. Passed before and after; this is preserved claim behavior, not a newly corrected defect.
5. Cancellation during pending setup, followed by late failure: cancellation completes without a disable or outward events. Passed before and after; no new claim-release correction is asserted.

All nine existing tests remain green, including same-mode shared last-owner teardown, security recovery, values gated by setup, failed-setup retry, mode conflict and failed-disable retry. The minimal fix waits for the handled setup future to settle before closing a failed controller. Closing inside that setup future and awaiting close would create a cycle: automatic onCancel awaits setup. The acquire/release queue and native API calls are unchanged.

The two-second test timeout is only a failure guard for executable tests; production has no new setup deadline. Consumer cancellation still waits for pending setup and does not abort native work. A setup future that never settles can still leave cancellation pending.

## Broader checks

- `(cd quick_blue_linux && flutter test --reporter expanded)`: 90 passed.
- `(cd quick_blue_darwin && flutter test --reporter expanded)`: 33 passed.
- `(cd quick_blue_windows && flutter test --reporter expanded)`: 16 passed.
- `python3 -m venv .dart_tool/docs-venv` and `.dart_tool/docs-venv/bin/pip install -r scripts/requirements-docs.txt`: exit 0.
- `.dart_tool/docs-venv/bin/python scripts/check-okf.py`: 19 concepts / 74 local links, exit 0.
- `.dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p 'test_check_okf.py'`: 13 passed, exit 0.
- `.dart_tool/docs-venv/bin/zensical build --clean`: no issues, exit 0.
- `.dart_tool/docs-venv/bin/python scripts/check-docs-site.py`: 20 navigation pages / 1113 local HTML links, exit 0.
- From `quick_blue/example`: `QUICK_BLUE_HIDE_TEST_WINDOW=1 xvfb-run -a flutter test integration_test/ble_smoke_test.dart -d linux`: built Linux example and passed 1 test, exit 0. This exercises real scanning/connect/discovery/read/disconnect, not controlled notification setup or native notification delivery.
- `dart format quick_blue_platform_interface/lib/src/characteristic_lifecycle.dart quick_blue_platform_interface/test/bluetooth_notifications_test.dart`: no remaining changes.
- `git diff --check`: exit 0. Final branch-to-base whitespace check is also required after staging evidence. Flutter's whitespace-only output lines were stripped in the evidence-only commit; test result text and ordering are unchanged.

No native source or Pigeon schemas changed, so native-specific Swift/Kotlin/C++ and regeneration checks are not applicable. Linux hardware smoke was available and ran; Darwin/Windows/Android hardware notification semantics are not established.

## Documentation and overlap

Canonical `docs/gatt.md` explains terminal settlement, buffered-value discard, retry, mode conflicts, acquired-claim cleanup, pending cancellation and the absence of native abort/deadlines. Root README adds a link; app-facing and platform-interface changelogs record the behavior. Package README and index entry descriptions need no changes because APIs and entry-point descriptions remain accurate.

Source changes are confined to `notifications()` in `characteristic_lifecycle.dart`. Tests remain in `bluetooth_notifications_test.dart`; the fake is reused unchanged. V01's implementation/docs were inherited, not overwritten. Open PR #14 owns the inherited source/docs, while PRs #1/#7/#10/#11/#12 also touch root README/changelog: publication must account for the unmerged V01 dependency and documentation overlap rather than flattening unrelated work.

## Proof boundary

Controlled futures and injected values establish only the shared Dart notification stream/claim state machine. Federated package tests and compilation do not establish native cancellation, native setup acknowledgement, peripheral notification delivery or BLE readiness. The hardware smoke proves its executed connect/discover/read path only. No native cancellation, blanket setup deadline, release publishing, profile/configuration change or provisioning was introduced.
