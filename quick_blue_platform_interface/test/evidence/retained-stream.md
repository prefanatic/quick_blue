# Retained raw characteristic stream: red evidence

Starting revision: `0596865a0a46e18f7dc6d56561a79f538cf7bcea`, freshly fetched
`origin/master` from prefanatic/quick_blue, identical to the audit baseline.
The dispatcher-created isolated worktree initially pointed at
`de25bde157b5a3d1fbf501e8ac7d89ada510b32e`; the feature branch was created
from freshly fetched upstream instead. No production files were changed.

Environment: Linux, Flutter 3.47.6, Dart 3.13.5.

Reproduce from repository root:

```sh
flutter pub get
dart format quick_blue_platform_interface/test/retained_characteristic_value_stream_test.dart
(cd quick_blue_platform_interface && flutter test test/retained_characteristic_value_stream_test.dart --reporter expanded)
(cd quick_blue_platform_interface && flutter test --reporter expanded)
flutter analyze quick_blue_platform_interface
git diff --check
```

The targeted test executed: 0 passed, 1 failed, exit 1. Initial delivery `[1]`
passed before cancellation; after listening again to the exact retained stream,
the expected new delivery `[[2]]` was actually empty. The full package suite
executed: 211 passed, 1 failed, exit 1; only the added regression failed.
The adjacent `.txt` files preserve actual command output (trailing whitespace
stripped to satisfy the repository whitespace gate), including failure
location and observed/expected values. Absolute paths in those logs reflect
the original isolated checkout and are not needed to reproduce.

Analysis reported no issues. Documentation validation passed with 19 concepts
and 73 local links; the clean Zensical build and site checker passed with 20
navigation pages and 1088 local HTML links/anchors. `git diff --check` passed.

This establishes Dart keyed routing under injected platform events only. It
neither enables nor verifies native notifications; no hardware claim is made.
Production behavior and the public contract are unchanged, so canonical GATT
docs, README and changelog are intentionally not changed in this red-only step.

Open upstream PRs inspected before editing: #1, #7, #10, #11 and #12. None
touched this new test or its evidence files. The downstream implementation owns
`lib/src/characteristic_lifecycle.dart` and may extend this regression; this step
owns only the new test and evidence. The upstream PR/final green verification
belong to the downstream implementation/release stages, not this red-only branch.
