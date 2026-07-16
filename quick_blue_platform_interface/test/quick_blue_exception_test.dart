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

  test('QuickBlueSecurityException exposes structured native error', () {
    const error = QuickBlueSecurityException(
      reason: QuickBlueSecurityErrorReason.peerRemovedPairingInformation,
      nativeDomain: 'CBErrorDomain',
      nativeCode: 14,
      operation: 'writeValue',
      deviceId: 'device-a',
      serviceId: 'service-a',
      characteristicId: 'characteristic-a',
      message: 'Peer removed pairing information',
    );

    expect(error.code, QuickBlueErrorCode.operationFailed);
    expect(
      error.reason,
      QuickBlueSecurityErrorReason.peerRemovedPairingInformation,
    );
    expect(error.nativeDomain, 'CBErrorDomain');
    expect(error.nativeCode, 14);
    expect(error.operation, 'writeValue');
    expect(error.deviceId, 'device-a');
    expect(error.serviceId, 'service-a');
    expect(error.characteristicId, 'characteristic-a');

    final terminalError = error.withRecoveryResult(
      QuickBlueSecurityRecoveryResult.userActionRequired,
    );
    expect(
      terminalError.recoveryResult,
      QuickBlueSecurityRecoveryResult.userActionRequired,
    );
    expect(terminalError.nativeDomain, error.nativeDomain);
    expect(terminalError.nativeCode, error.nativeCode);
  });
}
