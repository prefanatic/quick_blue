import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import 'test_support/fake_quick_blue_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BluetoothDevice exposes ranging capabilities', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final capabilities = await platform
        .device('device-a')
        .rangingCapabilities();

    expect(capabilities.isAvailable, isTrue);
    expect(capabilities.supportsDirection, isTrue);
    expect(platform.calls, <String>['rangingCapabilities device-a']);
  });

  test('ranging session forwards options, measurements, and stop', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);
    const options = BleRangingOptions(
      requestDirection: true,
      updateRate: BleRangingUpdateRate.frequent,
    );

    final session = await platform
        .device('device-a')
        .startRanging(options: options);
    final measurementsFuture = session.measurements.toList();
    final timestamp = DateTime(2026, 7, 25);
    platform.addRangingMeasurement(
      BleRangingMeasurement(
        deviceId: 'device-a',
        timestamp: timestamp,
        distanceMeters: 1.25,
        azimuthDegrees: -15,
        rssi: -42,
        distanceConfidence: BleRangingConfidence.high,
      ),
    );

    await pumpEventQueue();
    await session.stop();
    await session.stop();

    final measurements = await measurementsFuture;
    expect(measurements, hasLength(1));
    final measurement = measurements.single;
    expect(measurement.deviceId, 'device-a');
    expect(measurement.timestamp, timestamp);
    expect(measurement.distanceMeters, 1.25);
    expect(measurement.azimuthDegrees, -15);
    expect(measurement.rssi, -42);
    expect(measurement.distanceConfidence, BleRangingConfidence.high);
    expect(platform.lastRangingOptions, options);

    expect(platform.calls, <String>[
      'startRanging device-a',
      'stopRanging device-a',
    ]);
  });

  test('only one ranging session can be active per device', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);

    final first = await platform.device('device-a').startRanging();

    await expectLater(
      platform.device('device-a').startRanging(),
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.deviceBusy,
        ),
      ),
    );

    await first.stop();
    final second = await platform.device('device-a').startRanging();
    await second.stop();
  });

  test('a failed native start releases the ranging session claim', () async {
    final platform = FakeQuickBluePlatform()
      ..startRangingError = const QuickBlueException(
        code: QuickBlueErrorCode.unavailable,
        operation: 'startRanging',
        message: 'not ready',
      );
    addTearDown(platform.dispose);

    await expectLater(
      platform.device('device-a').startRanging(),
      throwsA(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.unavailable,
        ),
      ),
    );

    platform.startRangingError = null;
    final session = await platform.device('device-a').startRanging();
    await session.stop();
  });

  test('native ranging failures are emitted on the session stream', () async {
    final platform = FakeQuickBluePlatform();
    addTearDown(platform.dispose);
    final session = await platform.device('device-a').startRanging();
    final errorExpectation = expectLater(
      session.measurements,
      emitsError(
        isA<QuickBlueException>().having(
          (error) => error.code,
          'code',
          QuickBlueErrorCode.operationFailed,
        ),
      ),
    );

    platform.addRangingError(
      'device-a',
      const QuickBlueException(
        code: QuickBlueErrorCode.operationFailed,
        operation: 'ranging',
        deviceId: 'device-a',
        message: 'lost peer',
      ),
    );

    await errorExpectation;
    await session.stop();
  });
}
