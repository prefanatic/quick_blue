# Darwin Dart L2CAP bridge evidence

Baseline: `0596865a0a46e18f7dc6d56561a79f538cf7bcea` (fresh upstream master).
Host: Linux x86_64; Flutter 3.47.6, Dart 3.13.5, installed Swift 6.1.2.
Logs retain execution output with trailing whitespace stripped for diff hygiene.

The implementation and tests in the commit containing this evidence were exercised
before committing. Git blob IDs of those exact files:

- `quick_blue_darwin/lib/src/quick_blue_darwin.dart`: `7d19e65cd2606f0fbd34e723b5735831e83e4988`
- `quick_blue_darwin/test/l2cap_lifecycle_test.dart`: `955627f2761cd229e45ddd923cf08233e0d7599b`

## Executed commands and results

- `flutter pub get`: exit 0.
- `flutter test quick_blue_darwin/test/l2cap_lifecycle_test.dart --reporter expanded`
  on the original bridge before correction: 0 passed, 6 failed, exit 1 (`red.txt`).
  This initial six-case fixture was then expanded with additional failure/lifetime
  cases; the original log is retained, not claimed to match final line numbers.
- Final ten-case fixture copied into a temporary detached worktree of the exact
  baseline, then `flutter pub get` and the same test command: 1 passed, 9 failed,
  exit 1 (`red-final-suite.txt`). This independently confirms the final fixture
  exposes the baseline defects. Temporary worktree removed after execution.
- Same test command on corrected bridge: 10 passed, exit 0 (`green.txt`).
- `(cd quick_blue_darwin && flutter test --reporter expanded)`: 43 passed,
  exit 0 (`package.txt`).
- `(cd quick_blue && flutter test --reporter expanded)`: 88 passed,
  exit 0 (`facade.txt`).
- `flutter analyze`: no issues, exit 0 (`analyze.txt`).
- `dart format quick_blue_darwin/lib/src/quick_blue_darwin.dart quick_blue_darwin/test`:
  completed successfully; final source formatted.
- `PATH="$HOME/.local/opt/swift/usr/bin:$HOME/.local/opt/swift/bin:$PATH" ./quick_blue_darwin/darwin/quick_blue_darwin/type_check/run.sh`:
  exit 0; plugin/generated-source stub compilation and 1 existing native-write
  test passed (`swift.txt`). Nonfatal libtinfo version-information warnings.
- `python3 -m venv .dart_tool/docs-venv` and
  `.dart_tool/docs-venv/bin/pip install -r scripts/requirements-docs.txt`: exit 0.
- `.dart_tool/docs-venv/bin/python scripts/check-okf.py`: 19 concepts,
  73 links pass; exit 0 (`docs.txt`).
- `.dart_tool/docs-venv/bin/python -m unittest discover -s scripts -p 'test_check_okf.py'`:
  13 passed; exit 0 (`docs.txt`).
- `.dart_tool/docs-venv/bin/zensical build --clean`: exit 0 (`docs.txt`).
- `.dart_tool/docs-venv/bin/python scripts/check-docs-site.py`: 20 navigation
  pages, 1096 links/anchors pass; exit 0 (`docs.txt`).
- `git diff --check`: exit 0.
- `git diff --name-only -- quick_blue_darwin/darwin quick_blue_darwin/pigeons quick_blue_darwin/lib/src/messages.g.dart`:
  empty; Swift, schema and generated sources unchanged.

## Contract and limits

The fake messenger exercises listening before host reply, error/closed settlement,
exactly-once sink close, write/close failure delivery, controlled late-open cleanup,
quarantine rejection, listener cancellation/expiry, remote closure and host failure.
The public sink is an EventSink: close cannot be awaited; socket stream errors are
its observable failure channel. A buffered single-subscription socket stream
preserves early events without resubscribing the device-wide native event channel.

Open waits for both readiness and host reply for five seconds. A deadline attempts
close, quarantines that device in this platform instance for at most five more
seconds, closes a controlled late opened channel, and releases the listener.
The native API cannot cancel a pending open and rejects close without an installed
delegate. Cleanup errors without a returned socket use FlutterError.reportError.
This does not guarantee cleanup of events beyond the window or distinguish other
engines/instances using the same device-only event schema.

This evidence proves Dart-to-host ordering/error/cleanup only. Swift stubs and the
existing native-write test do not prove Apple L2CAP semantics. Native nil-channel
error emission and Apple peripheral verification are explicitly excluded, not
fixed or proved. No macOS/iOS host or Apple peripheral run was available here.

Canonical documentation updated: docs/l2cap.md, root README entry point and
quick_blue/CHANGELOG.md. No example code changed; the existing receive example
still uses the public EventSink.close and handles stream errors via await-for.
The index description and Darwin restoration/accessory concept remain applicable
without changes. No packages/releases were published.
