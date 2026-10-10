# Opt-in snapshot-bound migration documentation evidence

Proof boundary: this phase documents the additive Dart validity contract and
records the documentation validation gate. The Dart tests re-executed below
re-confirm that contract on a fake platform only. Nothing here establishes
native-side rejection, hardware behavior, or rollback of IO already handed to
a platform.

## Revisions and launch gate

- Worktree: isolated project worktree for this task, reset from the stale
  dispatcher HEAD `de25bde` to the coordinated feature-branch base
  `81e3908d5e988158fdfece0410e4e888fbfb38bf` (the parent implementation's
  recorded final SHA, read back from
  `pip-agent-is-here/quick_blue#feature/snapshot-bound-characteristics` with
  `git ls-remote` before checkout).
- Parent implementation, tests and evidence consumed at that exact SHA:
  `BluetoothGatt.boundCharacteristic`, the `@internal`
  `snapshotBoundCharacteristic` device factory, `BluetoothCharacteristic`
  submission guards, the 12-test regression file, the facade compile test,
  and `snapshot-bound.md`.
- Authorization: this card was planning-only until an explicit operator
  instruction to work it; that instruction is the launch authorization.
- Entitlement gate (read-only; no profile or configuration change): the
  active config sets `model.default: gpt-6.1-sol` with
  `provider: openai-codex` (ChatGPT backend base URL), and
  `hermes auth list` shows an `openai-codex` device_code OAuth credential.
  Uncommented `reasoning_effort` keys exist in the config (`low` at the
  agent-level key; `medium` documented as applying to OpenRouter/Nous
  Portal); `hermes config get reasoning_effort` reports the key not set at
  profile level. The parent implementation run recorded its effective runtime
  as openai-codex/gpt-6.1-sol/low. This documentation worker's session header
  reports a different runtime (moonshot / kimi-k2-6); per the standing
  preference not to interrupt running work to switch models, no mid-run
  switch was attempted and no configuration was changed.
- One writer per overlapping file set: the parent implementation phase had
  completed and handed docs/README/changelog ownership to this card; no other
  active branch or running card holds the coordinated feature branch.
- Open PR overlap inspected at documentation start
  (`gh pr list --repo prefanatic/quick_blue --state open --json number,title,headRefName,files`):
  PR #14 touches `README.md`, `quick_blue/CHANGELOG.md` and `docs/gatt.md`
  (+45/-1, retained value-stream docs); PRs #12, #11, #10, #7 and #1 also
  touch `README.md` and/or `quick_blue/CHANGELOG.md`. This phase made only
  additive edits in distinct sections of those files and did not touch
  PR #14's `characteristic_lifecycle.dart` or its value-stream documentation
  area. `docs/gatt.md` is therefore a recorded merge hotspot for the
  integrator; `README.md` and `quick_blue/CHANGELOG.md` remain cross-PR
  hotspots already flagged by earlier phases.

## Documentation changes (this phase)

- `docs/gatt.md`: new "Opt into snapshot-bound handles" section with
  migration examples (opt-in, rejection semantics per operation, fresh-handle
  resolution after `gattServiceChangedStream`, direct-ID escape hatch,
  characterized disconnect/reconnect policy, evidence-scope note); a
  cross-link from "Resolve a characteristic"; updated frontmatter
  description; the snapshot-bound regression test added as a cited source.
- `docs/index.md`: gatt entry description updated for discoverability.
- `docs/limitations.md`: table row plus verification-gap bullet stating the
  guard is Dart-side and native/hardware rejection is not established.
- `README.md`: one additive sentence in the feature summary paragraph.
- `quick_blue/README.md`: pointer under "Discovering a characteristic" and a
  migration paragraph under "GATT service changes".
- `quick_blue/CHANGELOG.md`: Unreleased/Added entry for
  `BluetoothGatt.boundCharacteristic`.
- Reviewed and deliberately unchanged: `docs/quickstart.md` (default
  ID-only flow remains valid), `docs/connections.md` (no snapshot-validity
  claims), `docs/testing.md`, `docs/maintenance.md`, `CONTRIBUTING.md`
  (process docs; no affected API claims), `docs/capabilities.md`
  (its "snapshot" text is about Bluetooth availability, unrelated).

## Executed documentation validation

Commands from the repository root, per `docs/maintenance.md`:

- `python3 -m venv .dart_tool/docs-venv` and
  `.dart_tool/docs-venv/bin/pip install -r scripts/requirements-docs.txt`:
  success.
- `.dart_tool/docs-venv/bin/python scripts/check-okf.py`:
  `OKF 0.2: 19 concepts; 74 local links; metadata, sources and indexes pass`;
  `snapshot-bound-docs-okf.txt`.
- `.dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p
  'test_check_okf.py'`: 13 tests, OK; `snapshot-bound-docs-tests.txt`.
- `.dart_tool/docs-venv/bin/zensical build --clean`: build finished, no
  issues; `snapshot-bound-docs-site-build.txt`.
- `.dart_tool/docs-venv/bin/python scripts/check-docs-site.py`:
  `20 navigation pages; 1121 local HTML links/anchors pass; search assets
  present`; `snapshot-bound-docs-site.txt`.
- `git diff --check`: exit 0 (working tree; staged check re-run at commit).

## Consistency with executed tests

Executed in this worktree at the documentation base SHA (the docs edits are
Markdown-only):

- `(cd quick_blue_platform_interface && flutter test
  test/snapshot_bound_characteristic_test.dart --reporter expanded)`:
  12 passed, 0 failed.
- `(cd quick_blue && flutter test
  test/snapshot_bound_public_api_test.dart --reporter expanded)`:
  1 passed, 0 failed.

These re-confirm the behaviors the migration text describes: pre-submission
`invalidState` for read/write/setNotifiable, listen-time notification
rejection before setup, fresh bound handles submitting after rediscovery,
unchanged direct-ID defaults, no rollback of an already-submitted write,
per-chunk checks, and disconnect/reconnect preserving the current snapshot
policy while only service-changed events invalidate.

## What this evidence does not establish

- The disconnect/reconnect snapshot policy is documented as the existing
  characterized behavior, not a newly invented guarantee.
- Already-submitted IO is documented as not rolled back.
- Only the additive Dart validity contract is proven; native, platform, and
  hardware behavior remain unverified for bound handles.
