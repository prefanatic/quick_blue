# Stale sink repair evidence

Parent candidate: 93d13bf4af883874faf50cc5a656fef0e2c1c311. This revision extends that exact candidate without resetting it.

Adapted the independent reviewer probe into the tracked lifecycle suite. Before the production change, `(cd quick_blue_darwin && flutter test test/l2cap_lifecycle_test.dart --reporter expanded)` returned exit 1: 13 passed, 1 failed; stale native close count expected 0, actual 1 (`stale-red.txt`). Adding a disposed guard to sink.close makes the identical suite pass all 14 (`stale-green.txt`).

Additional regressions cover delayed successful/failed close replies and delayed write failure after remote close and replacement open. `_dispose` is idempotent before invoking map removal, so a late old close reply cannot remove the new session. Write completion only reports errors; it does not remove sessions or submit additional native operations. Disposed failures remain observable through FlutterError.reportError rather than being injected into a replacement socket stream.

Executed checks (all exit 0 after repair):

- `flutter pub get`: stale-pub.txt
- `dart format quick_blue_darwin/lib/src/quick_blue_darwin.dart quick_blue_darwin/test/l2cap_lifecycle_test.dart`: clean
- `(cd quick_blue_darwin && flutter test test/l2cap_lifecycle_test.dart --reporter expanded)`: 14 passed
- `(cd quick_blue_darwin && flutter test --reporter expanded)`: 47 passed, stale-package.txt
- `(cd quick_blue && flutter test --reporter expanded)`: 88 passed, stale-facade.txt
- `flutter analyze`: no issues, stale-analyze.txt
- `PATH=$HOME/.local/opt/swift/usr/bin:$HOME/.local/opt/swift/bin:$PATH ./quick_blue_darwin/darwin/quick_blue_darwin/type_check/run.sh`: stub type-check and 1 existing write test passed, stale-swift.txt (nonfatal libtinfo warnings)
- `python3 -m venv .dart_tool/docs-venv` and `.dart_tool/docs-venv/bin/pip install -r scripts/requirements-docs.txt`: success
- `.dart_tool/docs-venv/bin/python scripts/check-okf.py`: 19 concepts/73 links pass
- `.dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p test_check_okf.py`: 13 passed
- `.dart_tool/docs-venv/bin/zensical build --clean`: success
- `.dart_tool/docs-venv/bin/python scripts/check-docs-site.py`: 20 pages/1096 links pass
- `git diff --check`: clean

Docs gates are in stale-docs.txt. Canonical docs/l2cap.md and quick_blue/CHANGELOG.md now describe stale cleanup and delayed reply isolation. README already links directly to that concept; index and Darwin restoration docs do not need changes. Receive example remains unchanged, and its finally sink.close is the scenario exercised by the regression.

Proof boundary: fake messenger tests establish Dart-to-host request and callback isolation only. Swift/schema/generated sources remain unchanged. No Apple host or peripheral is available here; native nil-channel and physical Apple L2CAP behavior remain unverified. No push, PR publication, or package publication performed. Existing review/publication cards own downstream delivery.
