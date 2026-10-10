# Retained raw characteristic stream: green evidence

Implementation starts from regression commit
`7329b7a05c7d43e64f845be7fced4a8b6947eb66`, whose original red evidence is
preserved unchanged in `retained-stream.md` and the adjacent red logs.
Upstream `origin/master` was fetched again and remains
`0596865a0a46e18f7dc6d56561a79f538cf7bcea`.

The keyed registry now tracks a set of controllers for each normalized key.
A retained broadcast stream registers its own controller on re-listen. Final
cancellation removes only that controller, and removes the key only when no
controllers remain. Both exact service events and legacy empty-service events
are forwarded to all registered controllers. Getter object identity is not a
new public guarantee; the behavior established here is delivery to active
listeners, including retained and freshly obtained streams for the same key.
There is no replay guarantee and no change to native notification setup/teardown.

Executed from repository root on Linux with Flutter 3.47.6 / Dart 3.13.5:

```sh
flutter pub get
dart format quick_blue_platform_interface/lib/src/characteristic_lifecycle.dart quick_blue_platform_interface/test/retained_characteristic_value_stream_test.dart
(cd quick_blue_platform_interface && flutter test test/retained_characteristic_value_stream_test.dart --reporter expanded)
(cd quick_blue_platform_interface && flutter test --reporter expanded)
(cd quick_blue && flutter test --reporter expanded)
flutter analyze
```

Results: targeted 6 passed; platform-interface 217 passed; quick_blue 88 passed;
analysis no issues. All commands above exited 0. Adjacent `*-green.txt` files
retain real test/analysis output with trailing whitespace stripped. The original
retained-stream regression now passes. Four additional overlap cases cover both
cancellation orders under exact and legacy service events; another case covers
overlapping subscriptions on one controller and subsequent re-listening.
Every new case asserts that raw-stream use made no native API calls.

Documentation validation also executed successfully:

```sh
python3 -m venv .dart_tool/docs-venv
.dart_tool/docs-venv/bin/pip install -r scripts/requirements-docs.txt
.dart_tool/docs-venv/bin/python scripts/check-okf.py
.dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p 'test_check_okf.py'
.dart_tool/docs-venv/bin/zensical build --clean
.dart_tool/docs-venv/bin/python scripts/check-docs-site.py
git diff --check
```

Results: 19 concepts / 73 local links; 13 checker tests passed; clean site build
passed; 20 navigation pages / 1088 HTML links and anchors passed, with search
assets present. Open upstream PRs #1, #7, #10, #11 and #12 were re-inspected;
none touches the scoped lifecycle source or retained-stream test/evidence files.

An initial evidence-collection invocation mistakenly used persistent relative
working directories; the invalid package commands failed before running tests.
Those temporary misplaced files were removed and all reported commands rerun
from the explicit repository root. Only successful rerun logs are tracked.

This is Dart routing evidence under injected events, not hardware notification
proof. No native, Pigeon, notification acquisition/release, or public API files
were changed. Native builds and hardware runs are not applicable to this scoped
raw-routing correction; native delivery remains unverified. The serialized
documentation child owns canonical GATT/README/changelog updates; the verification
and delivery children own independent review and upstream PR publication.
