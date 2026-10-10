# Windows event-only read boundary

## Source and scope

Verification-only characterization on wrapper source/fixture commit
`39964c2abb45b0a5216b2ad6cb287e727865a73e`. Fresh `git fetch origin`
resolved master to `0d208c6cd800fdafd9b0f4c4c1bd6c62541cbe2e`; the
wrapper stack, not freshly merged master, was executed. See
[wrapper source mapping](../wrappers/RESULTS.md) for explicit unmerged
notification/snapshot/Darwin dependencies and [plan](../PLAN.md) for ownership.
This leaf changes only this directory. No production, native, schema, generated,
manifest or sibling fixture edits. Final evidence commit is recorded in handoff.

## Executable observations

- Existing R1 in `quick_blue/test/test_support/adapter_contract_harness.dart:220`
  runs through Windows binding (`directRead: false`). Wrong-service `180a` event
  [7], then matching `180f` notification [9], arrive while host reply is pending.
  Future remains pending until void success, then returns [9], not a direct
  [1,2] reply. Tracked output: `r1.txt`, 1 passed.
- Additional `read_boundary_test.dart` reuses the exact sibling harness/binding
  without modifying them. Inject only wrong-service [7], complete void host
  success, pump event queue: read remains pending. Subsequent matching [1,2]
  resolves it. This separately excludes the confound that a pending host reply
  alone explains rejection of the wrong-service event. Output:
  `wrong-service.txt`, 1 passed. The [1,2] here is an injected EVENT, not native
  direct-result proof.
- Full Windows package suite: 36 passed (`windows-full.txt`). The evidence-only
  test is outside package auto-discovery and must be invoked explicitly below.

## Implementation trace and limitation

`QuickBlueWindows` implements only `Future<void> readValue` at
`quick_blue_windows/lib/src/quick_blue_windows.dart:147` and inherits
`QuickBluePlatform.readCharacteristicValue` at
`quick_blue_platform_interface/lib/src/quick_blue_platform.dart:709`. The latter
creates a StreamQueue before awaiting readValue, then returns its first matching
value. Service filtering is routing, not operation correlation. Matching events
are not labeled as read responses vs notifications; an early matching notification
can therefore become the read result. Waiting for host success does not replace
already buffered bytes. Legacy empty-service events retain their separately
characterized compatibility semantics (wrapper R6), not service attribution.

Windows Pigeon source `quick_blue_windows/pigeons/messages.dart:151` declares
async void readValue. Native `quick_blue_windows/windows/quick_blue_windows_plugin.cpp`
ReadValueAsync at 1327 reads WinRT bytes, calls SendCharacteristicValue at 1345,
then replies void success at 1349. Source inspection does not establish runtime
callback scheduling or arrival order, and mocks do not run that C++.

R1 is passing CHARACTERIZATION of an unsupported direct-result seam, not a
passing guarantee that read bytes are notification-independent. No repair claimed,
so no red/green corrective proof is claimed. Windows/WinRT build and BLE hardware
were not exercised on this Linux host; neither is required to infer this narrowly
executed Dart fallback, and neither native ordering nor hardware behavior is proven.

## Separately scoped corrective design proposal (not implemented)

If notification-independent reads are required, authorize a separate Windows
Dart/Pigeon/native change: add an async byte-returning host read method, override
readCharacteristicValue to consume that operation's native result, preserve legacy
void readValue and value-event delivery intentionally. Regenerate owning Pigeon
outputs rather than hand-editing. Define compatibility/event duplication and error
semantics before implementation. Regression acceptance: matching notification [9]
while read is pending must still appear in streams but never replace direct [1,2];
wrong service/device/characteristic and concurrent reads must remain isolated;
native errors must preserve identity/security context. Verify generated sync,
Windows builds and real WinRT/peripheral operation separately. Merely filtering
service more strictly or delaying subscription cannot solve operation correlation.
This proposal is not authorization, a production patch, or a direct-result pass.

## Reproduction and validation

From worktree root (Flutter 3.47.6 / Dart 3.13.5, Linux):

```sh
flutter pub get
(cd quick_blue_windows && flutter test test/adapter_contract_test.dart --plain-name 'R1 notification before read reply' --reporter expanded)
(cd quick_blue_windows && flutter test ../evidence/adapter-contracts/windows-read-boundary/read_boundary_test.dart --reporter expanded)
(cd quick_blue_windows && flutter test --reporter expanded)
dart format --output=none --set-exit-if-changed evidence/adapter-contracts/windows-read-boundary/read_boundary_test.dart
flutter analyze
.dart_tool/docs-venv/bin/python scripts/check-okf.py
.dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p test_check_okf.py
.dart_tool/docs-venv/bin/zensical build --clean
.dart_tool/docs-venv/bin/python scripts/check-docs-site.py
git diff --check
```

Final validation output in `validation.txt`: analysis clean; format unchanged;
OKF 19 concepts/75 links; 13 checker tests; clean site build;
20 pages/1155 links. Initial analysis correctly identified flutter_test as absent
from root dependencies. The evidence file is run under Windows package's runner
and dev dependencies; an explicit local lint annotation documents that ownership,
without adding a root dependency. No executable claim was suppressed.

This evidence document is the only new documentation: no API, behavior, supported
platform, setup or public workflow changed. Canonical testing/limitations coverage,
README/changelog and final aggregate PR/current-head CI belong to aggregate writer;
that writer must retain this limitation and explicit evidence-test command.
