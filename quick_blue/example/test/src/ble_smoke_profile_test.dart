import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_blue_example/src/ble_smoke_profile.dart';

void main() {
  group('BleSmokeProfile', () {
    test('loads built-in Valve Lighthouse profile', () {
      final profile = BleSmokeProfile.builtIn(valveLighthouseSmokeProfileName);

      expect(profile, isNotNull);
      expect(profile?.targetNamePattern, contains('LHB-'));
      expect(profile?.expectedManufacturerDataHex, '00 02');
      expect(profile?.connect, isFalse);
      expect(profile?.read, isFalse);
      expect(profile?.targetsDevice, isTrue);
    });

    test('parses custom JSON profile', () {
      final profile = BleSmokeProfile.fromJson('''
        {
          "name": "desk",
          "deviceId": "AA:BB:CC:DD:EE:FF",
          "namePattern": "Sensor",
          "serviceUuids": ["180f"],
          "expectedAdvertisedServiceUuids": "180a, 180f",
          "expectedServiceUuids": ["1800"],
          "expectedManufacturerDataHex": "01 02",
          "expectedServiceDataHex": {"180f": "64"},
          "minRssi": -80,
          "connect": true,
          "read": false,
          "maxConnectAttempts": 2
        }
      ''');

      expect(profile.name, 'desk');
      expect(profile.targetDeviceId, 'AA:BB:CC:DD:EE:FF');
      expect(profile.targetNamePattern, 'Sensor');
      expect(profile.serviceUuids, <String>['180f']);
      expect(profile.expectedAdvertisedServiceUuids, <String>['180a', '180f']);
      expect(profile.expectedServiceUuids, <String>['1800']);
      expect(profile.expectedManufacturerDataHex, '01 02');
      expect(profile.expectedServiceDataHex, <String, String>{'180f': '64'});
      expect(profile.minRssi, -80);
      expect(profile.connect, isTrue);
      expect(profile.read, isFalse);
      expect(profile.maxConnectAttempts, 2);
    });

    test('merges custom profile over built-in defaults', () {
      final profile = BleSmokeProfile.builtIn(valveLighthouseSmokeProfileName)!
          .merge(
            const BleSmokeProfile(
              targetDeviceId: 'AA:BB',
              expectedAdvertisedServiceUuids: <String>['180f'],
              minRssi: -70,
            ),
          );

      expect(profile.targetNamePattern, contains('LHB-'));
      expect(profile.targetDeviceId, 'AA:BB');
      expect(profile.expectedAdvertisedServiceUuids, <String>['180f']);
      expect(profile.minRssi, -70);
      expect(profile.connect, isFalse);
    });
  });

  group('hexBytes', () {
    test('parses separated hex', () {
      expect(hexBytes('0x01 02:ff', 'value'), Uint8List.fromList([1, 2, 255]));
    });

    test('rejects malformed hex', () {
      expect(() => hexBytes('0x0', 'value'), throwsArgumentError);
      expect(() => hexBytes('zz', 'value'), throwsArgumentError);
    });
  });

  test('hasBytePrefix compares byte prefixes', () {
    expect(
      hasBytePrefix(Uint8List.fromList([1, 2, 3]), Uint8List.fromList([1, 2])),
      isTrue,
    );
    expect(
      hasBytePrefix(Uint8List.fromList([1]), Uint8List.fromList([1, 2])),
      isFalse,
    );
  });

  test('hexString formats bytes for profile JSON', () {
    expect(hexString(Uint8List.fromList([0, 1, 255])), '00 01 ff');
  });
}
