import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quick_blue/quick_blue.dart';
import 'package:quick_blue_example/main.dart';

const _scanSeconds = int.fromEnvironment(
  'QUICK_BLUE_SWITCH_SCAN_SECONDS',
  defaultValue: 15,
);
const _switchDelayMilliseconds = int.fromEnvironment(
  'QUICK_BLUE_SWITCH_DELAY_MILLISECONDS',
  defaultValue: 600,
);
const _secondConnectTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SWITCH_SECOND_CONNECT_TIMEOUT_SECONDS',
  defaultValue: 15,
);
const _bluetoothReadyTimeoutSeconds = int.fromEnvironment(
  'QUICK_BLUE_SWITCH_BLUETOOTH_READY_TIMEOUT_SECONDS',
  defaultValue: 8,
);
const _firstNamePattern = String.fromEnvironment(
  'QUICK_BLUE_SWITCH_FIRST_NAME_PATTERN',
  defaultValue: 'govee',
);
const _secondNamePattern = String.fromEnvironment(
  'QUICK_BLUE_SWITCH_SECOND_NAME_PATTERN',
  defaultValue: 'nest\\s*hub|nesthub',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'connects another device after backing out of a pending detail connection',
    (tester) async {
      if (!_supportsUiSwitchRegression(defaultTargetPlatform)) {
        markTestSkipped(
          'This UI switch regression targets macOS CoreBluetooth and '
          'Linux BlueZ paths.',
        );
        return;
      }

      final bluetoothAvailable = await _waitForBluetoothAvailable();
      if (!bluetoothAvailable) {
        markTestSkipped(
          'Bluetooth is not powered on, unavailable, or permission was denied.',
        );
        return;
      }

      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MyApp());
      await _waitForEnabledButton(
        tester,
        find.byKey(const ValueKey('ble_scan_button')),
      );

      await tester.tap(find.byKey(const ValueKey('ble_scan_button')));
      await tester.pump();

      final firstPattern = RegExp(_firstNamePattern, caseSensitive: false);
      final secondPattern = RegExp(_secondNamePattern, caseSensitive: false);
      final firstRow = _deviceRow(firstPattern);
      final secondRow = _deviceRow(secondPattern);

      await _waitForDeviceRow(tester, firstRow, _seconds(_scanSeconds, 15));
      await _waitForDeviceRow(tester, secondRow, _seconds(_scanSeconds, 15));

      await _tapVisible(tester, firstRow);
      await _waitForFinder(
        tester,
        find.byKey(const ValueKey('ble_connect_button')),
        const Duration(seconds: 5),
      );

      await tester.tap(find.byKey(const ValueKey('ble_connect_button')));
      await tester.pump();
      await Future<void>.delayed(
        Duration(milliseconds: _positive(_switchDelayMilliseconds, 600)),
      );

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await _waitForDeviceRow(tester, secondRow, const Duration(seconds: 5));
      await _tapVisible(tester, secondRow);
      await _waitForFinder(
        tester,
        find.byKey(const ValueKey('ble_connect_button')),
        const Duration(seconds: 5),
      );

      await tester.tap(find.byKey(const ValueKey('ble_connect_button')));
      await _waitForFinder(
        tester,
        find.text('connected'),
        _seconds(_secondConnectTimeoutSeconds, 15),
      );

      final disconnect = find.text('Disconnect');
      if (disconnect.evaluate().isNotEmpty) {
        await tester.tap(disconnect);
        await tester.pump();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

bool _supportsUiSwitchRegression(TargetPlatform platform) {
  return platform == TargetPlatform.macOS || platform == TargetPlatform.linux;
}

Finder _deviceRow(RegExp namePattern) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    if (key is! ValueKey<String>) {
      return false;
    }
    const prefix = 'ble_device_row_name_';
    if (!key.value.startsWith(prefix)) {
      return false;
    }
    return namePattern.hasMatch(key.value.substring(prefix.length));
  });
}

Future<void> _waitForEnabledButton(WidgetTester tester, Finder finder) async {
  await _waitForCondition(
    tester,
    const Duration(seconds: 8),
    () {
      if (finder.evaluate().isEmpty) {
        return false;
      }
      final button = tester.widget<ButtonStyleButton>(finder);
      return button.onPressed != null;
    },
    'Timed out waiting for enabled button: $finder',
  );
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder,
  Duration timeout,
) async {
  await _waitForCondition(
    tester,
    timeout,
    () => finder.evaluate().isNotEmpty,
    'Timed out waiting for finder: $finder',
  );
}

Future<void> _waitForDeviceRow(
  WidgetTester tester,
  Finder finder,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  var dragOffset = -240.0;
  var attempts = 0;

  do {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }

    final list = find.byKey(const ValueKey('ble_devices_list'));
    if (list.evaluate().isNotEmpty && attempts.isOdd) {
      await tester.drag(list, Offset(0, dragOffset));
      await tester.pump();
      if (attempts % 6 == 5) {
        dragOffset = -dragOffset;
      }
    }
    attempts++;
  } while (DateTime.now().isBefore(deadline));

  fail(
    'Timed out waiting for device row: $finder\n'
    'Visible device rows:\n${_visibleDeviceRows()}',
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _waitForDeviceRow(tester, finder, const Duration(seconds: 5));
  final target = finder.first;
  await tester.ensureVisible(target);
  await tester.pump();
  final rect = tester.getRect(target);
  await tester.tapAt(Offset(rect.left + 24, rect.top + 14));
  await tester.pump();
}

String _visibleDeviceRows() {
  final rows = find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('ble_device_row_name_');
      })
      .evaluate()
      .map((element) => (element.widget.key! as ValueKey<String>).value)
      .toList(growable: false);
  if (rows.isEmpty) {
    return '<none>';
  }
  return rows.join('\n');
}

Future<void> _waitForCondition(
  WidgetTester tester,
  Duration timeout,
  bool Function() condition,
  String failureMessage,
) async {
  final deadline = DateTime.now().add(timeout);
  do {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) {
      return;
    }
  } while (DateTime.now().isBefore(deadline));
  fail(failureMessage);
}

Future<bool> _waitForBluetoothAvailable() async {
  final deadline = DateTime.now().add(
    _seconds(_bluetoothReadyTimeoutSeconds, 8),
  );

  do {
    if (await QuickBlue.isBluetoothAvailable()) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  } while (DateTime.now().isBefore(deadline));

  return false;
}

Duration _seconds(int value, int fallback) {
  return Duration(seconds: _positive(value, fallback));
}

int _positive(int value, int fallback) {
  return value > 0 ? value : fallback;
}
