import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue/src/availability.g.dart';
import 'package:quick_blue/src/quick_blue_android.dart';

class _NativeAvailability implements QuickBlueAvailabilityApiForNativeInterop {
  bool available = true;
  PlatformException? failure;

  @override
  bool isBluetoothAvailable() {
    if (failure case final error?) throw error;
    return available;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('public Future uses generated synchronous native boundary', () async {
    final native = _NativeAvailability();
    final platform = QuickBlueAndroid(
      availabilityApi: QuickBlueAvailabilityApi(nativeInteropApi: native),
    );
    expect(await platform.isBluetoothAvailable(), isTrue);
    native.available = false;
    expect(await platform.isBluetoothAvailable(), isFalse);
    native.failure = PlatformException(code: 'unregistered-instance');
    await expectLater(
      platform.isBluetoothAvailable(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'unregistered-instance',
        ),
      ),
    );
  });
}
