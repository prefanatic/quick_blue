import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_platform_interface/quick_blue_platform_interface.dart';

void main() {
  test('QuickBlueGattException exposes structured native status', () {
    const error = QuickBlueGattException(
      status: 5,
      operation: 'readValue',
      deviceId: 'device-a',
      serviceId: 'service-a',
      characteristicId: 'characteristic-a',
      message: 'Characteristic read failed with GATT status 5',
    );

    expect(error.code, QuickBlueErrorCode.operationFailed);
    expect(error.status, 5);
    expect(error.details, 5);
    expect(error.operation, 'readValue');
    expect(error.deviceId, 'device-a');
    expect(error.serviceId, 'service-a');
    expect(error.characteristicId, 'characteristic-a');
  });
}
