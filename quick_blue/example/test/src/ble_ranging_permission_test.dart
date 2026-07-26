import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_example/src/ble_ranging_permission.dart';

const _permissionChannel = MethodChannel(
  'com.example.quick_blue_example/permissions',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, null);
  });

  test(
    'requests the Android ranging permission through the host activity',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_permissionChannel, (call) async {
            receivedCall = call;
            return true;
          });

      expect(await requestBleRangingPermission(), isTrue);
      expect(receivedCall?.method, 'requestRangingPermission');
    },
  );

  test('does not invoke the permission channel on other platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_permissionChannel, (call) async {
          callCount++;
          return false;
        });

    expect(await requestBleRangingPermission(), isTrue);
    expect(callCount, 0);
  });
}
