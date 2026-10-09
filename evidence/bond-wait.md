# Bond-state observation cleanup evidence

Baseline: upstream master 0596865a0a46e18f7dc6d56561a79f538cf7bcea, fetched before work. The isolated implementation worktree originally contained only de25bde above its common ancestor; that patch is identical to upstream 305267b (stable patch-id 766c354eeb6e572f8122ee45d13e5252f7c41838). No unique work or owner checkout was changed when aligning the clean worktree to the baseline.

## Before correction

`bond-wait-baseline-regression.dart.txt` preserves the exact pre-change regression source. To reproduce, copy it to `quick_blue_platform_interface/test/bond_state_wait_test.dart` in an isolated checkout of the baseline, then run:

    flutter pub get
    (cd quick_blue_platform_interface && flutter test test/bond_state_wait_test.dart --reporter expanded)

Executed before editing production code. Exit 1, expected listener count 0, actual 1 after the caller's external Future.timeout expired without any target event. Output: `bond-wait-red.txt`. The baseline test intentionally leaks an observation; the corrected test instead uses the new built-in timeout argument. External Future.timeout remains unable to cancel an underlying future.

The planning phase also executed baseline package suites: platform interface 211 passed, facade 88 passed, analysis clean. Those upstream handoff counts are contextual, not new execution claims from this implementation phase.

## After correction

Executed commands and retained outputs:

    dart format quick_blue_platform_interface/lib/src/bluetooth_device.dart quick_blue_platform_interface/lib/src/operation_wait.dart quick_blue_platform_interface/test/bond_state_wait_test.dart quick_blue/lib/src/quick_blue.dart quick_blue/test/quick_blue_test.dart
    flutter analyze
    (cd quick_blue_platform_interface && flutter test test/bond_state_wait_test.dart --reporter expanded)
    (cd quick_blue_platform_interface && flutter test --reporter expanded)
    (cd quick_blue && flutter test --reporter expanded)

Analysis: no issues. Targeted regressions: 11 passed. Full platform interface: 222 passed. Full facade: 89 passed. All exit 0. Corresponding `*-green.txt` logs are retained beside this file.

The tests exercise actual caller-owned bond stream subscriptions through a counting test-only wrapper. They cover fake-clock deadline and cancellation cleanup without target events, both stopping modes during a pending snapshot and late snapshot errors, independent concurrent waiters targeting different states, snapshot/event race, immediate snapshot success, platform snapshot failure, no-options unbounded behavior and filtering, pre-cancelled token, invalid timeout, and static API forwarding. Clock advancement uses tester.pump, never real sleep. runAsync drains subscription cancellation futures after clock advancement; it does not advance the deadline. Widget-test teardown also checks for outstanding timers.

Development failures were corrected before passing runs: an unavailable TestWidgetsFlutterBinding.pendingTimerCount getter was removed in favor of widget-test timer invariants; awaiting cancellation futures solely inside fake time hung because broadcast cancellation completion needed real microtask draining. No production timeout workaround or weakened listener expectation was introduced.

Documentation checks (all exit 0):

    python3 -m venv .dart_tool/docs-venv
    .dart_tool/docs-venv/bin/pip install -r scripts/requirements-docs.txt
    .dart_tool/docs-venv/bin/python scripts/check-okf.py
    .dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p 'test_check_okf.py'
    .dart_tool/docs-venv/bin/zensical build --clean
    .dart_tool/docs-venv/bin/python scripts/check-docs-site.py
    git diff --check

OKF: 19 concepts validated. Checker tests: 13 passed. Site build: no issues. Site links/navigation/search validated; see `bond-wait-docs-green.txt` for exact totals. Pairing fragment API calls are covered by existing pair delegation tests and new device/facade timeout tests; it is not a claim of executing pairing on hardware.

## Scope and continuation

Only Dart observation was changed. No native, Pigeon, generated output, Android bond-repair harness, or hardware test was changed or executed. No result establishes native bonding, Android repair, or OS pairing semantics. Stop options do not initiate, modify, or cancel bonding. Actual event subscription, timer and token listener cleanup occurs in finally, with immediate StreamQueue cancellation even if next never receives an event.

Canonical docs updated: docs/pairing.md and docs/limitations.md, plus README.md, quick_blue/CHANGELOG.md and public API comments. docs/connections.md remains accurate for connection/discovery/MTU ownership; it does not claim an exhaustive API list. No index description or navigation change is needed. README/changelog are known shared-file overlap hotspots; edits are localized. Independent validation/documentation review and PR publication remain downstream phases, not completed by this evidence.
