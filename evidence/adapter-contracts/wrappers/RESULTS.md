# Dart wrapper adapter contract evidence

## Scope and source

These tests establish only Dart translation/event contracts against Flutter's
fake binary messenger, not Android, Apple or WinRT runtime/hardware semantics.
No production abstractions, native code, schemas, generated outputs, Linux-owned
files, workflow or dependency-manifest edits are introduced by the harness.

Production/source parent tested: `e32048357d3bafad3f2e1b7b72fa46d0dffbd728`.
The final harness/evidence commit is identified in the delivery handoff. Fixture
hashes and executed counts are retained below/in `counts.json`.

Preserved the original `wt/t_26fd2614` starting commit `9249387`, rather than
resetting its snapshot-bound regressions. Explicitly stacked source:

- Plan `51f98c665252556ee2ed1f0448862c2c07ac46b2` (local `69c1bfb`).
- Notification PR #14/#15 source: `7329b7a`, `d44cfd8`, `384b46b`,
  `5654247`, `88637be`, `a26b7eb` (local `8407b09`, `c56c8b3`, `c0af6ac`,
  `4ef0891`, `2f3941e`, `7d51982`).
- Independently approved Darwin repair `93d13bf` plus `96f53c9` (local `079b249`,
  `b5af94b`), now published as open PR #27 at exact
  `96f53c9ae72b4529c990d5556c28fd0012072c8a`.
- Snapshot PR #19: original `9249387` already present; added remaining
  `078c058`, `bac7b11`, `09b1946`, `81e3908`, `099708e`, `74636b3` (local
  `79dcab2`, `cb4367d`, `b22fa63`, `bcafd0c`, `d75de95`, `e320483`).
  The initial full interface run exposed the preserved red-only scaffold;
  including its existing approved implementation, not a new speculative fix,
  restored the full suite. Snapshot cases are retained, not duplicated here.

Byte-for-byte production comparisons against dependency heads are empty for
Darwin bridge vs `96f53c9`, characteristic coordinator vs `a26b7eb`, and snapshot
handle/device/GATT files vs `74636b3`.

Initial freshly fetched master was `0596865a0a46e18f7dc6d56561a79f538cf7bcea`.
Final fetch found master `0d208c6cd800fdafd9b0f4c4c1bd6c62541cbe2e`, containing
maintenance-validator changes only. PRs #14, #15, #19 and #27 remain open, not
assumed merged. Aggregate delivery must reconcile the newer master, shared docs
and all source dependencies. Leaf fork publication is not aggregate PR/CI proof.

## Case results

Each wrapper executes the same 20 named tests, without platform skips:

| Family | Cases per wrapper | Observed result |
| --- | ---: | --- |
| R1 | 1 | Pending host read receives wrong-service [7] then matching notification [9]; remains pending until host reply. Android/Darwin return direct [1,2]; Windows's inherited void-read fallback returns first matching event [9]. |
| R2 | 1 | Duplicate 2a19 under 180f/180a stays service-isolated; short/uppercase/canonical service and characteristic aliases route; wrong device/characteristic ignored; outgoing write/notify identities preserved. Read identities checked by R1. |
| R3 | 9 | Parameterized read/write/setNotifiable each exercise security, non-security and malformed host error details. Security reason/domain/code and all operation/identity context survive. Non-security/malformed behavior intentionally differs by wrapper. |
| R4 | 4 | Shared enable, conflicting indication rejection, final disable; controlled pending-cancel success/failure; terminal setup failure emits one error then done without consumer cancellation. |
| R5 | 3 | Entire capability object for both injected host gate values; unsupported bonding on Darwin/Windows and L2CAP on Windows; connected lookup argument forwarding; Android event-driven MTU vs Darwin/Windows host-result MTU. |
| R6 | 1 | Empty-service callback deliberately reaches both service-qualified streams, global event stream and legacy callback; nonempty service does not fan out. Not native service-less lookup evidence. |
| R7 | 1 | Listener established before lazy initialization; repeated initialization delivers once; cancelled listener stays silent; Darwin restoration host listen occurs once. Teardown cancels test-owned subscriptions and unregisters generated callbacks/mock channels. |

Standalone green: Android 20, Darwin 20, Windows 20. Two additional full matrix
repeat runs passed 20 in every package (six repeat invocations). Full package
suites: quick_blue 109; Darwin 67; Windows 36; platform_interface 234.
See expanded `contracts-*.txt`, `repeat.txt`, `full-*.txt` and `counts.json`.

## Executed baseline

Created an isolated detached worktree inside `.dart_tool/adapter-baseline` at
`0596865a0a46e18f7dc6d56561a79f538cf7bcea`, copied the exact final six test/fixture
files, ran `flutter pub get`, and ran the same standalone package command for
all three wrappers. Each baseline actually executed 19 passing / 1 failing
case: R4 terminal setup failure timed out awaiting done. No intended guarantee
was silently removed. Existing #15 corrective implementation supplies this
contract on the stacked source; this harness introduces no production repair.
Retained expanded `baseline-*.txt` output records exit 1 in each package.

Initial fixture-development errors (void callback success envelope shape,
Android MTU completion via event, Darwin generated lookup method/host-owned UUID
requirement, and record-vs-byte-list matcher equality) were corrected by tracing
implementation/generated sources. They were fixture assumptions, not production
defects or invented passing evidence.

## Commands and gates

Host Flutter 3.47.6 / Dart 3.13.5. Commands from selected worktree root:

```sh
flutter pub get
# Each of quick_blue, quick_blue_darwin, quick_blue_windows:
(cd PACKAGE && flutter test test/adapter_contract_test.dart --reporter expanded)
# Each above plus quick_blue_platform_interface:
(cd PACKAGE && flutter test --reporter expanded)
flutter analyze
dart format --output=none --set-exit-if-changed quick_blue/test/adapter_contract_test.dart quick_blue/test/test_support/adapter_contract_harness.dart quick_blue_darwin/test/adapter_contract_test.dart quick_blue_darwin/test/test_support/adapter_contract_binding.dart quick_blue_windows/test/adapter_contract_test.dart quick_blue_windows/test/test_support/adapter_contract_binding.dart
.dart_tool/docs-venv/bin/python scripts/check-okf.py
.dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p 'test_check_okf.py'
.dart_tool/docs-venv/bin/zensical build --clean
.dart_tool/docs-venv/bin/python scripts/check-docs-site.py
git diff --check
```

All final commands exit 0. Analysis has no issues; format changed zero files;
OKF 19 concepts/75 local links, 13 checker tests, clean site build and site
20 pages/1155 local links/anchors. Actual validation output is `validation.txt`.

## Documentation and ownership

New harness/evidence files are exactly those assigned in PLAN.md. The leaf adds
this evidence document, not new public behavior/setup/workflow claims. Canonical
docs/README/changelog changes are the explicitly stacked dependency documents.
Conflict reconciliation retained both dependency additions in README/changelog
and all notification/snapshot sources and footnotes in docs/gatt.md. Aggregate
owns the final public coverage entry, shared-document reconciliation and plan
case-status update; no claim that that downstream phase is already done.

## Remaining proof boundaries

Windows has no direct native read-result seam: preserve the event fallback, and
use existing tracked Windows boundary follow-up before aggregate acceptance.
Darwin connected-device UUID requirements are host-owned: Dart forwards even an
empty UUID list and preserves an injected host PlatformException, rather than
inventing a Dart typed unsupported gate. Capability flags are not readiness.

There is no public plugin-wide dispose. R7 does not dispose the production
Darwin restoration subscription; it proves one initialization listen and
removes test-owned messenger handlers. Native callback ordering, native
notification cancellation/setup, Apple/Windows runtime, peripheral behavior,
and hardware readiness remain unverified. No hardware smoke or native build
was represented as proof of these injected Dart interleavings. Linux is owned
and verified separately. Independent combined review and aggregate upstream
PR/head/current-head CI remain downstream phases.

## Fixture SHA-256

```text
6f61d799a62b0f17c94d417b8caf002d88c5bd00395a040b5dac9369aa1f29d2  quick_blue/test/adapter_contract_test.dart
9a0c799627717508f4faa2a2c33fd6bb9e9cca98141d6ad22ac4db1782f7c3be  quick_blue/test/test_support/adapter_contract_harness.dart
1775fc3c4d1a376802e2fad3373e9195f2267549466dfd9977092a8d4f1b2198  quick_blue_darwin/test/adapter_contract_test.dart
62885d217361a890b7f726922820723aa1b9019c554220cd828b85780ca84fbd  quick_blue_darwin/test/test_support/adapter_contract_binding.dart
1775fc3c4d1a376802e2fad3373e9195f2267549466dfd9977092a8d4f1b2198  quick_blue_windows/test/adapter_contract_test.dart
14be819ca6c1f7ac0c4f57c481eacfaf5980b751627a2930394cbc194b6aad01  quick_blue_windows/test/test_support/adapter_contract_binding.dart
```
