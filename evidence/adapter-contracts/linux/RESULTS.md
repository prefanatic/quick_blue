# Linux Dart adapter contract evidence

## Source and ownership

Production source: freshly fetched upstream master
`0596865a0a46e18f7dc6d56561a79f538cf7bcea`.
Case specification: plan commit
`51f98c665252556ee2ed1f0448862c2c07ac46b2`.
No predecessor production commits are required or included. In particular open
PRs #14/#15, #19, #20 and #23 are not assumed merged. The previous worktree
branch at `9249387` is preserved; implementation uses `test/linux-adapter-contracts`
from upstream instead. Fixture/test SHA is the commit containing this report.

Only the two new Linux-local test/fixture files and this evidence directory are
owned here. No production, schema, generated, existing GATT fixture, wrapper,
workflow, README or changelog file is edited.

## Executed cases

All 17 cases execute without platform skips or system D-Bus:

| Family | Cases | Observed assertions |
| --- | ---: | --- |
| R1 | 1 | Cached setup [0], pending read, notification [9], direct return [1,2]; events retain both notification and direct value. |
| R2 | 1 | Two devices and two services with 2a19; UUID aliases route correctly, canonical event identity; read/write/notify select the correct fake; write command type is forwarded. |
| R3 | 6 | Read/write/notify preserve authorization reason, domain, null native code, operation and original caller context; BlueZ Failed and arbitrary StateError propagate unchanged. |
| R4 | 6 | Matching listeners share start and final stop; conflicting modes fail; failed setup installs no watcher; disconnect clears watchers despite stop failure; pending cancel success stops once and pending failure stops zero times; explicit disable failure retains its watcher until disconnect. |
| R5 | 1 | Every capability field; pair/query and service-filter forwarding; unsupported MTU preserves requested size and operation; unsupported companion enumeration is typed. |
| R6 | 1 | Empty-service inherited dispatcher fans out to both services and legacy callback, not other devices; nonempty service does not fan out. Native empty-service read rejects with ArgumentError before fake read. |
| R7 | 1 | Lazy initialization coalesces; callback delivers once; injected lease attaches/detaches; disconnect cleans device and characteristic property watches. |

The empty-service read expectation initially assumed notFound; execution showed
UUID validation throws ArgumentError. The final test deliberately characterizes
that actual boundary rather than promising successful service-less lookup or
universal typed validation. Initial fixture compilation and record-list equality
mistakes were corrected; an early cross-stream barrier assumption was replaced
by a matching-event await for the multi-event R6 assertion. These were test-authoring
errors, not production repairs. No production defect is claimed corrected.

R4 does not claim master settles failed notification streams with done. That
existing shared-lifecycle contract is handled by open #15/#14 and must be retained
and re-executed by the aggregate wrapper lane. Pending cancellation here tests
explicit cancellation and late success/failure only. Test subscriptions are
cancelled in teardown, connection owners disconnected and fake controllers closed.
Finite fake client add/remove streams avoid suggesting a plugin-wide dispose API.

## Commands and results

Host: Linux; Flutter 3.47.6, Dart 3.13.5; bluez 0.8.3, dbus 0.7.15.
Commands run from repository root unless parenthesized:

- `flutter pub get`: exit 0.
- `dart format quick_blue_linux/test/adapter_contract_test.dart quick_blue_linux/test/test_support/adapter_contract_bluez.dart`: passed.
- `(cd quick_blue_linux && flutter test test/adapter_contract_test.dart --reporter expanded)`: 17 passed; three further consecutive reruns each 17 passed.
- `(cd quick_blue_linux && flutter test --reporter expanded)`: 107 passed (includes 17 new cases).
- `flutter analyze`: no issues.
- `python3 -m venv .dart_tool/docs-venv` and `.dart_tool/docs-venv/bin/pip install -r scripts/requirements-docs.txt`: exit 0.
- `.dart_tool/docs-venv/bin/python scripts/check-okf.py`: 19 concepts / 73 local links passed.
- `.dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p 'test_check_okf.py'`: 13 passed.
- `.dart_tool/docs-venv/bin/zensical build --clean`: passed.
- `.dart_tool/docs-venv/bin/python scripts/check-docs-site.py`: 20 pages / 1088 local links and anchors passed.
- `git diff --check`: passed.

Captured final expanded logs: `contracts.log`, `linux-full.log` alongside this report.
An intermediate logging rerun used an unparenthesized cd and subsequent commands
failed on the changed shell cwd; those invocations were rerun from explicit root
and are not counted as test executions. Final logs contain only actual successful
executions, not synthesized responses.

## Documentation and delivery boundaries

This is additive test-only characterization, not changed behavior/API/setup or a
public workflow. Existing canonical concepts were reviewed; no public claim was
changed, so README/changelog/OKF concepts remain unaffected in this leaf. This
report documents the new harness; aggregate documentation ownership remains with
the existing downstream lane, avoiding README, changelog and docs/gatt.md hotspots.

The leaf commit is pushed to the fork feature branch for independent combined
review. Upstream PR publication, shared-doc reconciliation and exact-head CI
read-back belong to the pre-created aggregate delivery lane; leaf completion is
not evidence of PR publication, CI success or merge.

Proof: Dart Linux adapter translation, injected event interleaving, fake BlueZ
resolution and fake lease/property-watch ownership only. No system bus, powered
adapter, physical peripheral, native BlueZ ordering, socket readiness, Windows or
Apple runtime is exercised. Hardware smoke/native builds were not run because no
production/platform behavior changed and they do not prove these injected cases.
Linux native service-less lookup and plugin-wide disposal are excluded by the
tracked plan, not manufactured passing seams. Windows direct correlation has its
own aggregate-gating follow-up. All mapped Linux fake-dependency families execute.
