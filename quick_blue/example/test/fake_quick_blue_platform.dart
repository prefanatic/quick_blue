import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

import '../../test/test_support/fake_quick_blue_platform.dart' as support;

class FakeQuickBluePlatform extends support.FakeQuickBluePlatform {
  FakeQuickBluePlatform() {
    emitInitialBluetoothState = true;
  }

  BleRangingCapabilities rangingCapabilitiesResult =
      const BleRangingCapabilities(
        availability: BleRangingAvailability.available,
        supportsDirection: false,
      );
  BleRangingOptions? lastRangingOptions;

  @override
  Future<BleRangingCapabilities> rangingCapabilities(String deviceId) async {
    calls.add('rangingCapabilities $deviceId');
    return rangingCapabilitiesResult;
  }

  @override
  Future<void> startRanging(String deviceId, BleRangingOptions options) async {
    calls.add('startRanging $deviceId');
    lastRangingOptions = options;
  }

  @override
  Future<void> stopRanging(String deviceId) async {
    calls.add('stopRanging $deviceId');
  }

  void addRangingMeasurement(BleRangingMeasurement measurement) {
    handleRangingMeasurement(measurement);
  }

  void addRangingError(String deviceId, QuickBlueException error) {
    handleRangingError(deviceId, error);
  }
}
